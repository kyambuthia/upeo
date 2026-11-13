//! Bit-level serialization for compact network packets.
//!
//! Reference: Fiedler, "Serialization Strategies", Gaffer on Games.
//! Uses a 64-bit scratch accumulator flushed in 32-bit little-endian words so
//! arbitrary-bit-width integers, quantized floats, and booleans pack tightly
//! with zero heap allocations.

const std = @import("std");

pub const SerializeError = error{
    BufferOverflow,
    BufferUnderflow,
    ValueOutOfRange,
};

pub fn bitsRequired(comptime min_val: i64, comptime max_val: i64) u6 {
    comptime {
        std.debug.assert(max_val >= min_val);
        const range: u64 = @intCast(max_val - min_val);
        if (range == 0) return 1;
        return @intCast(64 - @clz(range));
    }
}

pub const BitWriter = struct {
    buf: []u8,
    byte_pos: usize = 0,
    scratch: u64 = 0,
    scratch_bits: u6 = 0,

    pub fn init(buf: []u8) BitWriter {
        return .{ .buf = buf };
    }

    pub fn writeBits(self: *BitWriter, value: u32, num_bits: u6) SerializeError!void {
        std.debug.assert(num_bits >= 1 and num_bits <= 32);
        const mask: u64 = if (num_bits == 32) 0xFFFF_FFFF else (@as(u64, 1) << num_bits) - 1;
        self.scratch |= (@as(u64, value) & mask) << self.scratch_bits;
        self.scratch_bits += num_bits;

        if (self.scratch_bits >= 32) {
            if (self.byte_pos + 4 > self.buf.len) return error.BufferOverflow;
            const word: u32 = @truncate(self.scratch);
            std.mem.writeInt(u32, self.buf[self.byte_pos..][0..4], word, .little);
            self.byte_pos += 4;
            self.scratch >>= 32;
            self.scratch_bits -= 32;
        }
    }

    pub fn writeBool(self: *BitWriter, v: bool) SerializeError!void {
        return self.writeBits(@intFromBool(v), 1);
    }

    pub fn writeIntRange(self: *BitWriter, comptime min_val: i64, comptime max_val: i64, value: i64) SerializeError!void {
        if (value < min_val or value > max_val) return error.ValueOutOfRange;
        const bits = comptime bitsRequired(min_val, max_val);
        const shifted: u32 = @intCast(value - min_val);
        return self.writeBits(shifted, bits);
    }

    pub fn writeFloatQuantized(self: *BitWriter, value: f32, comptime min_val: f32, comptime max_val: f32, comptime num_bits: u6) SerializeError!void {
        const clamped = std.math.clamp(value, min_val, max_val);
        const max_int: u32 = if (num_bits == 32) std.math.maxInt(u32) else (@as(u32, 1) << num_bits) - 1;
        const normalized = (clamped - min_val) / (max_val - min_val);
        const quantized: u32 = @intFromFloat(@round(normalized * @as(f32, @floatFromInt(max_int))));
        return self.writeBits(quantized, num_bits);
    }

    pub fn writeBytes(self: *BitWriter, bytes: []const u8) SerializeError!void {
        for (bytes) |b| {
            try self.writeBits(b, 8);
        }
    }

    pub fn flush(self: *BitWriter) SerializeError![]const u8 {
        while (self.scratch_bits > 0) {
            if (self.byte_pos >= self.buf.len) return error.BufferOverflow;
            self.buf[self.byte_pos] = @truncate(self.scratch);
            self.byte_pos += 1;
            self.scratch >>= 8;
            self.scratch_bits -|= 8;
        }
        return self.buf[0..self.byte_pos];
    }
};

pub const BitReader = struct {
    buf: []const u8,
    byte_pos: usize = 0,
    scratch: u64 = 0,
    scratch_bits: u7 = 0,

    pub fn init(buf: []const u8) BitReader {
        return .{ .buf = buf };
    }

    pub fn readBits(self: *BitReader, num_bits: u6) SerializeError!u32 {
        std.debug.assert(num_bits >= 1 and num_bits <= 32);
        while (self.scratch_bits < num_bits) {
            if (self.byte_pos >= self.buf.len) return error.BufferUnderflow;
            const remaining = self.buf.len - self.byte_pos;
            if (remaining >= 4 and self.scratch_bits <= 32) {
                const word = std.mem.readInt(u32, self.buf[self.byte_pos..][0..4], .little);
                self.scratch |= @as(u64, word) << @intCast(self.scratch_bits);
                self.byte_pos += 4;
                self.scratch_bits += 32;
            } else {
                self.scratch |= @as(u64, self.buf[self.byte_pos]) << @intCast(self.scratch_bits);
                self.byte_pos += 1;
                self.scratch_bits += 8;
            }
        }

        const mask: u64 = if (num_bits == 32) 0xFFFF_FFFF else (@as(u64, 1) << num_bits) - 1;
        const val: u32 = @truncate(self.scratch & mask);
        self.scratch >>= num_bits;
        self.scratch_bits -= num_bits;
        return val;
    }

    pub fn readBool(self: *BitReader) SerializeError!bool {
        return (try self.readBits(1)) != 0;
    }

    pub fn readIntRange(self: *BitReader, comptime min_val: i64, comptime max_val: i64) SerializeError!i64 {
        const bits = comptime bitsRequired(min_val, max_val);
        const shifted = try self.readBits(bits);
        const val = min_val + @as(i64, shifted);
        if (val > max_val) return error.ValueOutOfRange;
        return val;
    }

    pub fn readFloatQuantized(self: *BitReader, comptime min_val: f32, comptime max_val: f32, comptime num_bits: u6) SerializeError!f32 {
        const max_int: u32 = if (num_bits == 32) std.math.maxInt(u32) else (@as(u32, 1) << num_bits) - 1;
        const q = try self.readBits(num_bits);
        const normalized = @as(f32, @floatFromInt(q)) / @as(f32, @floatFromInt(max_int));
        return min_val + normalized * (max_val - min_val);
    }

    pub fn readBytes(self: *BitReader, out: []u8) SerializeError!void {
        for (out) |*b| {
            b.* = @truncate(try self.readBits(8));
        }
    }
};

test "BitWriter and BitReader round-trip bounded ints, bools, quantized floats, bytes" {
    var buf: [64]u8 = undefined;
    var w = BitWriter.init(&buf);

    try w.writeBool(true);
    try w.writeBool(false);
    try w.writeIntRange(-50, 50, -17);
    try w.writeIntRange(0, 1023, 777);
    try w.writeFloatQuantized(3.14159, -10.0, 10.0, 16);
    try w.writeBytes("upeo");
    const packet = try w.flush();

    var r = BitReader.init(packet);
    try std.testing.expect(try r.readBool());
    try std.testing.expect(!(try r.readBool()));
    try std.testing.expectEqual(@as(i64, -17), try r.readIntRange(-50, 50));
    try std.testing.expectEqual(@as(i64, 777), try r.readIntRange(0, 1023));
    try std.testing.expectApproxEqAbs(@as(f32, 3.14159), try r.readFloatQuantized(-10.0, 10.0, 16), 0.001);

    var tag: [4]u8 = undefined;
    try r.readBytes(&tag);
    try std.testing.expectEqualStrings("upeo", &tag);
}

test "BitWriter overflow and BitReader underflow" {
    var tiny: [2]u8 = undefined;
    var w = BitWriter.init(&tiny);
    try w.writeBits(0xFFFF, 16);
    try std.testing.expectError(error.BufferOverflow, w.writeBits(0x12345, 20));

    var r = BitReader.init(&.{0xAA});
    _ = try r.readBits(8);
    try std.testing.expectError(error.BufferUnderflow, r.readBits(1));
}

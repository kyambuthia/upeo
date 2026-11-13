//! 16-bit sequence number wraparound arithmetic and fixed-size sequence buffers.
//!
//! References:
//! - Elz & Bush, "Serial Number Arithmetic", RFC 1982, 1996.
//! - Fiedler, "Snapshot Compression" / "Reliability, Flow Control, and Congestion
//!   Avoidance", Gaffer on Games.

const std = @import("std");

/// Returns true iff `s1` is strictly more recent than `s2` in 16-bit modular
/// serial number arithmetic (RFC 1982).
pub fn greaterThan(s1: u16, s2: u16) bool {
    return ((s1 > s2) and (s1 - s2 <= 32768)) or
        ((s1 < s2) and (s2 - s1 > 32768));
}

pub fn lessThan(s1: u16, s2: u16) bool {
    return greaterThan(s2, s1);
}

/// Signed modular difference `s1 - s2` when `|s1 - s2| < 32768`.
pub fn diff(s1: u16, s2: u16) i32 {
    const raw: i32 = @as(i32, s1) - @as(i32, s2);
    if (raw > 32768) return raw - 65536;
    if (raw < -32768) return raw + 65536;
    return raw;
}

/// Fixed-capacity ring buffer indexed by `sequence % N` with stored sequence tags
/// to reject stale wraparound hits without heap allocations.
pub fn SequenceBuffer(comptime T: type, comptime N: usize) type {
    comptime std.debug.assert(N > 0 and N <= 32768);

    return struct {
        const Self = @This();

        entries: [N]T = undefined,
        entry_seq: [N]u32 = @splat(EMPTY),

        const EMPTY: u32 = std.math.maxInt(u32);

        pub fn reset(self: *Self) void {
            @memset(&self.entry_seq, EMPTY);
        }

        pub fn insert(self: *Self, seq: u16, value: T) *T {
            const idx = seq % N;
            self.entry_seq[idx] = seq;
            self.entries[idx] = value;
            return &self.entries[idx];
        }

        pub fn exists(self: Self, seq: u16) bool {
            return self.entry_seq[seq % N] == seq;
        }

        pub fn find(self: *Self, seq: u16) ?*T {
            const idx = seq % N;
            if (self.entry_seq[idx] != seq) return null;
            return &self.entries[idx];
        }

        pub fn findConst(self: *const Self, seq: u16) ?*const T {
            const idx = seq % N;
            if (self.entry_seq[idx] != seq) return null;
            return &self.entries[idx];
        }

        pub fn remove(self: *Self, seq: u16) void {
            const idx = seq % N;
            if (self.entry_seq[idx] == seq) {
                self.entry_seq[idx] = EMPTY;
            }
        }
    };
}

test "RFC 1982 sequence wraparound comparison" {
    try std.testing.expect(greaterThan(1, 0));
    try std.testing.expect(!greaterThan(0, 1));
    try std.testing.expect(!greaterThan(42, 42));

    // Wraparound across 65535 -> 0
    try std.testing.expect(greaterThan(0, 65535));
    try std.testing.expect(greaterThan(5, 65530));
    try std.testing.expect(!greaterThan(65530, 5));
    try std.testing.expectEqual(@as(i32, 6), diff(5, 65535));
    try std.testing.expectEqual(@as(i32, -6), diff(65535, 5));
}

test "SequenceBuffer insert, lookup, and wraparound overwrite" {
    var buf = SequenceBuffer(u32, 64){};
    _ = buf.insert(10, 123);
    try std.testing.expect(buf.exists(10));
    try std.testing.expectEqual(@as(u32, 123), buf.find(10).?.*);

    // Same slot 10 + 64 = 74 overwrites and invalidates 10
    _ = buf.insert(74, 456);
    try std.testing.expect(!buf.exists(10));
    try std.testing.expect(buf.find(10) == null);
    try std.testing.expectEqual(@as(u32, 456), buf.find(74).?.*);
}

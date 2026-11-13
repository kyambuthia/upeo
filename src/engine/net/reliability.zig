//! Packet reliability, redundant acks, and RFC 6298 RTT estimation.
//!
//! References:
//! - Fiedler, "Reliability, Flow Control, and Congestion Avoidance", Gaffer on Games.
//! - Paxson, Allman, Chu & Sargent, "Computing TCP's Retransmission Timer",
//!   RFC 6298, 2011 (Jacobson/Karels SRTT, RTTVAR, RTO estimator).

const std = @import("std");
const seq = @import("sequence.zig");

pub const PacketHeader = struct {
    pub const WIRE_SIZE = 8;

    sequence: u16,
    ack: u16,
    ack_bits: u32,

    pub fn write(self: PacketHeader, buf: []u8) void {
        std.debug.assert(buf.len >= WIRE_SIZE);
        std.mem.writeInt(u16, buf[0..2], self.sequence, .little);
        std.mem.writeInt(u16, buf[2..4], self.ack, .little);
        std.mem.writeInt(u32, buf[4..8], self.ack_bits, .little);
    }

    pub fn read(buf: []const u8) error{PacketTooShort}!PacketHeader {
        if (buf.len < WIRE_SIZE) return error.PacketTooShort;
        return .{
            .sequence = std.mem.readInt(u16, buf[0..2], .little),
            .ack = std.mem.readInt(u16, buf[2..4], .little),
            .ack_bits = std.mem.readInt(u32, buf[4..8], .little),
        };
    }
};

/// Tracks sent and received packet sequences, computes redundant 32-bit ack
/// bitfields, and estimates smoothed RTT (SRTT), RTT variance (RTTVAR), RTO,
/// and packet loss.
pub const ReliabilityState = struct {
    pub const BUFFER_SIZE = 256;

    const SentPacket = struct {
        send_time_s: f64,
        bytes: u32,
        acked: bool = false,
    };

    const RecvPacket = struct {
        recv_time_s: f64,
    };

    local_seq: u16 = 0,
    remote_seq: u16 = 0,
    has_received: bool = false,

    sent: seq.SequenceBuffer(SentPacket, BUFFER_SIZE) = .{},
    received: seq.SequenceBuffer(RecvPacket, BUFFER_SIZE) = .{},

    // RFC 6298 RTT estimator (in seconds)
    has_rtt: bool = false,
    srtt: f64 = 0.1,
    rttvar: f64 = 0.05,
    rto: f64 = 0.3,

    // Counters
    packets_sent: u64 = 0,
    packets_acked: u64 = 0,
    bytes_sent: u64 = 0,
    bytes_received: u64 = 0,

    pub fn buildHeader(self: *ReliabilityState, now_s: f64, packet_bytes: u32) PacketHeader {
        const s = self.local_seq;
        self.local_seq +%= 1;

        _ = self.sent.insert(s, .{
            .send_time_s = now_s,
            .bytes = packet_bytes,
            .acked = false,
        });
        self.packets_sent += 1;
        self.bytes_sent += packet_bytes;

        return .{
            .sequence = s,
            .ack = self.remote_seq,
            .ack_bits = self.computeAckBits(),
        };
    }

    /// Processes an incoming header, records the remote sequence, and invokes
    /// `on_ack(acked_seq)` for every newly acknowledged local packet.
    pub fn processHeader(
        self: *ReliabilityState,
        hdr: PacketHeader,
        now_s: f64,
        packet_bytes: u32,
        ctx: anytype,
        comptime on_ack: fn (@TypeOf(ctx), u16) void,
    ) void {
        self.bytes_received += packet_bytes;

        if (!self.has_received or seq.greaterThan(hdr.sequence, self.remote_seq)) {
            self.remote_seq = hdr.sequence;
            self.has_received = true;
        }
        _ = self.received.insert(hdr.sequence, .{ .recv_time_s = now_s });

        // Process primary ack + 32 redundant ack bits
        for (0..33) |bit| {
            const is_acked = if (bit == 0) true else ((hdr.ack_bits >> @intCast(bit - 1)) & 1) != 0;
            if (!is_acked) continue;

            const acked_seq = hdr.ack -% @as(u16, @intCast(bit));
            if (self.sent.find(acked_seq)) |entry| {
                if (!entry.acked) {
                    entry.acked = true;
                    self.packets_acked += 1;
                    self.updateRtt(@max(0.0, now_s - entry.send_time_s));
                    on_ack(ctx, acked_seq);
                }
            }
        }
    }

    fn computeAckBits(self: *const ReliabilityState) u32 {
        if (!self.has_received) return 0;
        var bits: u32 = 0;
        for (1..33) |offset| {
            const s = self.remote_seq -% @as(u16, @intCast(offset));
            if (self.received.exists(s)) {
                bits |= @as(u32, 1) << @intCast(offset - 1);
            }
        }
        return bits;
    }

    /// RFC 6298 Section 2.2 / 2.3 Jacobson/Karels estimator.
    fn updateRtt(self: *ReliabilityState, sample: f64) void {
        if (!self.has_rtt) {
            self.srtt = sample;
            self.rttvar = sample * 0.5;
            self.has_rtt = true;
        } else {
            const alpha = 1.0 / 8.0;
            const beta = 1.0 / 4.0;
            self.rttvar = (1.0 - beta) * self.rttvar + beta * @abs(self.srtt - sample);
            self.srtt = (1.0 - alpha) * self.srtt + alpha * sample;
        }
        self.rto = std.math.clamp(self.srtt + @max(0.01, 4.0 * self.rttvar), 0.05, 2.0);
    }

    pub fn packetLossRatio(self: ReliabilityState) f32 {
        if (self.packets_sent == 0) return 0.0;
        const lost = self.packets_sent -| self.packets_acked;
        return @as(f32, @floatFromInt(lost)) / @as(f32, @floatFromInt(self.packets_sent));
    }
};

test "ReliabilityState redundant ack bitfield recovers dropped acks" {
    var a = ReliabilityState{};
    var b = ReliabilityState{};

    const Sink = struct {
        count: usize = 0,
        last: u16 = 0,
        fn onAck(self: *@This(), s: u16) void {
            self.count += 1;
            self.last = s;
        }
    };
    var sink = Sink{};

    // A sends seq 0, 1, 2; B receives all three
    for (0..3) |i| {
        const h = a.buildHeader(@as(f64, @floatFromInt(i)) * 0.05, 32);
        b.processHeader(h, @as(f64, @floatFromInt(i)) * 0.05 + 0.02, 32, &sink, Sink.onAck);
    }

    // B sends one packet back -> ack=2, ack_bits bits 0 and 1 set (for seq 1 and 0)
    const reply = b.buildHeader(0.15, 32);
    try std.testing.expectEqual(@as(u16, 2), reply.ack);
    try std.testing.expectEqual(@as(u32, 0b11), reply.ack_bits);

    a.processHeader(reply, 0.17, 32, &sink, Sink.onAck);
    try std.testing.expectEqual(@as(usize, 3), sink.count);
    try std.testing.expect(a.srtt > 0.0);
}

//! Reliable-ordered and unreliable-unordered message channels layered on top
//! of unreliable datagrams.
//!
//! Reference: Fiedler, "Reliability, Flow Control, and Congestion Avoidance",
//! Gaffer on Games.

const std = @import("std");
const seq = @import("sequence.zig");
const rel = @import("reliability.zig");

pub const MAX_MSG_SIZE = 256;

pub const ReliableChannel = struct {
    pub const QUEUE_SIZE = 64;

    const Outgoing = struct {
        msg_id: u16 = 0,
        len: u16 = 0,
        data: [MAX_MSG_SIZE]u8 = undefined,
        sent_by_pkt: u16 = 0,
        has_sent_pkt: bool = false,
        last_send_s: f64 = -100.0,
        acked: bool = false,
    };

    const Incoming = struct {
        len: u16 = 0,
        data: [MAX_MSG_SIZE]u8 = undefined,
    };

    next_send_id: u16 = 0,
    oldest_unacked_id: u16 = 0,
    next_recv_id: u16 = 0,

    send_buf: seq.SequenceBuffer(Outgoing, QUEUE_SIZE) = .{},
    recv_buf: seq.SequenceBuffer(Incoming, QUEUE_SIZE) = .{},

    pub fn enqueue(self: *ReliableChannel, payload: []const u8) error{ MessageTooLarge, QueueFull }!u16 {
        if (payload.len > MAX_MSG_SIZE) return error.MessageTooLarge;
        if (seq.diff(self.next_send_id, self.oldest_unacked_id) >= QUEUE_SIZE) {
            return error.QueueFull;
        }

        const id = self.next_send_id;
        self.next_send_id +%= 1;
        const slot = self.send_buf.insert(id, .{
            .msg_id = id,
            .len = @intCast(payload.len),
        });
        @memcpy(slot.data[0..payload.len], payload);
        return id;
    }

    /// Serializes as many unacked/RTO-expired messages as fit in `out_buf`
    /// tagged with `pkt_seq`. Format: `[count:u16] ([msg_id:u16][len:u16][bytes...])*`.
    pub fn writeMessages(self: *ReliableChannel, pkt_seq: u16, now_s: f64, rto_s: f64, out_buf: []u8) usize {
        if (out_buf.len < 2) return 0;
        var pos: usize = 2;
        var count: u16 = 0;

        var id = self.oldest_unacked_id;
        while (seq.lessThan(id, self.next_send_id)) : (id +%= 1) {
            const entry = self.send_buf.find(id) orelse continue;
            if (entry.acked) continue;
            if (now_s - entry.last_send_s < rto_s) continue;

            const needed = 4 + entry.len;
            if (pos + needed > out_buf.len) break;

            std.mem.writeInt(u16, out_buf[pos..][0..2], id, .little);
            std.mem.writeInt(u16, out_buf[pos + 2 ..][0..2], entry.len, .little);
            @memcpy(out_buf[pos + 4 ..][0..entry.len], entry.data[0..entry.len]);
            pos += needed;
            count += 1;

            entry.last_send_s = now_s;
            entry.sent_by_pkt = pkt_seq;
            entry.has_sent_pkt = true;
        }

        std.mem.writeInt(u16, out_buf[0..2], count, .little);
        return pos;
    }

    /// Marks any outgoing message last carried in `acked_pkt_seq` as acknowledged
    /// and advances `oldest_unacked_id`.
    pub fn onPacketAcked(self: *ReliableChannel, acked_pkt_seq: u16) void {
        var id = self.oldest_unacked_id;
        while (seq.lessThan(id, self.next_send_id)) : (id +%= 1) {
            if (self.send_buf.find(id)) |entry| {
                if (!entry.acked and entry.has_sent_pkt and entry.sent_by_pkt == acked_pkt_seq) {
                    entry.acked = true;
                }
            }
        }
        while (seq.lessThan(self.oldest_unacked_id, self.next_send_id)) {
            const entry = self.send_buf.find(self.oldest_unacked_id) orelse break;
            if (!entry.acked) break;
            self.send_buf.remove(self.oldest_unacked_id);
            self.oldest_unacked_id +%= 1;
        }
    }

    /// Parses incoming message frames from `data` into the receive reorder buffer.
    pub fn readMessages(self: *ReliableChannel, data: []const u8) void {
        if (data.len < 2) return;
        const count = std.mem.readInt(u16, data[0..2], .little);
        var pos: usize = 2;

        for (0..count) |_| {
            if (pos + 4 > data.len) break;
            const msg_id = std.mem.readInt(u16, data[pos..][0..2], .little);
            const len = std.mem.readInt(u16, data[pos + 2 ..][0..2], .little);
            pos += 4;
            if (pos + len > data.len or len > MAX_MSG_SIZE) break;

            if (!seq.lessThan(msg_id, self.next_recv_id) and
                seq.diff(msg_id, self.next_recv_id) < QUEUE_SIZE and
                !self.recv_buf.exists(msg_id))
            {
                const slot = self.recv_buf.insert(msg_id, .{ .len = len });
                @memcpy(slot.data[0..len], data[pos..][0..len]);
            }
            pos += len;
        }
    }

    /// Pops the next in-order message into `out_buf`, or returns `null` if missing.
    pub fn receiveNext(self: *ReliableChannel, out_buf: []u8) ?[]const u8 {
        const entry = self.recv_buf.find(self.next_recv_id) orelse return null;
        const n = @min(out_buf.len, entry.len);
        @memcpy(out_buf[0..n], entry.data[0..n]);
        self.recv_buf.remove(self.next_recv_id);
        self.next_recv_id +%= 1;
        return out_buf[0..n];
    }
};

test "ReliableChannel delivers all messages in order under 25% loss and jitter" {
    const net_t = @import("transport.zig");
    var sim = net_t.SimulatedNetwork.init(.{
        .loss_chance = 0.25,
        .duplicate_chance = 0.15,
        .base_latency_s = 0.02,
        .jitter_s = 0.02,
        .seed = 0xfeed_face_cafe_babe,
    });

    const addr_a = net_t.Address.loopback(10001);
    const addr_b = net_t.Address.loopback(10002);
    var ep_a = sim.endpoint(addr_a);
    var ep_b = sim.endpoint(addr_b);
    const ta = ep_a.transport();
    const tb = ep_b.transport();

    var rel_a = rel.ReliabilityState{};
    var rel_b = rel.ReliabilityState{};
    var ch_a = ReliableChannel{};
    var ch_b = ReliableChannel{};

    const total_msgs: usize = 20;
    for (0..total_msgs) |i| {
        var msg: [4]u8 = undefined;
        std.mem.writeInt(u32, &msg, @intCast(i), .little);
        _ = try ch_a.enqueue(&msg);
    }

    var received_count: usize = 0;
    var pkt_buf: [1024]u8 = undefined;
    var recv_buf: [1024]u8 = undefined;
    var msg_out: [MAX_MSG_SIZE]u8 = undefined;

    for (0..400) |_| {
        // A sends packet
        const hdr_a = rel_a.buildHeader(sim.now_s, 64);
        hdr_a.write(pkt_buf[0..rel.PacketHeader.WIRE_SIZE]);
        const body_a = ch_a.writeMessages(hdr_a.sequence, sim.now_s, rel_a.rto, pkt_buf[rel.PacketHeader.WIRE_SIZE..]);
        try ta.send(addr_b, pkt_buf[0 .. rel.PacketHeader.WIRE_SIZE + body_a]);

        // B sends ack packet
        const hdr_b = rel_b.buildHeader(sim.now_s, 16);
        hdr_b.write(pkt_buf[0..rel.PacketHeader.WIRE_SIZE]);
        try tb.send(addr_a, pkt_buf[0..rel.PacketHeader.WIRE_SIZE]);

        sim.advance(0.015);

        // Drain B
        var from: net_t.Address = undefined;
        while (try tb.recv(&recv_buf, &from)) |n| {
            const h = try rel.PacketHeader.read(recv_buf[0..n]);
            rel_b.processHeader(h, sim.now_s, @intCast(n), &ch_b, struct {
                fn ack(_: *ReliableChannel, _: u16) void {}
            }.ack);
            ch_b.readMessages(recv_buf[rel.PacketHeader.WIRE_SIZE..n]);
        }

        // Drain A (acks)
        while (try ta.recv(&recv_buf, &from)) |n| {
            const h = try rel.PacketHeader.read(recv_buf[0..n]);
            rel_a.processHeader(h, sim.now_s, @intCast(n), &ch_a, ReliableChannel.onPacketAcked);
        }

        while (ch_b.receiveNext(&msg_out)) |m| {
            const val = std.mem.readInt(u32, m[0..4], .little);
            try std.testing.expectEqual(@as(u32, @intCast(received_count)), val);
            received_count += 1;
        }
        if (received_count == total_msgs) break;
    }

    try std.testing.expectEqual(total_msgs, received_count);
}

//! Connection state machine with challenge/response anti-amplification
//! handshake, keep-alives, and timeouts.
//!
//! Reference: Fiedler, "Client Server Connection" / netcode.io specification
//! (client `connect_request` is padded >= `challenge` response size to prevent
//! UDP reflection/amplification attacks).

const std = @import("std");
const transport_mod = @import("transport.zig");
const Address = transport_mod.Address;
const Transport = transport_mod.Transport;
const rel = @import("reliability.zig");
const channel_mod = @import("channel.zig");

pub const PROTOCOL_ID: u32 = 0x5550_454F; // "UPEO"
pub const PROTOCOL_VERSION: u16 = 1;

pub const PacketKind = enum(u8) {
    connect_request = 1,
    challenge = 2,
    challenge_response = 3,
    payload = 4,
    disconnect = 5,
};

pub const ClientState = enum {
    disconnected,
    sending_request,
    sending_challenge_response,
    connected,
    timed_out,
};

pub const ConnectionConfig = struct {
    protocol_id: u32 = PROTOCOL_ID,
    version: u16 = PROTOCOL_VERSION,
    timeout_s: f64 = 5.0,
    keepalive_interval_s: f64 = 0.25,
    resend_handshake_s: f64 = 0.2,
};

pub const Client = struct {
    config: ConnectionConfig,
    transport: Transport,
    server_addr: Address,
    state: ClientState = .disconnected,

    client_salt: u64 = 0,
    challenge_salt: u64 = 0,
    last_send_s: f64 = -10.0,
    last_recv_s: f64 = 0.0,

    reliability: rel.ReliabilityState = .{},
    reliable: channel_mod.ReliableChannel = .{},

    pub fn init(transport: Transport, server_addr: Address, client_salt: u64, config: ConnectionConfig) Client {
        return .{
            .config = config,
            .transport = transport,
            .server_addr = server_addr,
            .client_salt = client_salt,
        };
    }

    pub fn connect(self: *Client, now_s: f64) void {
        self.state = .sending_request;
        self.last_recv_s = now_s;
        self.last_send_s = -10.0;
    }

    pub fn disconnect(self: *Client) !void {
        if (self.state == .connected) {
            var pkt: [17]u8 = undefined;
            pkt[0] = @backingInt(PacketKind.disconnect);
            std.mem.writeInt(u32, pkt[1..5], self.config.protocol_id, .little);
            std.mem.writeInt(u64, pkt[5..13], self.client_salt ^ self.challenge_salt, .little);
            std.mem.writeInt(u32, pkt[13..17], 0, .little);
            try self.transport.send(self.server_addr, &pkt);
        }
        self.state = .disconnected;
    }

    pub fn tick(self: *Client, now_s: f64) !void {
        if (self.state == .disconnected or self.state == .timed_out) return;

        if (now_s - self.last_recv_s > self.config.timeout_s) {
            self.state = .timed_out;
            return;
        }

        // Poll incoming packets
        var buf: [1400]u8 = undefined;
        var from: Address = undefined;
        while (try self.transport.recv(&buf, &from)) |n| {
            if (!from.eql(self.server_addr) or n < 5) continue;
            const kind: PacketKind = std.enums.fromInt(PacketKind, buf[0]) orelse continue;
            const proto = std.mem.readInt(u32, buf[1..5], .little);
            if (proto != self.config.protocol_id) continue;

            self.last_recv_s = now_s;
            switch (kind) {
                .challenge => {
                    if (n >= 21 and self.state == .sending_request) {
                        const c_salt = std.mem.readInt(u64, buf[5..13], .little);
                        if (c_salt == self.client_salt) {
                            self.challenge_salt = std.mem.readInt(u64, buf[13..21], .little);
                            self.state = .sending_challenge_response;
                            self.last_send_s = -10.0;
                        }
                    }
                },
                .payload => {
                    if (self.state == .sending_challenge_response) {
                        self.state = .connected;
                    }
                    if (self.state == .connected and n >= 5 + rel.PacketHeader.WIRE_SIZE) {
                        const hdr = rel.PacketHeader.read(buf[5 .. 5 + rel.PacketHeader.WIRE_SIZE]) catch continue;
                        self.reliability.processHeader(hdr, now_s, @intCast(n), &self.reliable, channel_mod.ReliableChannel.onPacketAcked);
                        self.reliable.readMessages(buf[5 + rel.PacketHeader.WIRE_SIZE .. n]);
                    }
                },
                .disconnect => {
                    self.state = .disconnected;
                    return;
                },
                else => {},
            }
        }

        // Send outgoing handshake or keepalive/payload
        switch (self.state) {
            .sending_request => {
                if (now_s - self.last_send_s >= self.config.resend_handshake_s) {
                    // Padded to 64 bytes (> challenge response size) for anti-amplification
                    var pkt: [64]u8 = @splat(0);
                    pkt[0] = @backingInt(PacketKind.connect_request);
                    std.mem.writeInt(u32, pkt[1..5], self.config.protocol_id, .little);
                    std.mem.writeInt(u16, pkt[5..7], self.config.version, .little);
                    std.mem.writeInt(u64, pkt[7..15], self.client_salt, .little);
                    try self.transport.send(self.server_addr, &pkt);
                    self.last_send_s = now_s;
                }
            },
            .sending_challenge_response => {
                if (now_s - self.last_send_s >= self.config.resend_handshake_s) {
                    var pkt: [64]u8 = @splat(0);
                    pkt[0] = @backingInt(PacketKind.challenge_response);
                    std.mem.writeInt(u32, pkt[1..5], self.config.protocol_id, .little);
                    std.mem.writeInt(u64, pkt[5..13], self.client_salt ^ self.challenge_salt, .little);
                    try self.transport.send(self.server_addr, &pkt);
                    self.last_send_s = now_s;
                }
            },
            .connected => {
                if (now_s - self.last_send_s >= self.config.keepalive_interval_s) {
                    var pkt: [1024]u8 = undefined;
                    pkt[0] = @backingInt(PacketKind.payload);
                    std.mem.writeInt(u32, pkt[1..5], self.config.protocol_id, .little);
                    const hdr = self.reliability.buildHeader(now_s, 0);
                    hdr.write(pkt[5 .. 5 + rel.PacketHeader.WIRE_SIZE]);
                    const body_len = self.reliable.writeMessages(
                        hdr.sequence,
                        now_s,
                        self.reliability.rto,
                        pkt[5 + rel.PacketHeader.WIRE_SIZE ..],
                    );
                    try self.transport.send(self.server_addr, pkt[0 .. 5 + rel.PacketHeader.WIRE_SIZE + body_len]);
                    self.last_send_s = now_s;
                }
            },
            else => {},
        }
    }
};

pub fn Server(comptime max_clients: usize) type {
    return struct {
        const Self = @This();

        pub const ClientSlot = struct {
            connected: bool = false,
            addr: Address = Address.any(0),
            xor_salt: u64 = 0,
            last_recv_s: f64 = 0.0,
            reliability: rel.ReliabilityState = .{},
            reliable: channel_mod.ReliableChannel = .{},
        };

        config: ConnectionConfig,
        transport: Transport,
        prng: std.Random.DefaultPrng,
        clients: [max_clients]ClientSlot = @splat(.{}),

        pub fn init(transport: Transport, seed: u64, config: ConnectionConfig) Self {
            return .{
                .config = config,
                .transport = transport,
                .prng = std.Random.DefaultPrng.init(seed),
            };
        }

        pub fn connectedCount(self: Self) usize {
            var count: usize = 0;
            for (self.clients) |cl| {
                if (cl.connected) count += 1;
            }
            return count;
        }

        pub fn tick(self: *Self, now_s: f64) !void {
            // Timeout inactive clients
            for (&self.clients) |*cl| {
                if (cl.connected and now_s - cl.last_recv_s > self.config.timeout_s) {
                    cl.connected = false;
                }
            }

            // Poll incoming packets
            var buf: [1400]u8 = undefined;
            var from: Address = undefined;
            while (try self.transport.recv(&buf, &from)) |n| {
                if (n < 5) continue;
                const kind: PacketKind = std.enums.fromInt(PacketKind, buf[0]) orelse continue;
                const proto = std.mem.readInt(u32, buf[1..5], .little);
                if (proto != self.config.protocol_id) continue;

                switch (kind) {
                    .connect_request => {
                        // Require >= 64 bytes to prevent UDP amplification
                        if (n < 64) continue;
                        const version = std.mem.readInt(u16, buf[5..7], .little);
                        if (version != self.config.version) continue;
                        const c_salt = std.mem.readInt(u64, buf[7..15], .little);
                        const challenge_salt = self.prng.random().int(u64);

                        var reply: [21]u8 = undefined;
                        reply[0] = @backingInt(PacketKind.challenge);
                        std.mem.writeInt(u32, reply[1..5], self.config.protocol_id, .little);
                        std.mem.writeInt(u64, reply[5..13], c_salt, .little);
                        std.mem.writeInt(u64, reply[13..21], challenge_salt, .little);
                        try self.transport.send(from, &reply);
                    },
                    .challenge_response => {
                        if (n < 13) continue;
                        const xor_salt = std.mem.readInt(u64, buf[5..13], .little);
                        const slot = self.findByAddr(from) orelse self.allocSlot() orelse continue;
                        slot.* = .{
                            .connected = true,
                            .addr = from,
                            .xor_salt = xor_salt,
                            .last_recv_s = now_s,
                        };
                        try self.sendPayload(slot, now_s);
                    },
                    .payload => {
                        const slot = self.findByAddr(from) orelse continue;
                        if (n < 5 + rel.PacketHeader.WIRE_SIZE) continue;
                        slot.last_recv_s = now_s;
                        const hdr = rel.PacketHeader.read(buf[5 .. 5 + rel.PacketHeader.WIRE_SIZE]) catch continue;
                        slot.reliability.processHeader(hdr, now_s, @intCast(n), &slot.reliable, channel_mod.ReliableChannel.onPacketAcked);
                        slot.reliable.readMessages(buf[5 + rel.PacketHeader.WIRE_SIZE .. n]);
                        try self.sendPayload(slot, now_s);
                    },
                    .disconnect => {
                        if (self.findByAddr(from)) |slot| {
                            slot.connected = false;
                        }
                    },
                    else => {},
                }
            }
        }

        fn sendPayload(self: *Self, slot: *ClientSlot, now_s: f64) !void {
            var pkt: [1024]u8 = undefined;
            pkt[0] = @backingInt(PacketKind.payload);
            std.mem.writeInt(u32, pkt[1..5], self.config.protocol_id, .little);
            const hdr = slot.reliability.buildHeader(now_s, 0);
            hdr.write(pkt[5 .. 5 + rel.PacketHeader.WIRE_SIZE]);
            const body_len = slot.reliable.writeMessages(
                hdr.sequence,
                now_s,
                slot.reliability.rto,
                pkt[5 + rel.PacketHeader.WIRE_SIZE ..],
            );
            try self.transport.send(slot.addr, pkt[0 .. 5 + rel.PacketHeader.WIRE_SIZE + body_len]);
        }

        fn findByAddr(self: *Self, addr: Address) ?*ClientSlot {
            for (&self.clients) |*cl| {
                if (cl.connected and cl.addr.eql(addr)) return cl;
            }
            return null;
        }

        fn allocSlot(self: *Self) ?*ClientSlot {
            for (&self.clients) |*cl| {
                if (!cl.connected) return cl;
            }
            return null;
        }
    };
}

test "Client/Server challenge handshake, message exchange, and timeout lifecycle" {
    var sim = transport_mod.SimulatedNetwork.init(.{
        .loss_chance = 0.05,
        .base_latency_s = 0.01,
        .jitter_s = 0.005,
        .seed = 42,
    });

    const srv_addr = Address.loopback(9000);
    const cli_addr = Address.loopback(9001);
    var srv_ep = sim.endpoint(srv_addr);
    var cli_ep = sim.endpoint(cli_addr);

    var server = Server(4).init(srv_ep.transport(), 0xbeef, .{ .timeout_s = 1.0 });
    var client = Client.init(cli_ep.transport(), srv_addr, 0xcafe, .{ .timeout_s = 1.0 });

    client.connect(sim.now_s);
    for (0..60) |_| {
        try client.tick(sim.now_s);
        try server.tick(sim.now_s);
        sim.advance(0.02);
        if (client.state == .connected and server.connectedCount() == 1) break;
    }
    try std.testing.expectEqual(ClientState.connected, client.state);
    try std.testing.expectEqual(@as(usize, 1), server.connectedCount());

    // Exchange a reliable message client -> server
    _ = try client.reliable.enqueue("hello upeo");
    var msg_buf: [64]u8 = undefined;
    var got_msg = false;
    for (0..40) |_| {
        try client.tick(sim.now_s);
        try server.tick(sim.now_s);
        sim.advance(0.05);
        if (server.clients[0].reliable.receiveNext(&msg_buf)) |m| {
            try std.testing.expectEqualStrings("hello upeo", m);
            got_msg = true;
            break;
        }
    }
    try std.testing.expect(got_msg);

    // Silence client -> server times it out after timeout_s
    sim.advance(1.5);
    try server.tick(sim.now_s);
    try std.testing.expectEqual(@as(usize, 0), server.connectedCount());
}

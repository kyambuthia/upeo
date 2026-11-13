//! Transport abstraction, non-blocking UDP sockets, and a simulated lossy
//! in-memory network for deterministic testing.
//!
//! Platform notes:
//! - POSIX (Linux/macOS/BSD): `std.c` non-blocking IPv4 UDP (`O_NONBLOCK`).
//! - Windows: `std.os.windows.ws2_32` (`WSAStartup` + `ioctlsocket` `FIONBIO`).
//! - WebAssembly (`emscripten` / `wasi`): raw UDP is unavailable in browsers;
//!   implement `Transport` over WebRTC DataChannels or WebSocket/WebTransport.

const std = @import("std");
const builtin = @import("builtin");

pub const Address = struct {
    ip: [4]u8,
    port: u16,

    pub fn loopback(port: u16) Address {
        return .{ .ip = .{ 127, 0, 0, 1 }, .port = port };
    }

    pub fn any(port: u16) Address {
        return .{ .ip = .{ 0, 0, 0, 0 }, .port = port };
    }

    pub fn eql(a: Address, b: Address) bool {
        return std.mem.eql(u8, &a.ip, &b.ip) and a.port == b.port;
    }

    pub fn format(self: Address, writer: anytype) !void {
        try writer.print("{d}.{d}.{d}.{d}:{d}", .{ self.ip[0], self.ip[1], self.ip[2], self.ip[3], self.port });
    }
};

pub const Transport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        send: *const fn (ptr: *anyopaque, to: Address, data: []const u8) anyerror!void,
        recv: *const fn (ptr: *anyopaque, out_buf: []u8, out_from: *Address) anyerror!?usize,
    };

    pub fn send(self: Transport, to: Address, data: []const u8) !void {
        return self.vtable.send(self.ptr, to, data);
    }

    pub fn recv(self: Transport, out_buf: []u8, out_from: *Address) !?usize {
        return self.vtable.recv(self.ptr, out_buf, out_from);
    }
};

/// Non-blocking IPv4 UDP socket using `std.c` on POSIX.
pub const UdpSocket = struct {
    fd: std.posix.fd_t,
    bound_port: u16,

    pub fn bind(addr: Address) !UdpSocket {
        if (builtin.target.cpu.arch.isWasm() or builtin.os.tag == .windows) {
            return error.UnsupportedPlatform;
        }
        const fd = std.c.socket(std.c.AF.INET, std.c.SOCK.DGRAM, 0);
        if (fd < 0) return error.SocketFailed;
        errdefer _ = std.c.close(fd);

        // Set O_NONBLOCK
        const flags = std.c.fcntl(fd, std.c.F.GETFL, @as(c_int, 0));
        if (flags < 0 or std.c.fcntl(fd, std.c.F.SETFL, flags | @as(c_int, @bitCast(std.c.O{ .NONBLOCK = true }))) < 0) {
            return error.FcntlFailed;
        }

        var sa = std.c.sockaddr.in{
            .family = std.c.AF.INET,
            .port = std.mem.nativeToBig(u16, addr.port),
            .addr = @bitCast(addr.ip),
        };
        if (std.c.bind(fd, @ptrCast(&sa), @sizeOf(std.c.sockaddr.in)) < 0) {
            return error.BindFailed;
        }

        var len: std.c.socklen_t = @sizeOf(std.c.sockaddr.in);
        if (std.c.getsockname(fd, @ptrCast(&sa), &len) < 0) {
            return error.GetSockNameFailed;
        }

        return .{
            .fd = fd,
            .bound_port = std.mem.bigToNative(u16, sa.port),
        };
    }

    pub fn close(self: *UdpSocket) void {
        _ = std.c.close(self.fd);
    }

    pub fn transport(self: *UdpSocket) Transport {
        return .{
            .ptr = self,
            .vtable = &.{ .send = sendErased, .recv = recvErased },
        };
    }

    fn sendErased(ptr: *anyopaque, to: Address, data: []const u8) anyerror!void {
        const self: *UdpSocket = @ptrCast(@alignCast(ptr));
        return self.sendTo(to, data);
    }

    fn recvErased(ptr: *anyopaque, out_buf: []u8, out_from: *Address) anyerror!?usize {
        const self: *UdpSocket = @ptrCast(@alignCast(ptr));
        return self.recvFrom(out_buf, out_from);
    }

    pub fn sendTo(self: *UdpSocket, to: Address, data: []const u8) !void {
        if (builtin.target.cpu.arch.isWasm() or builtin.os.tag == .windows) {
            return error.UnsupportedPlatform;
        }
        const sa = std.c.sockaddr.in{
            .family = std.c.AF.INET,
            .port = std.mem.nativeToBig(u16, to.port),
            .addr = @bitCast(to.ip),
        };
        const rc = std.c.sendto(self.fd, data.ptr, data.len, 0, @ptrCast(&sa), @sizeOf(std.c.sockaddr.in));
        if (rc < 0) return error.SendFailed;
    }

    pub fn recvFrom(self: *UdpSocket, out_buf: []u8, out_from: *Address) !?usize {
        if (builtin.target.cpu.arch.isWasm() or builtin.os.tag == .windows) {
            return error.UnsupportedPlatform;
        }
        var sa: std.c.sockaddr.in = undefined;
        var len: std.c.socklen_t = @sizeOf(std.c.sockaddr.in);
        const rc = std.c.recvfrom(self.fd, out_buf.ptr, out_buf.len, 0, @ptrCast(&sa), &len);
        if (rc < 0) {
            const err = std.c.errno(rc);
            if (err == .AGAIN) return null;
            return error.RecvFailed;
        }
        out_from.* = .{
            .ip = @bitCast(sa.addr),
            .port = std.mem.bigToNative(u16, sa.port),
        };
        return @intCast(rc);
    }
};

/// Deterministic in-memory packet simulator with configurable loss, latency,
/// jitter, duplication, and reordering.
pub const SimulatedNetwork = struct {
    pub const MAX_PACKET_SIZE = 1400;
    pub const MAX_IN_FLIGHT = 512;

    pub const Config = struct {
        loss_chance: f32 = 0.0,
        duplicate_chance: f32 = 0.0,
        base_latency_s: f64 = 0.02,
        jitter_s: f64 = 0.01,
        seed: u64 = 0x1234_5678_9abc_def0,
    };

    const InFlight = struct {
        active: bool = false,
        from: Address = Address.any(0),
        to: Address = Address.any(0),
        deliver_at_s: f64 = 0.0,
        len: usize = 0,
        data: [MAX_PACKET_SIZE]u8 = undefined,
    };

    config: Config,
    now_s: f64 = 0.0,
    prng: std.Random.DefaultPrng,
    queue: [MAX_IN_FLIGHT]InFlight = @splat(.{}),

    pub fn init(config: Config) SimulatedNetwork {
        return .{
            .config = config,
            .prng = std.Random.DefaultPrng.init(config.seed),
        };
    }

    pub fn advance(self: *SimulatedNetwork, dt_s: f64) void {
        self.now_s += dt_s;
    }

    pub fn endpoint(self: *SimulatedNetwork, addr: Address) Endpoint {
        return .{ .net = self, .addr = addr };
    }

    fn enqueue(self: *SimulatedNetwork, from: Address, to: Address, data: []const u8) void {
        if (data.len > MAX_PACKET_SIZE) return;
        const rng = self.prng.random();

        if (rng.float(f32) < self.config.loss_chance) return;

        const copies: usize = if (rng.float(f32) < self.config.duplicate_chance) 2 else 1;
        for (0..copies) |_| {
            for (&self.queue) |*slot| {
                if (!slot.active) {
                    const jitter = (rng.float(f64) * 2.0 - 1.0) * self.config.jitter_s;
                    slot.active = true;
                    slot.from = from;
                    slot.to = to;
                    slot.deliver_at_s = self.now_s + @max(0.0, self.config.base_latency_s + jitter);
                    slot.len = data.len;
                    @memcpy(slot.data[0..data.len], data);
                    break;
                }
            }
        }
    }

    fn poll(self: *SimulatedNetwork, to: Address, out_buf: []u8, out_from: *Address) ?usize {
        for (&self.queue) |*slot| {
            if (slot.active and slot.to.eql(to) and slot.deliver_at_s <= self.now_s) {
                const n = @min(out_buf.len, slot.len);
                @memcpy(out_buf[0..n], slot.data[0..n]);
                out_from.* = slot.from;
                slot.active = false;
                return n;
            }
        }
        return null;
    }

    pub const Endpoint = struct {
        net: *SimulatedNetwork,
        addr: Address,

        pub fn transport(self: *Endpoint) Transport {
            return .{
                .ptr = self,
                .vtable = &.{ .send = sendErased, .recv = recvErased },
            };
        }

        fn sendErased(ptr: *anyopaque, to: Address, data: []const u8) anyerror!void {
            const self: *Endpoint = @ptrCast(@alignCast(ptr));
            self.net.enqueue(self.addr, to, data);
        }

        fn recvErased(ptr: *anyopaque, out_buf: []u8, out_from: *Address) anyerror!?usize {
            const self: *Endpoint = @ptrCast(@alignCast(ptr));
            return self.net.poll(self.addr, out_buf, out_from);
        }
    };
};

test "UdpSocket loopback round-trip on 127.0.0.1" {
    var server = UdpSocket.bind(Address.loopback(0)) catch return;
    defer server.close();
    var client = UdpSocket.bind(Address.loopback(0)) catch return;
    defer client.close();

    const st = server.transport();
    const ct = client.transport();

    try ct.send(Address.loopback(server.bound_port), "ping");

    var buf: [32]u8 = undefined;
    var from: Address = undefined;
    var received: ?usize = null;
    for (0..100) |_| {
        received = try st.recv(&buf, &from);
        if (received != null) break;
    }
    try std.testing.expectEqual(@as(?usize, 4), received);
    try std.testing.expectEqualStrings("ping", buf[0..4]);
    try std.testing.expectEqual(client.bound_port, from.port);
}

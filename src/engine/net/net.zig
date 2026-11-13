//! Upeo networking subsystem.
//!
//! Transport-agnostic, allocation-free-in-steady-state UDP client/server stack:
//! bit-packing, RFC 1982 sequences, RFC 6298 reliability/RTT, reliable-ordered
//! channels, challenge/response connections, simulated lossy transport, and
//! snapshot interpolation / client-side prediction.

pub const serialize = @import("serialize.zig");
pub const sequence = @import("sequence.zig");
pub const reliability = @import("reliability.zig");
pub const channel = @import("channel.zig");
pub const transport = @import("transport.zig");
pub const connection = @import("connection.zig");
pub const snapshot = @import("snapshot.zig");

test {
    _ = serialize;
    _ = sequence;
    _ = reliability;
    _ = channel;
    _ = transport;
    _ = connection;
    _ = snapshot;
}

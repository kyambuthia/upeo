//! Snapshot interpolation and client-side prediction / reconciliation helpers.
//!
//! Reference: Bernier, "Latency Compensating Methods in Client/Server In-game
//! Protocol Design and Optimization", GDC 2001.

const std = @import("std");

/// Fixed-capacity timestamped snapshot buffer that interpolates between the two
/// snapshots bracketing `(now_s - playout_delay_s)`.
pub fn SnapshotBuffer(comptime T: type, comptime N: usize) type {
    comptime std.debug.assert(N >= 2);

    return struct {
        const Self = @This();

        pub const Entry = struct {
            time_s: f64 = 0.0,
            state: T = undefined,
        };

        entries: [N]Entry = undefined,
        count: usize = 0,
        head: usize = 0, // oldest

        pub fn push(self: *Self, time_s: f64, state: T) void {
            if (self.count < N) {
                const idx = (self.head + self.count) % N;
                self.entries[idx] = .{ .time_s = time_s, .state = state };
                self.count += 1;
            } else {
                self.entries[self.head] = .{ .time_s = time_s, .state = state };
                self.head = (self.head + 1) % N;
            }
        }

        pub fn sample(
            self: *const Self,
            render_time_s: f64,
            comptime lerp_fn: fn (a: T, b: T, t: f32) T,
        ) ?T {
            if (self.count == 0) return null;
            if (self.count == 1) return self.entries[self.head].state;

            const oldest = self.entries[self.head];
            if (render_time_s <= oldest.time_s) return oldest.state;

            for (0..self.count - 1) |i| {
                const a = self.entries[(self.head + i) % N];
                const b = self.entries[(self.head + i + 1) % N];
                if (render_time_s >= a.time_s and render_time_s <= b.time_s) {
                    const span = b.time_s - a.time_s;
                    const t: f32 = if (span > 1e-9) @floatCast((render_time_s - a.time_s) / span) else 0.0;
                    return lerp_fn(a.state, b.state, std.math.clamp(t, 0.0, 1.0));
                }
            }

            const newest = self.entries[(self.head + self.count - 1) % N];
            return newest.state;
        }
    };
}

/// Fixed-capacity input/state ring buffer for client-side prediction and
/// server reconciliation (replay unacknowledged inputs after an authoritative
/// correction).
pub fn PredictionBuffer(comptime InputT: type, comptime StateT: type, comptime N: usize) type {
    comptime std.debug.assert(N > 0);

    return struct {
        const Self = @This();

        const Slot = struct {
            tick: u32 = 0,
            valid: bool = false,
            input: InputT = undefined,
            predicted: StateT = undefined,
        };

        slots: [N]Slot = @splat(.{}),

        pub fn record(self: *Self, tick: u32, input: InputT, predicted: StateT) void {
            self.slots[tick % N] = .{
                .tick = tick,
                .valid = true,
                .input = input,
                .predicted = predicted,
            };
        }

        /// Reconciles against an authoritative server state at `server_tick` by
        /// replaying all recorded inputs for `(server_tick + 1) ..= latest_tick`.
        pub fn reconcile(
            self: *Self,
            server_tick: u32,
            server_state: StateT,
            latest_tick: u32,
            comptime step_fn: fn (state: StateT, input: InputT) StateT,
        ) StateT {
            var state = server_state;
            var t = server_tick +% 1;
            while (@as(i32, @bitCast(latest_tick -% t)) >= 0) : (t +%= 1) {
                const slot = &self.slots[t % N];
                if (slot.valid and slot.tick == t) {
                    state = step_fn(state, slot.input);
                    slot.predicted = state;
                }
            }
            return state;
        }
    };
}

test "SnapshotBuffer interpolates bracketing snapshots" {
    const Vec = struct { x: f32 };
    const lerp = struct {
        fn f(a: Vec, b: Vec, t: f32) Vec {
            return .{ .x = a.x + (b.x - a.x) * t };
        }
    }.f;

    var buf = SnapshotBuffer(Vec, 8){};
    buf.push(1.0, .{ .x = 10.0 });
    buf.push(2.0, .{ .x = 20.0 });

    const s = buf.sample(1.25, lerp).?;
    try std.testing.expectApproxEqAbs(@as(f32, 12.5), s.x, 1e-5);
}

test "PredictionBuffer reconciles authoritative state by replaying unacked ticks" {
    const step = struct {
        fn f(pos: f32, vel: f32) f32 {
            return pos + vel;
        }
    }.f;

    var pred = PredictionBuffer(f32, f32, 16){};
    // Client predicts ticks 1, 2, 3 with vel = +2.0 starting from 0
    pred.record(1, 2.0, 2.0);
    pred.record(2, 2.0, 4.0);
    pred.record(3, 2.0, 6.0);

    // Server corrects tick 1 to 1.5 (e.g. collision); ticks 2 and 3 replay -> 1.5 + 2 + 2 = 5.5
    const corrected = pred.reconcile(1, 1.5, 3, step);
    try std.testing.expectApproxEqAbs(@as(f32, 5.5), corrected, 1e-5);
}

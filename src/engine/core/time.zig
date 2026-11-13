//! Frame timing and fixed-timestep accumulator.
//!
//! Uses a fixed-step physics accumulator with frame-dt clamping to prevent the
//! "spiral of death" on lag spikes, and exposes an interpolation `alpha` in
//! `[0, 1)` for rendering (Fiedler, "Fix Your Timestep!", Gaffer on Games, 2004).

const std = @import("std");
const c = @import("../platform/c.zig").c;

pub const FrameStats = struct {
    fps: f32 = 0.0,
    frame_ms: f32 = 0.0,
    frame_count: u64 = 0,

    _accum_time: f32 = 0.0,
    _accum_frames: u32 = 0,

    pub fn record(self: *FrameStats, dt: f32) void {
        self.frame_count += 1;
        self._accum_time += dt;
        self._accum_frames += 1;
        if (self._accum_time >= 0.5) {
            self.fps = @as(f32, @floatFromInt(self._accum_frames)) / self._accum_time;
            self.frame_ms = (self._accum_time / @as(f32, @floatFromInt(self._accum_frames))) * 1000.0;
            self._accum_time = 0.0;
            self._accum_frames = 0;
        }
    }
};

pub const Clock = struct {
    last_ns: u64,
    delta_time: f32 = 0.0,
    elapsed_time: f64 = 0.0,
    accumulator: f64 = 0.0,
    fixed_dt: f32 = 1.0 / 60.0,
    max_frame_dt: f32 = 0.05,
    stats: FrameStats = .{},

    pub const fixed_delta: f32 = 1.0 / 60.0;

    pub fn init() Clock {
        return initAt(c.SDL_GetTicksNS());
    }

    /// Pure initializer for deterministic testing without SDL.
    pub fn initAt(now_ns: u64) Clock {
        return .{ .last_ns = now_ns };
    }

    pub fn tick(self: *Clock) f32 {
        return self.tickAt(c.SDL_GetTicksNS());
    }

    /// Advances the clock to `now_ns`, clamps dt, feeds the fixed-step
    /// accumulator, and updates `stats`.
    pub fn tickAt(self: *Clock, now_ns: u64) f32 {
        const diff_ns = now_ns -| self.last_ns;
        self.last_ns = now_ns;

        const raw_dt = @as(f32, @floatCast(@as(f64, @floatFromInt(diff_ns)) / 1_000_000_000.0));
        self.delta_time = @min(raw_dt, self.max_frame_dt);
        self.elapsed_time += self.delta_time;
        self.accumulator += self.delta_time;
        self.stats.record(self.delta_time);
        return self.delta_time;
    }

    /// Consumes one fixed timestep if enough time has accumulated.
    pub fn consumeFixedStep(self: *Clock) bool {
        const step: f64 = self.fixed_dt;
        if (self.accumulator + 1e-9 >= step) {
            self.accumulator = @max(0.0, self.accumulator - step);
            return true;
        }
        return false;
    }

    /// Remainder fraction in `[0, 1)` for render state interpolation.
    pub fn alpha(self: Clock) f32 {
        return @floatCast(@min(1.0, self.accumulator / @as(f64, self.fixed_dt)));
    }
};

test "clock clamps large spikes and steps fixed accumulator" {
    var clock = Clock.initAt(0);

    // 100ms spike should clamp to 50ms -> 2 full 16.67ms steps (since 3 * f32(1/60) > 0.05)
    const dt = clock.tickAt(100_000_000);
    try std.testing.expectApproxEqAbs(@as(f32, 0.05), dt, 1e-6);

    var steps: usize = 0;
    while (clock.consumeFixedStep()) steps += 1;
    try std.testing.expectEqual(@as(usize, 2), steps);
    try std.testing.expect(clock.alpha() >= 0.0 and clock.alpha() < 1.0);
}

test "clock handles exact 60Hz ticks without drift" {
    var clock = Clock.initAt(0);
    const step_ns: u64 = 16_666_667;
    var total_steps: usize = 0;
    var i: u64 = 1;
    while (i <= 60) : (i += 1) {
        _ = clock.tickAt(i * step_ns);
        while (clock.consumeFixedStep()) total_steps += 1;
    }
    try std.testing.expectEqual(@as(usize, 60), total_steps);
}

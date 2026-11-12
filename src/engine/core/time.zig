const std = @import("std");
const c = @import("../platform/c.zig").c;

pub const Clock = struct {
    last_ticks: u64,
    delta_time: f32 = 0.0,
    elapsed_time: f32 = 0.0,

    pub const fixed_delta: f32 = 1.0 / 60.0;

    pub fn init() Clock {
        return .{
            .last_ticks = c.SDL_GetTicks(),
        };
    }

    pub fn tick(self: *Clock) f32 {
        const now = c.SDL_GetTicks();
        const diff_ms = now - self.last_ticks;
        self.last_ticks = now;

        const dt = @as(f32, @floatFromInt(diff_ms)) / 1000.0;
        // Clamp to 50ms maximum to prevent spiral of death on long lag spikes
        self.delta_time = @min(dt, 0.05);
        self.elapsed_time += self.delta_time;
        return self.delta_time;
    }
};

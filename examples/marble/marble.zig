const std = @import("std");
const upeo = @import("upeo");
const math = upeo.math;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Input = upeo.input.Input;
const arena = @import("arena.zig");

pub const Marble = struct {
    pos: Vec3 = Vec3.new(0.0, 0.5, 0.0),
    vel: Vec3 = Vec3.zero,
    rot_x: f32 = 0.0,
    rot_z: f32 = 0.0,
    radius: f32 = 0.5,
    is_grounded: bool = true,

    pub fn update(self: *Marble, input: Input, dt: f32) void {
        const accel: f32 = 25.0;
        const max_speed: f32 = 12.0;
        const drag: f32 = 0.985;
        const gravity: f32 = 20.0;

        // Input drive
        if (input.up) self.vel.z += accel * dt;
        if (input.down) self.vel.z -= accel * dt;
        if (input.left) self.vel.x -= accel * dt;
        if (input.right) self.vel.x += accel * dt;

        // Jump
        if (input.jump and self.is_grounded) {
            self.vel.y = 7.5;
            self.is_grounded = false;
        }

        // Gravity
        self.vel.y -= gravity * dt;

        // Slope acceleration: if on ramp, gravity pulls down the incline (-Z)
        if (self.is_grounded and arena.isOnRamp(self.pos.x, self.pos.z)) {
            // Slope angle ~16.7 degrees, sin(theta) ~ 0.287
            self.vel.z -= gravity * 0.287 * dt;
        }

        // Horizontal velocity clamping
        const horiz_speed = @sqrt(self.vel.x * self.vel.x + self.vel.z * self.vel.z);
        if (horiz_speed > max_speed) {
            const factor = max_speed / horiz_speed;
            self.vel.x *= factor;
            self.vel.z *= factor;
        }

        // Surface friction
        if (self.is_grounded) {
            self.vel.x *= drag;
            self.vel.z *= drag;
        }

        // Integration
        self.pos = self.pos.add(self.vel.scale(dt));

        // Rolling visual spin
        self.rot_x += (self.vel.z / self.radius) * dt;
        self.rot_z -= (self.vel.x / self.radius) * dt;

        // Collision detection and response with arena
        self.is_grounded = arena.resolveCollision(&self.pos, &self.vel, self.radius);
    }

    pub fn getModelMatrix(self: Marble) Mat4 {
        const t = Mat4.translation(self.pos.x, self.pos.y, self.pos.z);
        const rx = Mat4.rotationX(self.rot_x);
        const rz = Mat4.rotationZ(self.rot_z);
        const rot = Mat4.mul(rx, rz);
        return Mat4.mul(t, rot);
    }
};

test "marble jumping and gravity" {
    var marble = Marble{};
    const empty_input = Input{};

    // Marble starts grounded at y = 0.5
    try std.testing.expect(marble.is_grounded);

    // Trigger jump
    var jump_input = Input{};
    jump_input.jump = true;
    marble.update(jump_input, 0.016);

    try std.testing.expect(!marble.is_grounded);
    try std.testing.expect(marble.vel.y > 0.0);

    // After enough gravity steps, it lands back and is grounded
    var i: usize = 0;
    while (i < 60) : (i += 1) {
        marble.update(empty_input, 0.016);
    }
    try std.testing.expect(marble.is_grounded);
    try std.testing.expectEqual(@as(f32, 0.5), marble.pos.y);
}

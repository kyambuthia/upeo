const std = @import("std");
const math = @import("../engine/math/math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Input = @import("../engine/input/input.zig").Input;

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

        // Height resolution over terrain/ramp
        var ground_y: f32 = 0.0;
        if (self.pos.x >= -3.0 and self.pos.x <= 3.0 and self.pos.z >= 2.0 and self.pos.z <= 6.0) {
            const ramp_t = (self.pos.z - 2.0) / 4.0;
            ground_y = 1.2 * ramp_t;
        }

        if (self.pos.y <= ground_y + self.radius) {
            self.pos.y = ground_y + self.radius;
            if (self.vel.y < 0) self.vel.y = 0;
            self.is_grounded = true;
        } else {
            self.is_grounded = false;
        }

        // Boundary walls (size = 12.0)
        const bound = 12.0 - self.radius;
        if (self.pos.x < -bound) {
            self.pos.x = -bound;
            self.vel.x = -self.vel.x * 0.65;
        } else if (self.pos.x > bound) {
            self.pos.x = bound;
            self.vel.x = -self.vel.x * 0.65;
        }

        if (self.pos.z < -bound) {
            self.pos.z = -bound;
            self.vel.z = -self.vel.z * 0.65;
        } else if (self.pos.z > bound) {
            self.pos.z = bound;
            self.vel.z = -self.vel.z * 0.65;
        }
    }

    pub fn getModelMatrix(self: Marble) Mat4 {
        const t = Mat4.translation(self.pos.x, self.pos.y, self.pos.z);
        const rx = Mat4.rotationX(self.rot_x);
        const rz = Mat4.rotationZ(self.rot_z);
        const rot = Mat4.mul(rx, rz);
        return Mat4.mul(t, rot);
    }
};

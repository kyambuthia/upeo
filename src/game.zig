const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

pub const InputState = struct {
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
    jump: bool = false,
};

pub const Marble = struct {
    pos: Vec3 = Vec3.new(0.0, 0.5, 0.0),
    vel: Vec3 = Vec3.new(0.0, 0.0, 0.0),
    rot_x: f32 = 0.0,
    rot_z: f32 = 0.0,
    radius: f32 = 0.5,
    is_grounded: bool = true,

    pub fn update(self: *Marble, input: InputState, dt: f32) void {
        const accel: f32 = 25.0;
        const max_speed: f32 = 12.0;
        const drag: f32 = 0.985;
        const gravity: f32 = 20.0;

        // Apply acceleration from input
        if (input.up) self.vel.z += accel * dt;
        if (input.down) self.vel.z -= accel * dt;
        if (input.left) self.vel.x -= accel * dt;
        if (input.right) self.vel.x += accel * dt;

        // Jump
        if (input.jump and self.is_grounded) {
            self.vel.y = 7.5;
            self.is_grounded = false;
        }

        // Apply gravity
        self.vel.y -= gravity * dt;

        // Clamp horizontal speed
        const horiz_speed = @sqrt(self.vel.x * self.vel.x + self.vel.z * self.vel.z);
        if (horiz_speed > max_speed) {
            const factor = max_speed / horiz_speed;
            self.vel.x *= factor;
            self.vel.z *= factor;
        }

        // Apply drag on ground
        if (self.is_grounded) {
            self.vel.x *= drag;
            self.vel.z *= drag;
        }

        // Integrate position
        self.pos = self.pos.add(self.vel.scale(dt));

        // Update rolling visual rotation based on speed and radius
        self.rot_x += (self.vel.z / self.radius) * dt;
        self.rot_z -= (self.vel.x / self.radius) * dt;

        // Calculate ground height below marble
        var ground_y: f32 = 0.0;
        // Check ramp: x in [-3, 3], z in [2, 6]
        if (self.pos.x >= -3.0 and self.pos.x <= 3.0 and self.pos.z >= 2.0 and self.pos.z <= 6.0) {
            const ramp_t = (self.pos.z - 2.0) / 4.0;
            ground_y = 1.2 * ramp_t;
        }

        // Ground collision
        if (self.pos.y <= ground_y + self.radius) {
            self.pos.y = ground_y + self.radius;
            if (self.vel.y < 0) self.vel.y = 0;
            self.is_grounded = true;
        } else {
            self.is_grounded = false;
        }

        // Wall collisions (arena size = 12.0)
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

pub const Camera = struct {
    pos: Vec3 = Vec3.new(0.0, 5.0, -8.0),
    target: Vec3 = Vec3.new(0.0, 0.5, 0.0),

    pub fn update(self: *Camera, marble_pos: Vec3, dt: f32) void {
        const desired_pos = Vec3.new(marble_pos.x * 0.4, marble_pos.y + 6.0, marble_pos.z - 9.0);
        // Smooth camera follow
        const lerp_speed: f32 = 6.0 * dt;
        self.pos.x += (desired_pos.x - self.pos.x) * lerp_speed;
        self.pos.y += (desired_pos.y - self.pos.y) * lerp_speed;
        self.pos.z += (desired_pos.z - self.pos.z) * lerp_speed;

        self.target = marble_pos;
    }

    pub fn getViewMatrix(self: Camera) Mat4 {
        return Mat4.lookAt(self.pos, self.target, Vec3.new(0.0, 1.0, 0.0));
    }
};

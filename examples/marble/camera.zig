const std = @import("std");
const upeo = @import("upeo");
const math = upeo.math;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

pub const Camera = struct {
    pos: Vec3 = Vec3.new(0.0, 5.0, -8.0),
    target: Vec3 = Vec3.new(0.0, 0.5, 0.0),

    pub fn update(self: *Camera, marble_pos: Vec3, dt: f32) void {
        const desired_pos = Vec3.new(marble_pos.x * 0.4, marble_pos.y + 6.0, marble_pos.z - 9.0);
        const lerp_speed: f32 = 6.0 * dt;
        self.pos.x += (desired_pos.x - self.pos.x) * lerp_speed;
        self.pos.y += (desired_pos.y - self.pos.y) * lerp_speed;
        self.pos.z += (desired_pos.z - self.pos.z) * lerp_speed;

        self.target = marble_pos;
    }

    pub fn getViewMatrix(self: Camera) Mat4 {
        return Mat4.lookAt(self.pos, self.target, Vec3.up);
    }
};

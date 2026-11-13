//! Perspective 3D camera helper in the graphics subsystem.

const std = @import("std");
const math = @import("../math/math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

pub const Camera = struct {
    pos: Vec3 = Vec3.new(0, 5, -8),
    target: Vec3 = Vec3.zero,
    up: Vec3 = Vec3.up,
    fov_deg: f32 = 55.0,
    near: f32 = 0.1,
    far: f32 = 100.0,

    pub fn viewMatrix(self: Camera) Mat4 {
        return Mat4.lookAt(self.pos, self.target, self.up);
    }

    pub fn projMatrix(self: Camera, aspect: f32) Mat4 {
        return Mat4.perspective(std.math.degreesToRadians(self.fov_deg), aspect, self.near, self.far);
    }

    pub fn viewProjMatrix(self: Camera, aspect: f32) Mat4 {
        return Mat4.mul(self.projMatrix(aspect), self.viewMatrix());
    }
};

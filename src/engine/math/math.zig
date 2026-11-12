const std = @import("std");

pub const Vec3 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub const zero = Vec3{ .x = 0, .y = 0, .z = 0 };
    pub const up = Vec3{ .x = 0, .y = 1, .z = 0 };

    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
    }

    pub fn scale(self: Vec3, s: f32) Vec3 {
        return .{ .x = self.x * s, .y = self.y * s, .z = self.z * s };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn lengthSq(self: Vec3) f32 {
        return self.dot(self);
    }

    pub fn length(self: Vec3) f32 {
        return @sqrt(self.lengthSq());
    }

    pub fn normalize(self: Vec3) Vec3 {
        const l = self.length();
        if (l > 0.00001) {
            return self.scale(1.0 / l);
        }
        return self;
    }

    pub fn lerp(a: Vec3, b: Vec3, t: f32) Vec3 {
        return a.add(b.sub(a).scale(t));
    }
};

pub const Mat4 = struct {
    // Column-major order: [col * 4 + row]
    // Compatible directly with glUniformMatrix4fv
    m: [16]f32,

    pub fn identity() Mat4 {
        return .{
            .m = [16]f32{
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            },
        };
    }

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var r: [16]f32 = undefined;
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            var j: usize = 0;
            while (j < 4) : (j += 1) {
                var sum: f32 = 0;
                var k: usize = 0;
                while (k < 4) : (k += 1) {
                    sum += a.m[k * 4 + j] * b.m[i * 4 + k];
                }
                r[i * 4 + j] = sum;
            }
        }
        return .{ .m = r };
    }

    pub fn translation(x: f32, y: f32, z: f32) Mat4 {
        var res = Mat4.identity();
        res.m[12] = x;
        res.m[13] = y;
        res.m[14] = z;
        return res;
    }

    pub fn scaling(x: f32, y: f32, z: f32) Mat4 {
        var res = Mat4.identity();
        res.m[0] = x;
        res.m[5] = y;
        res.m[10] = z;
        return res;
    }

    pub fn rotationX(rad: f32) Mat4 {
        var res = Mat4.identity();
        const c = @cos(rad);
        const s = @sin(rad);
        res.m[5] = c;
        res.m[6] = s;
        res.m[9] = -s;
        res.m[10] = c;
        return res;
    }

    pub fn rotationY(rad: f32) Mat4 {
        var res = Mat4.identity();
        const c = @cos(rad);
        const s = @sin(rad);
        res.m[0] = c;
        res.m[2] = -s;
        res.m[8] = s;
        res.m[10] = c;
        return res;
    }

    pub fn rotationZ(rad: f32) Mat4 {
        var res = Mat4.identity();
        const c = @cos(rad);
        const s = @sin(rad);
        res.m[0] = c;
        res.m[1] = s;
        res.m[4] = -s;
        res.m[5] = c;
        return res;
    }

    pub fn perspective(fovy_rad: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const tan_half_fovy = @tan(fovy_rad / 2.0);
        var res = std.mem.zeroes(Mat4);
        res.m[0] = 1.0 / (aspect * tan_half_fovy);
        res.m[5] = 1.0 / tan_half_fovy;
        res.m[10] = -(far + near) / (far - near);
        res.m[11] = -1.0;
        res.m[14] = -(2.0 * far * near) / (far - near);
        return res;
    }

    pub fn lookAt(eye: Vec3, target: Vec3, up_vec: Vec3) Mat4 {
        const f = target.sub(eye).normalize();
        const s = f.cross(up_vec).normalize();
        const u = s.cross(f);

        var res = Mat4.identity();
        res.m[0] = s.x;
        res.m[4] = s.y;
        res.m[8] = s.z;
        res.m[1] = u.x;
        res.m[5] = u.y;
        res.m[9] = u.z;
        res.m[2] = -f.x;
        res.m[6] = -f.y;
        res.m[10] = -f.z;
        res.m[12] = -s.dot(eye);
        res.m[13] = -u.dot(eye);
        res.m[14] = f.dot(eye);
        return res;
    }
};

test "Vec3 arithmetic" {
    const a = Vec3.new(1, 2, 3);
    const b = Vec3.new(4, 5, 6);
    try std.testing.expectEqual(Vec3.new(5, 7, 9), a.add(b));
    try std.testing.expectEqual(Vec3.new(-3, -3, -3), a.sub(b));
    try std.testing.expectEqual(Vec3.new(2, 4, 6), a.scale(2));
    try std.testing.expectEqual(@as(f32, 32.0), a.dot(b));
}

test "Mat4 identity multiplication" {
    const ident = Mat4.identity();
    const t = Mat4.translation(5, 10, 15);
    const result = Mat4.mul(ident, t);
    try std.testing.expectEqual(t.m[12], result.m[12]);
    try std.testing.expectEqual(t.m[13], result.m[13]);
    try std.testing.expectEqual(t.m[14], result.m[14]);
}

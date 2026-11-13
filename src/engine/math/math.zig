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

    pub fn transpose(self: Mat4) Mat4 {
        var res: [16]f32 = undefined;
        for (0..4) |col| {
            for (0..4) |row| {
                res[row * 4 + col] = self.m[col * 4 + row];
            }
        }
        return .{ .m = res };
    }

    /// General 4x4 matrix inverse via 2x2 sub-determinants (cofactor expansion).
    /// Returns `null` if the matrix is singular.
    pub fn inverse(self: Mat4) ?Mat4 {
        const m = self.m;
        const c00 = m[10] * m[15] - m[14] * m[11];
        const c02 = m[6] * m[15] - m[14] * m[7];
        const c03 = m[6] * m[11] - m[10] * m[7];

        const c04 = m[9] * m[15] - m[13] * m[11];
        const c06 = m[5] * m[15] - m[13] * m[7];
        const c07 = m[5] * m[11] - m[9] * m[7];

        const c08 = m[9] * m[14] - m[13] * m[10];
        const c10 = m[5] * m[14] - m[13] * m[6];
        const c11 = m[5] * m[10] - m[9] * m[6];

        const c12 = m[8] * m[15] - m[12] * m[11];
        const c14 = m[4] * m[15] - m[12] * m[7];
        const c15 = m[4] * m[11] - m[8] * m[7];

        const c16 = m[8] * m[14] - m[12] * m[10];
        const c18 = m[4] * m[14] - m[12] * m[6];
        const c19 = m[4] * m[10] - m[8] * m[6];

        const c20 = m[8] * m[13] - m[12] * m[9];
        const c22 = m[4] * m[13] - m[12] * m[5];
        const c23 = m[4] * m[9] - m[8] * m[5];

        const fac0 = [4]f32{ c00, c00, c02, c03 };
        const fac1 = [4]f32{ c04, c04, c06, c07 };
        const fac2 = [4]f32{ c08, c08, c10, c11 };
        const fac3 = [4]f32{ c12, c12, c14, c15 };
        const fac4 = [4]f32{ c16, c16, c18, c19 };
        const fac5 = [4]f32{ c20, c20, c22, c23 };

        const vec0 = [4]f32{ m[4], m[0], m[0], m[0] };
        const vec1 = [4]f32{ m[5], m[1], m[1], m[1] };
        const vec2 = [4]f32{ m[6], m[2], m[2], m[2] };
        const vec3 = [4]f32{ m[7], m[3], m[3], m[3] };

        var inv: [4][4]f32 = undefined;
        const signs_a = [4]f32{ 1, -1, 1, -1 };
        const signs_b = [4]f32{ -1, 1, -1, 1 };
        for (0..4) |i| {
            inv[0][i] = (vec1[i] * fac0[i] - vec2[i] * fac1[i] + vec3[i] * fac2[i]) * signs_a[i];
            inv[1][i] = (vec0[i] * fac0[i] - vec2[i] * fac3[i] + vec3[i] * fac4[i]) * signs_b[i];
            inv[2][i] = (vec0[i] * fac1[i] - vec1[i] * fac3[i] + vec3[i] * fac5[i]) * signs_a[i];
            inv[3][i] = (vec0[i] * fac2[i] - vec1[i] * fac4[i] + vec2[i] * fac5[i]) * signs_b[i];
        }

        const det = m[0] * inv[0][0] + m[1] * inv[1][0] + m[2] * inv[2][0] + m[3] * inv[3][0];
        if (@abs(det) < 1e-8) return null;
        const inv_det = 1.0 / det;

        var res: [16]f32 = undefined;
        for (0..4) |col| {
            for (0..4) |row| {
                res[col * 4 + row] = inv[col][row] * inv_det;
            }
        }
        return .{ .m = res };
    }
};

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn new(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }
};

pub const Vec4 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,

    pub fn new(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }
};

/// Unit quaternion `(x, y, z, w)` for gimbal-lock-free 3D rotations and SLERP.
pub const Quat = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 1,

    pub const identity = Quat{};

    pub fn fromAxisAngle(axis: Vec3, rad: f32) Quat {
        const half = rad * 0.5;
        const s = @sin(half);
        const n = axis.normalize();
        return .{ .x = n.x * s, .y = n.y * s, .z = n.z * s, .w = @cos(half) };
    }

    pub fn mul(a: Quat, b: Quat) Quat {
        return .{
            .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        };
    }

    pub fn normalize(self: Quat) Quat {
        const len = @sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
        if (len <= 1e-6) return Quat.identity;
        const inv = 1.0 / len;
        return .{ .x = self.x * inv, .y = self.y * inv, .z = self.z * inv, .w = self.w * inv };
    }

    pub fn slerp(a: Quat, b_in: Quat, t: f32) Quat {
        var b = b_in;
        var dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
        if (dot < 0.0) {
            b = .{ .x = -b.x, .y = -b.y, .z = -b.z, .w = -b.w };
            dot = -dot;
        }
        if (dot > 0.9995) {
            return (Quat{
                .x = a.x + (b.x - a.x) * t,
                .y = a.y + (b.y - a.y) * t,
                .z = a.z + (b.z - a.z) * t,
                .w = a.w + (b.w - a.w) * t,
            }).normalize();
        }
        const theta_0 = std.math.acos(std.math.clamp(dot, -1.0, 1.0));
        const theta = theta_0 * t;
        const sin_theta = @sin(theta);
        const sin_theta_0 = @sin(theta_0);
        const s0 = @cos(theta) - dot * sin_theta / sin_theta_0;
        const s1 = sin_theta / sin_theta_0;
        return .{
            .x = s0 * a.x + s1 * b.x,
            .y = s0 * a.y + s1 * b.y,
            .z = s0 * a.z + s1 * b.z,
            .w = s0 * a.w + s1 * b.w,
        };
    }

    pub fn rotateVec(self: Quat, v: Vec3) Vec3 {
        const qv = Vec3.new(self.x, self.y, self.z);
        const t = qv.cross(v).scale(2.0);
        return v.add(t.scale(self.w)).add(qv.cross(t));
    }

    pub fn toMat4(self: Quat) Mat4 {
        const xx = self.x * self.x;
        const yy = self.y * self.y;
        const zz = self.z * self.z;
        const xy = self.x * self.y;
        const xz = self.x * self.z;
        const yz = self.y * self.z;
        const wx = self.w * self.x;
        const wy = self.w * self.y;
        const wz = self.w * self.z;

        var res = Mat4.identity();
        res.m[0] = 1.0 - 2.0 * (yy + zz);
        res.m[1] = 2.0 * (xy + wz);
        res.m[2] = 2.0 * (xz - wy);
        res.m[4] = 2.0 * (xy - wz);
        res.m[5] = 1.0 - 2.0 * (xx + zz);
        res.m[6] = 2.0 * (yz + wx);
        res.m[8] = 2.0 * (xz + wy);
        res.m[9] = 2.0 * (yz - wx);
        res.m[10] = 1.0 - 2.0 * (xx + yy);
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

test "Mat4 inverse round-trip" {
    const t = Mat4.translation(3, -4, 5);
    const r = Quat.fromAxisAngle(Vec3.new(0, 1, 0), 0.75).toMat4();
    const s = Mat4.scaling(2, 3, 4);
    const m = Mat4.mul(t, Mat4.mul(r, s));
    const inv = m.inverse().?;
    const prod = Mat4.mul(m, inv);

    const ident = Mat4.identity();
    for (0..16) |i| {
        try std.testing.expectApproxEqAbs(ident.m[i], prod.m[i], 1e-4);
    }
}

test "Quat axis-angle rotation and SLERP" {
    const q = Quat.fromAxisAngle(Vec3.up, std.math.pi / 2.0);
    const v = q.rotateVec(Vec3.new(1, 0, 0));
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), v.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), v.y, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), v.z, 1e-5);

    const half = Quat.slerp(Quat.identity, q, 0.5);
    const vh = half.rotateVec(Vec3.new(1, 0, 0));
    try std.testing.expectApproxEqAbs(@as(f32, @sqrt(0.5)), vh.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -@sqrt(0.5)), vh.z, 1e-4);
}

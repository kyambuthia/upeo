const std = @import("std");
const upeo = @import("upeo");
const math = upeo.math;
const Vec3 = math.Vec3;
const mesh = upeo.gfx.mesh;
const Vertex = mesh.Vertex;
const putQuad = mesh.putQuad;

pub const HALF_SIZE: f32 = 12.0;
pub const WALL_HEIGHT: f32 = 1.0;

pub const RAMP_X_MIN: f32 = -3.0;
pub const RAMP_X_MAX: f32 = 3.0;
pub const RAMP_Z_MIN: f32 = 2.0;
pub const RAMP_Z_MAX: f32 = 6.0;
pub const RAMP_HEIGHT: f32 = 1.2;

pub fn getSurfaceHeight(x: f32, z: f32) f32 {
    if (x >= RAMP_X_MIN and x <= RAMP_X_MAX and z >= RAMP_Z_MIN and z <= RAMP_Z_MAX) {
        const ramp_t = (z - RAMP_Z_MIN) / (RAMP_Z_MAX - RAMP_Z_MIN);
        return RAMP_HEIGHT * ramp_t;
    }
    return 0.0;
}

pub fn isOnRamp(x: f32, z: f32) bool {
    return (x >= RAMP_X_MIN and x <= RAMP_X_MAX and z >= RAMP_Z_MIN and z <= RAMP_Z_MAX);
}

pub fn resolveCollision(pos: *Vec3, vel: *Vec3, radius: f32) bool {
    const ground_y = getSurfaceHeight(pos.x, pos.z);
    var is_grounded = false;

    // Ground & Ramp collision
    if (pos.y <= ground_y + radius) {
        pos.y = ground_y + radius;
        if (vel.y < 0) vel.y = 0;
        is_grounded = true;
    }

    // Boundary walls (bounce restitution: 0.65)
    const bound = HALF_SIZE - radius;
    const restitution: f32 = 0.65;

    if (pos.x < -bound) {
        pos.x = -bound;
        vel.x = -vel.x * restitution;
    } else if (pos.x > bound) {
        pos.x = bound;
        vel.x = -vel.x * restitution;
    }

    if (pos.z < -bound) {
        pos.z = -bound;
        vel.z = -vel.z * restitution;
    } else if (pos.z > bound) {
        pos.z = bound;
        vel.z = -vel.z * restitution;
    }

    return is_grounded;
}

pub fn generateArenaMesh(allocator: std.mem.Allocator) ![]Vertex {
    const total_verts: usize = 6 * 6; // 6 quads * 6 vertices each
    const vertices = try allocator.alloc(Vertex, total_verts);
    errdefer allocator.free(vertices);

    const floor_color = [3]f32{ 0.25, 0.35, 0.45 };
    const wall_color = [3]f32{ 0.75, 0.55, 0.25 };
    const ramp_color = [3]f32{ 0.35, 0.70, 0.45 };

    var idx: usize = 0;

    // 1. Main floor (facing +Y upwards)
    idx = putQuad(
        vertices,
        idx,
        .{ -HALF_SIZE, 0.0, HALF_SIZE },
        .{ HALF_SIZE, 0.0, HALF_SIZE },
        .{ HALF_SIZE, 0.0, -HALF_SIZE },
        .{ -HALF_SIZE, 0.0, -HALF_SIZE },
        .{ 0.0, 1.0, 0.0 },
        floor_color,
    );

    // 2. North Wall (at Z = -HALF_SIZE, facing +Z inward)
    idx = putQuad(
        vertices,
        idx,
        .{ -HALF_SIZE, 0.0, -HALF_SIZE },
        .{ HALF_SIZE, 0.0, -HALF_SIZE },
        .{ HALF_SIZE, WALL_HEIGHT, -HALF_SIZE },
        .{ -HALF_SIZE, WALL_HEIGHT, -HALF_SIZE },
        .{ 0.0, 0.0, 1.0 },
        wall_color,
    );

    // 3. South Wall (at Z = +HALF_SIZE, facing -Z inward)
    idx = putQuad(
        vertices,
        idx,
        .{ HALF_SIZE, 0.0, HALF_SIZE },
        .{ -HALF_SIZE, 0.0, HALF_SIZE },
        .{ -HALF_SIZE, WALL_HEIGHT, HALF_SIZE },
        .{ HALF_SIZE, WALL_HEIGHT, HALF_SIZE },
        .{ 0.0, 0.0, -1.0 },
        wall_color,
    );

    // 4. West Wall (at X = -HALF_SIZE, facing +X inward)
    idx = putQuad(
        vertices,
        idx,
        .{ -HALF_SIZE, 0.0, HALF_SIZE },
        .{ -HALF_SIZE, 0.0, -HALF_SIZE },
        .{ -HALF_SIZE, WALL_HEIGHT, -HALF_SIZE },
        .{ -HALF_SIZE, WALL_HEIGHT, HALF_SIZE },
        .{ 1.0, 0.0, 0.0 },
        wall_color,
    );

    // 5. East Wall (at X = +HALF_SIZE, facing -X inward)
    idx = putQuad(
        vertices,
        idx,
        .{ HALF_SIZE, 0.0, -HALF_SIZE },
        .{ HALF_SIZE, 0.0, HALF_SIZE },
        .{ HALF_SIZE, WALL_HEIGHT, HALF_SIZE },
        .{ HALF_SIZE, WALL_HEIGHT, -HALF_SIZE },
        .{ -1.0, 0.0, 0.0 },
        wall_color,
    );

    // 6. Ramp (facing +Y/-Z upward-forward)
    _ = putQuad(
        vertices,
        idx,
        .{ RAMP_X_MIN, 0.0, RAMP_Z_MIN },
        .{ RAMP_X_MIN, RAMP_HEIGHT, RAMP_Z_MAX },
        .{ RAMP_X_MAX, RAMP_HEIGHT, RAMP_Z_MAX },
        .{ RAMP_X_MAX, 0.0, RAMP_Z_MIN },
        .{ 0.0, 0.9578, -0.2873 },
        ramp_color,
    );

    return vertices;
}

test "surface height calculations" {
    // Floor
    try std.testing.expectEqual(@as(f32, 0.0), getSurfaceHeight(0.0, 0.0));
    try std.testing.expectEqual(@as(f32, 0.0), getSurfaceHeight(10.0, 10.0));

    // Ramp start, mid, end
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), getSurfaceHeight(0.0, 2.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), getSurfaceHeight(0.0, 4.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), getSurfaceHeight(0.0, 6.0), 0.001);
}

test "boundary collision resolution" {
    var pos = Vec3.new(15.0, 0.5, 0.0);
    var vel = Vec3.new(10.0, 0.0, 0.0);
    const radius: f32 = 0.5;

    const grounded = resolveCollision(&pos, &vel, radius);
    try std.testing.expect(grounded);
    try std.testing.expectEqual(HALF_SIZE - radius, pos.x);
    try std.testing.expect(vel.x < 0.0); // bounced back
}

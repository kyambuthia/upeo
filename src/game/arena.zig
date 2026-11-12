const std = @import("std");
const mesh = @import("../engine/gfx/mesh.zig");
const Vertex = mesh.Vertex;
const putQuad = mesh.putQuad;

pub fn generateArenaMesh(allocator: std.mem.Allocator) ![]Vertex {
    const total_verts: usize = 6 * 6; // 6 quads * 6 vertices each
    const vertices = try allocator.alloc(Vertex, total_verts);
    errdefer allocator.free(vertices);

    const floor_color = [3]f32{ 0.25, 0.35, 0.45 };
    const wall_color = [3]f32{ 0.75, 0.55, 0.25 };
    const ramp_color = [3]f32{ 0.35, 0.70, 0.45 };

    const half_size: f32 = 12.0;
    const wall_h: f32 = 1.0;

    var idx: usize = 0;

    // 1. Main floor
    idx = putQuad(
        vertices,
        idx,
        .{ -half_size, 0.0, -half_size },
        .{ half_size, 0.0, -half_size },
        .{ half_size, 0.0, half_size },
        .{ -half_size, 0.0, half_size },
        .{ 0.0, 1.0, 0.0 },
        floor_color,
    );

    // 2. North Wall
    idx = putQuad(
        vertices,
        idx,
        .{ -half_size, 0.0, -half_size },
        .{ -half_size, wall_h, -half_size },
        .{ half_size, wall_h, -half_size },
        .{ half_size, 0.0, -half_size },
        .{ 0.0, 0.0, 1.0 },
        wall_color,
    );

    // 3. South Wall
    idx = putQuad(
        vertices,
        idx,
        .{ half_size, 0.0, half_size },
        .{ half_size, wall_h, half_size },
        .{ -half_size, wall_h, half_size },
        .{ -half_size, 0.0, half_size },
        .{ 0.0, 0.0, -1.0 },
        wall_color,
    );

    // 4. West Wall
    idx = putQuad(
        vertices,
        idx,
        .{ -half_size, 0.0, half_size },
        .{ -half_size, wall_h, half_size },
        .{ -half_size, wall_h, -half_size },
        .{ -half_size, 0.0, -half_size },
        .{ 1.0, 0.0, 0.0 },
        wall_color,
    );

    // 5. East Wall
    idx = putQuad(
        vertices,
        idx,
        .{ half_size, 0.0, -half_size },
        .{ half_size, wall_h, -half_size },
        .{ half_size, wall_h, half_size },
        .{ half_size, 0.0, half_size },
        .{ -1.0, 0.0, 0.0 },
        wall_color,
    );

    // 6. Ramp
    const rx0: f32 = -3.0;
    const rx1: f32 = 3.0;
    const rz0: f32 = 2.0;
    const rz1: f32 = 6.0;
    const ramp_height: f32 = 1.2;

    _ = putQuad(
        vertices,
        idx,
        .{ rx0, 0.0, rz0 },
        .{ rx1, 0.0, rz0 },
        .{ rx1, ramp_height, rz1 },
        .{ rx0, ramp_height, rz1 },
        .{ 0.0, 0.9, -0.4 },
        ramp_color,
    );

    return vertices;
}

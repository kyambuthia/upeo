const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;

pub const Vertex = extern struct {
    pos: [3]f32,
    normal: [3]f32,
    color: [3]f32,
};

pub fn generateSphere(allocator: std.mem.Allocator, radius: f32, rings: usize, sectors: usize) ![]Vertex {
    const total_verts = rings * sectors * 6;
    const vertices = try allocator.alloc(Vertex, total_verts);
    errdefer allocator.free(vertices);

    const R = 1.0 / @as(f32, @floatFromInt(rings));
    const S = 1.0 / @as(f32, @floatFromInt(sectors));

    var idx: usize = 0;
    var r: usize = 0;
    while (r < rings) : (r += 1) {
        var s: usize = 0;
        while (s < sectors) : (s += 1) {
            const rf0 = @as(f32, @floatFromInt(r));
            const rf1 = @as(f32, @floatFromInt(r + 1));
            const sf0 = @as(f32, @floatFromInt(s));
            const sf1 = @as(f32, @floatFromInt(s + 1));

            const y0 = @sin(-std.math.pi / 2.0 + std.math.pi * rf0 * R);
            const y1 = @sin(-std.math.pi / 2.0 + std.math.pi * rf1 * R);
            const cos_y0 = @cos(-std.math.pi / 2.0 + std.math.pi * rf0 * R);
            const cos_y1 = @cos(-std.math.pi / 2.0 + std.math.pi * rf1 * R);

            const x00 = cos_y0 * @sin(2.0 * std.math.pi * sf0 * S);
            const z00 = cos_y0 * @cos(2.0 * std.math.pi * sf0 * S);
            const x10 = cos_y1 * @sin(2.0 * std.math.pi * sf0 * S);
            const z10 = cos_y1 * @cos(2.0 * std.math.pi * sf0 * S);

            const x01 = cos_y0 * @sin(2.0 * std.math.pi * sf1 * S);
            const z01 = cos_y0 * @cos(2.0 * std.math.pi * sf1 * S);
            const x11 = cos_y1 * @sin(2.0 * std.math.pi * sf1 * S);
            const z11 = cos_y1 * @cos(2.0 * std.math.pi * sf1 * S);

            // Alternate colors for a patterned marble so rolling spin is clearly visible
            const is_stripe = (s % 2 == 0);
            const col = if (is_stripe) [3]f32{ 0.95, 0.35, 0.15 } else [3]f32{ 0.95, 0.90, 0.85 };

            const v00 = Vertex{ .pos = .{ x00 * radius, y0 * radius, z00 * radius }, .normal = .{ x00, y0, z00 }, .color = col };
            const v10 = Vertex{ .pos = .{ x10 * radius, y1 * radius, z10 * radius }, .normal = .{ x10, y1, z10 }, .color = col };
            const v11 = Vertex{ .pos = .{ x11 * radius, y1 * radius, z11 * radius }, .normal = .{ x11, y1, z11 }, .color = col };
            const v01 = Vertex{ .pos = .{ x01 * radius, y0 * radius, z01 * radius }, .normal = .{ x01, y0, z01 }, .color = col };

            // Triangle 1
            vertices[idx + 0] = v00;
            vertices[idx + 1] = v10;
            vertices[idx + 2] = v11;

            // Triangle 2
            vertices[idx + 3] = v00;
            vertices[idx + 4] = v11;
            vertices[idx + 5] = v01;

            idx += 6;
        }
    }

    return vertices;
}

fn putQuad(slice: []Vertex, start_idx: usize, p0: [3]f32, p1: [3]f32, p2: [3]f32, p3: [3]f32, normal: [3]f32, color: [3]f32) usize {
    const v0 = Vertex{ .pos = p0, .normal = normal, .color = color };
    const v1 = Vertex{ .pos = p1, .normal = normal, .color = color };
    const v2 = Vertex{ .pos = p2, .normal = normal, .color = color };
    const v3 = Vertex{ .pos = p3, .normal = normal, .color = color };

    slice[start_idx + 0] = v0;
    slice[start_idx + 1] = v1;
    slice[start_idx + 2] = v2;

    slice[start_idx + 3] = v0;
    slice[start_idx + 4] = v2;
    slice[start_idx + 5] = v3;

    return start_idx + 6;
}

pub fn generateArena(allocator: std.mem.Allocator) ![]Vertex {
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

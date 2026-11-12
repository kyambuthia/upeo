const std = @import("std");

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

            // Patterned stripes to visualize rotational rolling
            const is_stripe = (s % 2 == 0);
            const col = if (is_stripe) [3]f32{ 0.95, 0.35, 0.15 } else [3]f32{ 0.95, 0.90, 0.85 };

            const v00 = Vertex{ .pos = .{ x00 * radius, y0 * radius, z00 * radius }, .normal = .{ x00, y0, z00 }, .color = col };
            const v10 = Vertex{ .pos = .{ x10 * radius, y1 * radius, z10 * radius }, .normal = .{ x10, y1, z10 }, .color = col };
            const v11 = Vertex{ .pos = .{ x11 * radius, y1 * radius, z11 * radius }, .normal = .{ x11, y1, z11 }, .color = col };
            const v01 = Vertex{ .pos = .{ x01 * radius, y0 * radius, z01 * radius }, .normal = .{ x01, y0, z01 }, .color = col };

            // Outward-facing counter-clockwise triangles
            vertices[idx + 0] = v00;
            vertices[idx + 1] = v11;
            vertices[idx + 2] = v10;

            vertices[idx + 3] = v00;
            vertices[idx + 4] = v01;
            vertices[idx + 5] = v11;

            idx += 6;
        }
    }

    return vertices;
}

pub fn putQuad(slice: []Vertex, start_idx: usize, p0: [3]f32, p1: [3]f32, p2: [3]f32, p3: [3]f32, normal: [3]f32, color: [3]f32) usize {
    const v0 = Vertex{ .pos = p0, .normal = normal, .color = color };
    const v1 = Vertex{ .pos = p1, .normal = normal, .color = color };
    const v2 = Vertex{ .pos = p2, .normal = normal, .color = color };
    const v3 = Vertex{ .pos = p3, .normal = normal, .color = color };

    // Standard CCW quad triangulation: (v0, v1, v2) and (v0, v2, v3)
    slice[start_idx + 0] = v0;
    slice[start_idx + 1] = v1;
    slice[start_idx + 2] = v2;

    slice[start_idx + 3] = v0;
    slice[start_idx + 4] = v2;
    slice[start_idx + 5] = v3;

    return start_idx + 6;
}

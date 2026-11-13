//! Generic vertex buffers, index buffers (EBO), and comptime vertex attribute
//! layout binding for OpenGL ES 3.0.

const std = @import("std");
const c = @import("../platform/c.zig").c;
const gl = @import("gl.zig");
const math = @import("../math/math.zig");
const Vertex = @import("mesh.zig").Vertex;

pub const BufferUsage = enum {
    static,
    dynamic,

    fn toGl(self: BufferUsage) gl.GLenum {
        return switch (self) {
            .static => c.GL_STATIC_DRAW,
            .dynamic => c.GL_DYNAMIC_DRAW,
        };
    }
};

pub const MeshBuffer = struct {
    vao: gl.GLuint,
    vbo: gl.GLuint,
    ebo: gl.GLuint = 0,
    vertex_count: gl.GLsizei,
    index_count: gl.GLsizei = 0,

    pub fn init(vertices: []const Vertex) MeshBuffer {
        return initTyped(Vertex, vertices, .static);
    }

    pub fn initTyped(comptime V: type, vertices: []const V, usage: BufferUsage) MeshBuffer {
        var vao: gl.GLuint = 0;
        var vbo: gl.GLuint = 0;

        gl.GenVertexArrays(1, &vao);
        gl.GenBuffers(1, &vbo);

        gl.BindVertexArray(vao);
        gl.BindBuffer(c.GL_ARRAY_BUFFER, vbo);
        gl.BufferData(
            c.GL_ARRAY_BUFFER,
            @intCast(vertices.len * @sizeOf(V)),
            vertices.ptr,
            usage.toGl(),
        );

        bindVertexLayout(V);
        gl.BindVertexArray(0);

        return .{
            .vao = vao,
            .vbo = vbo,
            .vertex_count = @intCast(vertices.len),
        };
    }

    pub fn initIndexed(comptime V: type, vertices: []const V, indices: []const u32, usage: BufferUsage) MeshBuffer {
        var vao: gl.GLuint = 0;
        var vbo: gl.GLuint = 0;
        var ebo: gl.GLuint = 0;

        gl.GenVertexArrays(1, &vao);
        gl.GenBuffers(1, &vbo);
        gl.GenBuffers(1, &ebo);

        gl.BindVertexArray(vao);
        gl.BindBuffer(c.GL_ARRAY_BUFFER, vbo);
        gl.BufferData(
            c.GL_ARRAY_BUFFER,
            @intCast(vertices.len * @sizeOf(V)),
            vertices.ptr,
            usage.toGl(),
        );

        gl.BindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, ebo);
        gl.BufferData(
            c.GL_ELEMENT_ARRAY_BUFFER,
            @intCast(indices.len * @sizeOf(u32)),
            indices.ptr,
            usage.toGl(),
        );

        bindVertexLayout(V);
        gl.BindVertexArray(0);

        return .{
            .vao = vao,
            .vbo = vbo,
            .ebo = ebo,
            .vertex_count = @intCast(vertices.len),
            .index_count = @intCast(indices.len),
        };
    }

    pub fn updateVertices(self: MeshBuffer, comptime V: type, vertices: []const V, offset_vertices: usize) void {
        gl.BindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        gl.BufferSubData(
            c.GL_ARRAY_BUFFER,
            @intCast(offset_vertices * @sizeOf(V)),
            @intCast(vertices.len * @sizeOf(V)),
            vertices.ptr,
        );
    }

    pub fn deinit(self: MeshBuffer) void {
        var vbo = self.vbo;
        var vao = self.vao;
        gl.DeleteBuffers(1, &vbo);
        if (self.ebo != 0) {
            var ebo = self.ebo;
            gl.DeleteBuffers(1, &ebo);
        }
        gl.DeleteVertexArrays(1, &vao);
    }

    pub fn draw(self: MeshBuffer) void {
        gl.BindVertexArray(self.vao);
        if (self.ebo != 0) {
            gl.DrawElements(c.GL_TRIANGLES, self.index_count, c.GL_UNSIGNED_INT, null);
        } else {
            gl.DrawArrays(c.GL_TRIANGLES, 0, self.vertex_count);
        }
        gl.BindVertexArray(0);
    }

    pub fn drawInstanced(self: MeshBuffer, instance_count: usize) void {
        gl.BindVertexArray(self.vao);
        if (self.ebo != 0) {
            gl.DrawElementsInstanced(c.GL_TRIANGLES, self.index_count, c.GL_UNSIGNED_INT, null, @intCast(instance_count));
        } else {
            gl.DrawArraysInstanced(c.GL_TRIANGLES, 0, self.vertex_count, @intCast(instance_count));
        }
        gl.BindVertexArray(0);
    }
};

/// Binds vertex attributes at locations `0..N-1` from an `extern struct`'s fields.
pub fn bindVertexLayout(comptime V: type) void {
    const info = @typeInfo(V).@"struct";
    comptime std.debug.assert(info.layout == .@"extern");
    const stride: gl.GLsizei = @sizeOf(V);

    inline for (info.field_names, info.field_types, 0..) |name, F, loc| {
        const lanes = comptime floatLanes(F);
        gl.EnableVertexAttribArray(@intCast(loc));
        gl.VertexAttribPointer(
            @intCast(loc),
            lanes,
            c.GL_FLOAT,
            c.GL_FALSE,
            stride,
            @ptrFromInt(@offsetOf(V, name)),
        );
    }
}

pub fn floatLanes(comptime F: type) gl.GLint {
    return switch (F) {
        f32 => 1,
        [2]f32, math.Vec2 => 2,
        [3]f32, math.Vec3 => 3,
        [4]f32, math.Vec4 => 4,
        else => @compileError("Unsupported vertex attribute field type: " ++ @typeName(F)),
    };
}

test "floatLanes maps scalar, array, and vector types" {
    try std.testing.expectEqual(@as(gl.GLint, 3), floatLanes([3]f32));
    try std.testing.expectEqual(@as(gl.GLint, 3), floatLanes(math.Vec3));
    try std.testing.expectEqual(@as(gl.GLint, 2), floatLanes(math.Vec2));
    try std.testing.expectEqual(@as(gl.GLint, 4), floatLanes(math.Vec4));
}

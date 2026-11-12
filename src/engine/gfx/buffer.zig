const std = @import("std");
const c = @import("../platform/c.zig").c;
const Vertex = @import("mesh.zig").Vertex;

pub const MeshBuffer = struct {
    vao: c.GLuint,
    vbo: c.GLuint,
    vertex_count: c.GLsizei,

    pub fn init(vertices: []const Vertex) MeshBuffer {
        var vao: c.GLuint = 0;
        var vbo: c.GLuint = 0;

        c.glGenVertexArrays(1, &vao);
        c.glGenBuffers(1, &vbo);

        c.glBindVertexArray(vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            @intCast(vertices.len * @sizeOf(Vertex)),
            vertices.ptr,
            c.GL_STATIC_DRAW,
        );

        const stride = @sizeOf(Vertex);

        // Attribute 0: Position
        c.glEnableVertexAttribArray(0);
        c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "pos")));

        // Attribute 1: Normal
        c.glEnableVertexAttribArray(1);
        c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "normal")));

        // Attribute 2: Color
        c.glEnableVertexAttribArray(2);
        c.glVertexAttribPointer(2, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "color")));

        c.glBindVertexArray(0);

        return .{
            .vao = vao,
            .vbo = vbo,
            .vertex_count = @intCast(vertices.len),
        };
    }

    pub fn deinit(self: MeshBuffer) void {
        var vbo = self.vbo;
        var vao = self.vao;
        c.glDeleteBuffers(1, &vbo);
        c.glDeleteVertexArrays(1, &vao);
    }

    pub fn draw(self: MeshBuffer) void {
        c.glBindVertexArray(self.vao);
        c.glDrawArrays(c.GL_TRIANGLES, 0, self.vertex_count);
        c.glBindVertexArray(0);
    }
};

const c = @import("../platform/c.zig").c;
const gl = @import("gl.zig");
const Vertex = @import("mesh.zig").Vertex;

pub const MeshBuffer = struct {
    vao: gl.GLuint,
    vbo: gl.GLuint,
    vertex_count: gl.GLsizei,

    pub fn init(vertices: []const Vertex) MeshBuffer {
        var vao: gl.GLuint = 0;
        var vbo: gl.GLuint = 0;

        gl.GenVertexArrays(1, &vao);
        gl.GenBuffers(1, &vbo);

        gl.BindVertexArray(vao);
        gl.BindBuffer(c.GL_ARRAY_BUFFER, vbo);
        gl.BufferData(
            c.GL_ARRAY_BUFFER,
            @intCast(vertices.len * @sizeOf(Vertex)),
            vertices.ptr,
            c.GL_STATIC_DRAW,
        );

        const stride = @sizeOf(Vertex);

        // Attribute 0: Position
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "pos")));

        // Attribute 1: Normal
        gl.EnableVertexAttribArray(1);
        gl.VertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "normal")));

        // Attribute 2: Color
        gl.EnableVertexAttribArray(2);
        gl.VertexAttribPointer(2, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "color")));

        gl.BindVertexArray(0);

        return .{
            .vao = vao,
            .vbo = vbo,
            .vertex_count = @intCast(vertices.len),
        };
    }

    pub fn deinit(self: MeshBuffer) void {
        var vbo = self.vbo;
        var vao = self.vao;
        gl.DeleteBuffers(1, &vbo);
        gl.DeleteVertexArrays(1, &vao);
    }

    pub fn draw(self: MeshBuffer) void {
        gl.BindVertexArray(self.vao);
        gl.DrawArrays(c.GL_TRIANGLES, 0, self.vertex_count);
        gl.BindVertexArray(0);
    }
};

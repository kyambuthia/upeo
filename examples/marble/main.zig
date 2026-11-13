const std = @import("std");

const upeo = @import("upeo");
const Engine = upeo.app.Engine;
const c = upeo.c;
const gl = upeo.gfx.gl;
const ShaderProgram = upeo.gfx.ShaderProgram;
const shader_src = upeo.gfx.shaders;
const MeshBuffer = upeo.gfx.MeshBuffer;
const mesh = upeo.gfx.mesh;
const Mat4 = upeo.math.Mat4;
const Key = upeo.input.Key;

const Marble = @import("marble.zig").Marble;
const Camera = @import("camera.zig").Camera;
const arena = @import("arena.zig");

test {
    _ = @import("marble.zig");
    _ = @import("arena.zig");
}

const MarbleGame = struct {
    program: ShaderProgram,
    sphere_buf: MeshBuffer,
    arena_buf: MeshBuffer,
    marble: Marble = .{},
    camera: Camera = .{},

    pub fn init(engine: *Engine) !MarbleGame {
        const program = try ShaderProgram.init(
            shader_src.DEFAULT_VERTEX_SHADER,
            shader_src.DEFAULT_FRAGMENT_SHADER,
        );
        errdefer program.deinit();

        const sphere_verts = try mesh.generateSphere(engine.allocator, 0.5, 20, 28);
        defer engine.allocator.free(sphere_verts);
        const sphere_buf = MeshBuffer.init(sphere_verts);

        const arena_verts = try arena.generateArenaMesh(engine.allocator);
        defer engine.allocator.free(arena_verts);
        const arena_buf = MeshBuffer.init(arena_verts);

        gl.Enable(c.GL_DEPTH_TEST);
        gl.DepthFunc(c.GL_LESS);
        gl.Enable(c.GL_CULL_FACE);
        gl.CullFace(c.GL_BACK);

        return .{
            .program = program,
            .sphere_buf = sphere_buf,
            .arena_buf = arena_buf,
        };
    }

    pub fn deinit(self: *MarbleGame, _: *Engine) void {
        self.arena_buf.deinit();
        self.sphere_buf.deinit();
        self.program.deinit();
    }

    pub fn fixedUpdate(self: *MarbleGame, engine: *Engine, dt: f32) void {
        self.marble.update(engine.input, dt);
        self.camera.update(self.marble.pos, dt);
    }

    pub fn update(_: *MarbleGame, engine: *Engine, _: f32) void {
        if (engine.input.wasKeyPressed(Key.escape)) {
            engine.quit();
        }
    }

    pub fn render(self: *MarbleGame, engine: *Engine, _: f32) void {
        gl.ClearColor(0.14, 0.18, 0.24, 1.0);
        gl.Clear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        self.program.use();

        const proj_matrix = Mat4.perspective(std.math.degreesToRadians(55.0), engine.window.aspect(), 0.1, 100.0);
        const view_matrix = self.camera.getViewMatrix();

        ShaderProgram.setMat4(self.program.u_projection, proj_matrix.m);
        ShaderProgram.setMat4(self.program.u_view, view_matrix.m);

        ShaderProgram.setMat4(self.program.u_model, Mat4.identity().m);
        self.arena_buf.draw();

        ShaderProgram.setMat4(self.program.u_model, self.marble.getModelMatrix().m);
        self.sphere_buf.draw();
    }
};

pub fn main() !void {
    try upeo.app.run(MarbleGame, .{
        .window = .{
            .title = "Upeo - Universal 3D Engine (Zig + SDL3 + OpenGL ES 3.0)",
            .width = 1024,
            .height = 768,
            .vsync = true,
        },
    });
}

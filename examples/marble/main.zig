const std = @import("std");

const upeo = @import("upeo");
const Window = upeo.platform.Window;
const c = upeo.c;
const Input = upeo.input.Input;
const Clock = upeo.time.Clock;
const ShaderProgram = upeo.gfx.ShaderProgram;
const gl = upeo.gfx.gl;
const shader_src = upeo.gfx.shaders;
const MeshBuffer = upeo.gfx.MeshBuffer;
const mesh = upeo.gfx.mesh;
const math = upeo.math;
const Mat4 = math.Mat4;

// Game components
const Marble = @import("marble.zig").Marble;
const Camera = @import("camera.zig").Camera;
const arena = @import("arena.zig");

test {
    _ = @import("marble.zig");
    _ = @import("arena.zig");
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var window = try Window.init(.{
        .title = "Upeo - Universal 3D Engine (Zig + SDL3 + OpenGL ES 3.0)",
        .width = 1024,
        .height = 768,
        .vsync = true,
    });
    defer window.deinit();

    // Compile Shader Pipeline
    const program = try ShaderProgram.init(
        shader_src.DEFAULT_VERTEX_SHADER,
        shader_src.DEFAULT_FRAGMENT_SHADER,
    );
    defer program.deinit();

    // Build Geometry
    const sphere_verts = try mesh.generateSphere(allocator, 0.5, 20, 28);
    defer allocator.free(sphere_verts);
    const sphere_buf = MeshBuffer.init(sphere_verts);
    defer sphere_buf.deinit();

    const arena_verts = try arena.generateArenaMesh(allocator);
    defer allocator.free(arena_verts);
    const arena_buf = MeshBuffer.init(arena_verts);
    defer arena_buf.deinit();

    // Setup GLES State
    gl.Enable(c.GL_DEPTH_TEST);
    gl.DepthFunc(c.GL_LESS);
    gl.Enable(c.GL_CULL_FACE);
    gl.CullFace(c.GL_BACK);

    var marble = Marble{};
    var camera = Camera{};
    var input = Input{};
    var clock = Clock.init();

    while (!input.quit_requested) {
        input.resetFrame();

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            input.processEvent(event);
        }

        if (input.resized) {
            window.updateSize();
        }

        const dt = clock.tick();

        // Update Simulation
        marble.update(input, dt);
        camera.update(marble.pos, dt);

        // Render Frame
        gl.ClearColor(0.14, 0.18, 0.24, 1.0);
        gl.Clear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        program.use();

        const proj_matrix = Mat4.perspective(std.math.degreesToRadians(55.0), window.aspect(), 0.1, 100.0);
        const view_matrix = camera.getViewMatrix();

        ShaderProgram.setMat4(program.u_projection, proj_matrix.m);
        ShaderProgram.setMat4(program.u_view, view_matrix.m);

        // Draw Arena
        ShaderProgram.setMat4(program.u_model, Mat4.identity().m);
        arena_buf.draw();

        // Draw Marble
        ShaderProgram.setMat4(program.u_model, marble.getModelMatrix().m);
        sphere_buf.draw();

        window.swap();
    }
}

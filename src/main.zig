const std = @import("std");
const c = @import("c.zig").c;
const math = @import("math.zig");
const mesh = @import("mesh.zig");
const shader = @import("shader.zig");
const game = @import("game.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Vertex = mesh.Vertex;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init Error: {s}\n", .{c.SDL_GetError()});
        return error.SdlInitFailed;
    }
    defer c.SDL_Quit();

    // Configure OpenGL ES 3.0 context
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_ES);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 0);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_DEPTH_SIZE, 24);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_DOUBLEBUFFER, 1);

    var width: i32 = 1024;
    var height: i32 = 768;

    const window = c.SDL_CreateWindow(
        "3D Marble - Direct OpenGL (Zig + SDL3)",
        width,
        height,
        c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE,
    ) orelse {
        std.debug.print("SDL_CreateWindow Error: {s}\n", .{c.SDL_GetError()});
        return error.SdlCreateWindowFailed;
    };
    defer c.SDL_DestroyWindow(window);

    const gl_context = c.SDL_GL_CreateContext(window) orelse {
        std.debug.print("SDL_GL_CreateContext Error: {s}\n", .{c.SDL_GetError()});
        return error.SdlGlCreateContextFailed;
    };
    defer _ = c.SDL_GL_DestroyContext(gl_context);

    _ = c.SDL_GL_SetSwapInterval(1); // Enable VSync

    std.debug.print("OpenGL Version: {s}\n", .{c.glGetString(c.GL_VERSION)});
    std.debug.print("GLSL Version:   {s}\n", .{c.glGetString(c.GL_SHADING_LANGUAGE_VERSION)});

    // Compile Shaders
    const program = try shader.ShaderProgram.init(
        shader.VERTEX_SHADER_SOURCE,
        shader.FRAGMENT_SHADER_SOURCE,
    );
    defer program.deinit();

    // Generate Meshes
    const sphere_verts = try mesh.generateSphere(allocator, 0.5, 20, 28);
    defer allocator.free(sphere_verts);

    const arena_verts = try mesh.generateArena(allocator);
    defer allocator.free(arena_verts);

    // Setup Sphere VAO & VBO
    var sphere_vao: c.GLuint = 0;
    var sphere_vbo: c.GLuint = 0;
    c.glGenVertexArrays(1, &sphere_vao);
    c.glGenBuffers(1, &sphere_vbo);

    c.glBindVertexArray(sphere_vao);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, sphere_vbo);
    c.glBufferData(
        c.GL_ARRAY_BUFFER,
        @intCast(sphere_verts.len * @sizeOf(Vertex)),
        sphere_verts.ptr,
        c.GL_STATIC_DRAW,
    );
    setupVertexAttributes();

    // Setup Arena VAO & VBO
    var arena_vao: c.GLuint = 0;
    var arena_vbo: c.GLuint = 0;
    c.glGenVertexArrays(1, &arena_vao);
    c.glGenBuffers(1, &arena_vbo);

    c.glBindVertexArray(arena_vao);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, arena_vbo);
    c.glBufferData(
        c.GL_ARRAY_BUFFER,
        @intCast(arena_verts.len * @sizeOf(Vertex)),
        arena_verts.ptr,
        c.GL_STATIC_DRAW,
    );
    setupVertexAttributes();

    c.glBindVertexArray(0);

    // OpenGL State
    c.glEnable(c.GL_DEPTH_TEST);
    c.glDepthFunc(c.GL_LESS);
    c.glEnable(c.GL_CULL_FACE);
    c.glCullFace(c.GL_BACK);

    var marble = game.Marble{};
    var camera = game.Camera{};
    var input = game.InputState{};

    var is_running = true;
    var last_time = c.SDL_GetTicks();

    while (is_running) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    is_running = false;
                },
                c.SDL_EVENT_WINDOW_RESIZED, c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => {
                    _ = c.SDL_GetWindowSize(window, &width, &height);
                    c.glViewport(0, 0, width, height);
                },
                c.SDL_EVENT_KEY_DOWN => {
                    const sc = event.key.scancode;
                    if (sc == c.SDL_SCANCODE_W or sc == c.SDL_SCANCODE_UP) input.up = true;
                    if (sc == c.SDL_SCANCODE_S or sc == c.SDL_SCANCODE_DOWN) input.down = true;
                    if (sc == c.SDL_SCANCODE_A or sc == c.SDL_SCANCODE_LEFT) input.left = true;
                    if (sc == c.SDL_SCANCODE_D or sc == c.SDL_SCANCODE_RIGHT) input.right = true;
                    if (sc == c.SDL_SCANCODE_SPACE) input.jump = true;
                    if (sc == c.SDL_SCANCODE_ESCAPE) is_running = false;
                },
                c.SDL_EVENT_KEY_UP => {
                    const sc = event.key.scancode;
                    if (sc == c.SDL_SCANCODE_W or sc == c.SDL_SCANCODE_UP) input.up = false;
                    if (sc == c.SDL_SCANCODE_S or sc == c.SDL_SCANCODE_DOWN) input.down = false;
                    if (sc == c.SDL_SCANCODE_A or sc == c.SDL_SCANCODE_LEFT) input.left = false;
                    if (sc == c.SDL_SCANCODE_D or sc == c.SDL_SCANCODE_RIGHT) input.right = false;
                    if (sc == c.SDL_SCANCODE_SPACE) input.jump = false;
                },
                else => {},
            }
        }

        const now = c.SDL_GetTicks();
        const delta_ms = now - last_time;
        last_time = now;
        const dt: f32 = @min(@as(f32, @floatFromInt(delta_ms)) / 1000.0, 0.05);

        // Update physics & camera
        marble.update(input, dt);
        camera.update(marble.pos, dt);

        // Render Frame
        c.glClearColor(0.14, 0.18, 0.24, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        program.use();

        const aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(@max(height, 1)));
        const proj_matrix = Mat4.perspective(std.math.degreesToRadians(55.0), aspect, 0.1, 100.0);
        const view_matrix = camera.getViewMatrix();

        c.glUniformMatrix4fv(program.u_projection, 1, c.GL_FALSE, &proj_matrix.m);
        c.glUniformMatrix4fv(program.u_view, 1, c.GL_FALSE, &view_matrix.m);

        // 1. Draw Arena
        const arena_model = Mat4.identity();
        c.glUniformMatrix4fv(program.u_model, 1, c.GL_FALSE, &arena_model.m);
        c.glBindVertexArray(arena_vao);
        c.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(arena_verts.len));

        // 2. Draw Marble
        const marble_model = marble.getModelMatrix();
        c.glUniformMatrix4fv(program.u_model, 1, c.GL_FALSE, &marble_model.m);
        c.glBindVertexArray(sphere_vao);
        c.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(sphere_verts.len));

        c.glBindVertexArray(0);

        _ = c.SDL_GL_SwapWindow(window);
    }

    c.glDeleteBuffers(1, &sphere_vbo);
    c.glDeleteVertexArrays(1, &sphere_vao);
    c.glDeleteBuffers(1, &arena_vbo);
    c.glDeleteVertexArrays(1, &arena_vao);
}

fn setupVertexAttributes() void {
    const stride = @sizeOf(Vertex);

    // Position (location = 0)
    c.glEnableVertexAttribArray(0);
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "pos")));

    // Normal (location = 1)
    c.glEnableVertexAttribArray(1);
    c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "normal")));

    // Color (location = 2)
    c.glEnableVertexAttribArray(2);
    c.glVertexAttribPointer(2, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(@offsetOf(Vertex, "color")));
}

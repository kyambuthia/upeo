const std = @import("std");
const c = @import("c.zig").c;
const gl = @import("../gfx/gl.zig");

const log = std.log.scoped(.platform);

pub const WindowConfig = struct {
    title: [:0]const u8 = "Upeo",
    width: i32 = 1024,
    height: i32 = 768,
    vsync: bool = true,
};

pub const Window = struct {
    sdl_window: *c.SDL_Window,
    gl_context: c.SDL_GLContext,
    width: i32,
    height: i32,

    pub fn init(config: WindowConfig) !Window {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
            log.err("SDL_Init failed: {s}", .{c.SDL_GetError()});
            return error.SdlInitFailed;
        }
        errdefer c.SDL_Quit();

        // Request OpenGL ES 3.0 context
        setGlAttr(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_ES);
        setGlAttr(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        setGlAttr(c.SDL_GL_CONTEXT_MINOR_VERSION, 0);
        setGlAttr(c.SDL_GL_DEPTH_SIZE, 24);
        setGlAttr(c.SDL_GL_DOUBLEBUFFER, 1);

        const flags = c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE;
        const window = c.SDL_CreateWindow(config.title.ptr, config.width, config.height, flags) orelse {
            log.err("SDL_CreateWindow failed: {s}", .{c.SDL_GetError()});
            return error.SdlCreateWindowFailed;
        };
        errdefer c.SDL_DestroyWindow(window);

        const gl_ctx = c.SDL_GL_CreateContext(window) orelse {
            log.err("SDL_GL_CreateContext failed: {s}", .{c.SDL_GetError()});
            return error.SdlGlCreateContextFailed;
        };
        errdefer _ = c.SDL_GL_DestroyContext(gl_ctx);

        try gl.load(&sdlGetProc);

        if (!c.SDL_GL_SetSwapInterval(if (config.vsync) 1 else 0)) {
            log.warn("SDL_GL_SetSwapInterval failed: {s}", .{c.SDL_GetError()});
        }

        if (gl.GetString(c.GL_VERSION)) |ver| {
            log.info("GL context: {s}", .{std.mem.span(ver)});
        }

        var self = Window{
            .sdl_window = window,
            .gl_context = gl_ctx,
            .width = config.width,
            .height = config.height,
        };
        self.updateSize();
        return self;
    }

    pub fn deinit(self: *Window) void {
        _ = c.SDL_GL_DestroyContext(self.gl_context);
        c.SDL_DestroyWindow(self.sdl_window);
        c.SDL_Quit();
    }

    pub fn swap(self: *Window) void {
        _ = c.SDL_GL_SwapWindow(self.sdl_window);
    }

    pub fn updateSize(self: *Window) void {
        _ = c.SDL_GetWindowSizeInPixels(self.sdl_window, &self.width, &self.height);
        gl.Viewport(0, 0, self.width, self.height);
    }

    pub fn aspect(self: Window) f32 {
        return @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(@max(self.height, 1)));
    }
};

fn setGlAttr(attr: c.SDL_GLAttr, value: c_int) void {
    if (!c.SDL_GL_SetAttribute(attr, value)) {
        log.warn("SDL_GL_SetAttribute({d}, {d}) failed: {s}", .{ attr, value, c.SDL_GetError() });
    }
}

fn sdlGetProc(name: [*:0]const u8) ?*const anyopaque {
    return @ptrCast(c.SDL_GL_GetProcAddress(name));
}

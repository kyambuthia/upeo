//! Upeo engine root module.
//!
//! Games import this as `@import("upeo")` and never reach into engine
//! internals through relative paths.

pub const c = @import("engine/platform/c.zig").c;

pub const app = @import("engine/app.zig");
pub const core = @import("engine/core/core.zig");
pub const ecs = @import("engine/ecs/ecs.zig");
pub const math = @import("engine/math/math.zig");
pub const net = @import("engine/net/net.zig");
pub const time = @import("engine/core/time.zig");
pub const input = @import("engine/input/input.zig");

pub const platform = struct {
    pub const Window = @import("engine/platform/window.zig").Window;
    pub const WindowConfig = @import("engine/platform/window.zig").WindowConfig;
};

pub const gfx = struct {
    pub const gl = @import("engine/gfx/gl.zig");
    pub const ShaderProgram = @import("engine/gfx/shader.zig").ShaderProgram;
    pub const shaders = @import("engine/gfx/shader.zig");
    pub const MeshBuffer = @import("engine/gfx/buffer.zig").MeshBuffer;
    pub const BufferUsage = @import("engine/gfx/buffer.zig").BufferUsage;
    pub const Texture2D = @import("engine/gfx/texture.zig").Texture2D;
    pub const TextureConfig = @import("engine/gfx/texture.zig").TextureConfig;
    pub const Camera = @import("engine/gfx/camera.zig").Camera;
    pub const mesh = @import("engine/gfx/mesh.zig");
};

test {
    _ = core;
    _ = ecs;
    _ = math;
    _ = net;
    _ = time;
    _ = input;
    _ = gfx.gl;
    _ = gfx.mesh;
    _ = @import("engine/gfx/buffer.zig");
}

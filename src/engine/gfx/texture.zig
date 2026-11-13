//! 2D GPU textures (RGBA8 / RGB8 / R8) for OpenGL ES 3.0.

const c = @import("../platform/c.zig").c;
const gl = @import("gl.zig");

pub const Format = enum {
    r8,
    rgb8,
    rgba8,

    fn internalFormat(self: Format) gl.GLint {
        return switch (self) {
            .r8 => c.GL_R8,
            .rgb8 => c.GL_RGB8,
            .rgba8 => c.GL_RGBA8,
        };
    }

    fn pixelFormat(self: Format) gl.GLenum {
        return switch (self) {
            .r8 => c.GL_RED,
            .rgb8 => c.GL_RGB,
            .rgba8 => c.GL_RGBA,
        };
    }
};

pub const Filter = enum {
    nearest,
    linear,
    trilinear,
};

pub const Wrap = enum {
    repeat,
    clamp_to_edge,

    fn toGl(self: Wrap) gl.GLint {
        return switch (self) {
            .repeat => c.GL_REPEAT,
            .clamp_to_edge => c.GL_CLAMP_TO_EDGE,
        };
    }
};

pub const TextureConfig = struct {
    format: Format = .rgba8,
    filter: Filter = .linear,
    wrap: Wrap = .repeat,
    generate_mipmaps: bool = true,
};

pub const Texture2D = struct {
    id: gl.GLuint,
    width: u32,
    height: u32,

    pub fn init(width: u32, height: u32, pixels: ?[*]const u8, config: TextureConfig) Texture2D {
        var id: gl.GLuint = 0;
        gl.GenTextures(1, &id);
        gl.BindTexture(c.GL_TEXTURE_2D, id);

        gl.PixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        gl.TexImage2D(
            c.GL_TEXTURE_2D,
            0,
            config.format.internalFormat(),
            @intCast(width),
            @intCast(height),
            0,
            config.format.pixelFormat(),
            c.GL_UNSIGNED_BYTE,
            pixels,
        );

        const min_filter: gl.GLint = switch (config.filter) {
            .nearest => c.GL_NEAREST,
            .linear => c.GL_LINEAR,
            .trilinear => if (config.generate_mipmaps) c.GL_LINEAR_MIPMAP_LINEAR else c.GL_LINEAR,
        };
        const mag_filter: gl.GLint = if (config.filter == .nearest) c.GL_NEAREST else c.GL_LINEAR;

        gl.TexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, min_filter);
        gl.TexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, mag_filter);
        gl.TexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, config.wrap.toGl());
        gl.TexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, config.wrap.toGl());

        if (config.generate_mipmaps and pixels != null) {
            gl.GenerateMipmap(c.GL_TEXTURE_2D);
        }
        gl.BindTexture(c.GL_TEXTURE_2D, 0);

        return .{ .id = id, .width = width, .height = height };
    }

    pub fn bind(self: Texture2D, unit: u32) void {
        gl.ActiveTexture(c.GL_TEXTURE0 + unit);
        gl.BindTexture(c.GL_TEXTURE_2D, self.id);
    }

    pub fn deinit(self: Texture2D) void {
        var id = self.id;
        gl.DeleteTextures(1, &id);
    }
};

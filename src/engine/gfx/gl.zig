//! Runtime-loaded OpenGL ES 3.0 entry points.
//!
//! Every GL function the engine uses is declared here as a function pointer
//! and resolved once, after context creation, through
//! `SDL_GL_GetProcAddress`. Call sites use `gl.Clear(...)` etc.
//!
//! Adding a function: declare `pub var <Name>: Proc(c.PFNGL<NAME>PROC) = undefined;`
//! The loader picks up every `pub var` automatically, so nothing else changes.

const std = @import("std");
const c = @import("../platform/c.zig").c;

const log = std.log.scoped(.gl);

/// Strips the optional from a translated `PFNGL...PROC` typedef so call sites
/// don't need `.?` on every invocation.
fn Proc(comptime T: type) type {
    return @typeInfo(T).optional.child;
}

// Re-exported scalar types for convenience.
pub const GLuint = c.GLuint;
pub const GLint = c.GLint;
pub const GLenum = c.GLenum;
pub const GLsizei = c.GLsizei;
pub const GLfloat = c.GLfloat;

// --- State -------------------------------------------------------------
pub var Enable: Proc(c.PFNGLENABLEPROC) = undefined;
pub var Disable: Proc(c.PFNGLDISABLEPROC) = undefined;
pub var DepthFunc: Proc(c.PFNGLDEPTHFUNCPROC) = undefined;
pub var DepthMask: Proc(c.PFNGLDEPTHMASKPROC) = undefined;
pub var CullFace: Proc(c.PFNGLCULLFACEPROC) = undefined;
pub var FrontFace: Proc(c.PFNGLFRONTFACEPROC) = undefined;
pub var BlendFunc: Proc(c.PFNGLBLENDFUNCPROC) = undefined;
pub var Viewport: Proc(c.PFNGLVIEWPORTPROC) = undefined;
pub var Scissor: Proc(c.PFNGLSCISSORPROC) = undefined;
pub var ClearColor: Proc(c.PFNGLCLEARCOLORPROC) = undefined;
pub var Clear: Proc(c.PFNGLCLEARPROC) = undefined;
pub var GetError: Proc(c.PFNGLGETERRORPROC) = undefined;
pub var GetString: Proc(c.PFNGLGETSTRINGPROC) = undefined;
pub var GetIntegerv: Proc(c.PFNGLGETINTEGERVPROC) = undefined;
pub var PixelStorei: Proc(c.PFNGLPIXELSTOREIPROC) = undefined;

// --- Buffers & vertex arrays ------------------------------------------
pub var GenBuffers: Proc(c.PFNGLGENBUFFERSPROC) = undefined;
pub var DeleteBuffers: Proc(c.PFNGLDELETEBUFFERSPROC) = undefined;
pub var BindBuffer: Proc(c.PFNGLBINDBUFFERPROC) = undefined;
pub var BufferData: Proc(c.PFNGLBUFFERDATAPROC) = undefined;
pub var BufferSubData: Proc(c.PFNGLBUFFERSUBDATAPROC) = undefined;
pub var BindBufferBase: Proc(c.PFNGLBINDBUFFERBASEPROC) = undefined;
pub var MapBufferRange: Proc(c.PFNGLMAPBUFFERRANGEPROC) = undefined;
pub var UnmapBuffer: Proc(c.PFNGLUNMAPBUFFERPROC) = undefined;
pub var GenVertexArrays: Proc(c.PFNGLGENVERTEXARRAYSPROC) = undefined;
pub var DeleteVertexArrays: Proc(c.PFNGLDELETEVERTEXARRAYSPROC) = undefined;
pub var BindVertexArray: Proc(c.PFNGLBINDVERTEXARRAYPROC) = undefined;
pub var EnableVertexAttribArray: Proc(c.PFNGLENABLEVERTEXATTRIBARRAYPROC) = undefined;
pub var VertexAttribPointer: Proc(c.PFNGLVERTEXATTRIBPOINTERPROC) = undefined;
pub var VertexAttribIPointer: Proc(c.PFNGLVERTEXATTRIBIPOINTERPROC) = undefined;
pub var VertexAttribDivisor: Proc(c.PFNGLVERTEXATTRIBDIVISORPROC) = undefined;

// --- Drawing ------------------------------------------------------------
pub var DrawArrays: Proc(c.PFNGLDRAWARRAYSPROC) = undefined;
pub var DrawElements: Proc(c.PFNGLDRAWELEMENTSPROC) = undefined;
pub var DrawArraysInstanced: Proc(c.PFNGLDRAWARRAYSINSTANCEDPROC) = undefined;
pub var DrawElementsInstanced: Proc(c.PFNGLDRAWELEMENTSINSTANCEDPROC) = undefined;

// --- Shaders & programs -----------------------------------------------
pub var CreateShader: Proc(c.PFNGLCREATESHADERPROC) = undefined;
pub var DeleteShader: Proc(c.PFNGLDELETESHADERPROC) = undefined;
pub var ShaderSource: Proc(c.PFNGLSHADERSOURCEPROC) = undefined;
pub var CompileShader: Proc(c.PFNGLCOMPILESHADERPROC) = undefined;
pub var GetShaderiv: Proc(c.PFNGLGETSHADERIVPROC) = undefined;
pub var GetShaderInfoLog: Proc(c.PFNGLGETSHADERINFOLOGPROC) = undefined;
pub var CreateProgram: Proc(c.PFNGLCREATEPROGRAMPROC) = undefined;
pub var DeleteProgram: Proc(c.PFNGLDELETEPROGRAMPROC) = undefined;
pub var AttachShader: Proc(c.PFNGLATTACHSHADERPROC) = undefined;
pub var DetachShader: Proc(c.PFNGLDETACHSHADERPROC) = undefined;
pub var LinkProgram: Proc(c.PFNGLLINKPROGRAMPROC) = undefined;
pub var GetProgramiv: Proc(c.PFNGLGETPROGRAMIVPROC) = undefined;
pub var GetProgramInfoLog: Proc(c.PFNGLGETPROGRAMINFOLOGPROC) = undefined;
pub var UseProgram: Proc(c.PFNGLUSEPROGRAMPROC) = undefined;
pub var GetUniformLocation: Proc(c.PFNGLGETUNIFORMLOCATIONPROC) = undefined;
pub var GetUniformBlockIndex: Proc(c.PFNGLGETUNIFORMBLOCKINDEXPROC) = undefined;
pub var UniformBlockBinding: Proc(c.PFNGLUNIFORMBLOCKBINDINGPROC) = undefined;
pub var Uniform1i: Proc(c.PFNGLUNIFORM1IPROC) = undefined;
pub var Uniform1f: Proc(c.PFNGLUNIFORM1FPROC) = undefined;
pub var Uniform2fv: Proc(c.PFNGLUNIFORM2FVPROC) = undefined;
pub var Uniform3fv: Proc(c.PFNGLUNIFORM3FVPROC) = undefined;
pub var Uniform4fv: Proc(c.PFNGLUNIFORM4FVPROC) = undefined;
pub var UniformMatrix3fv: Proc(c.PFNGLUNIFORMMATRIX3FVPROC) = undefined;
pub var UniformMatrix4fv: Proc(c.PFNGLUNIFORMMATRIX4FVPROC) = undefined;

// --- Textures -------------------------------------------------------------
pub var GenTextures: Proc(c.PFNGLGENTEXTURESPROC) = undefined;
pub var DeleteTextures: Proc(c.PFNGLDELETETEXTURESPROC) = undefined;
pub var BindTexture: Proc(c.PFNGLBINDTEXTUREPROC) = undefined;
pub var ActiveTexture: Proc(c.PFNGLACTIVETEXTUREPROC) = undefined;
pub var TexImage2D: Proc(c.PFNGLTEXIMAGE2DPROC) = undefined;
pub var TexSubImage2D: Proc(c.PFNGLTEXSUBIMAGE2DPROC) = undefined;
pub var TexParameteri: Proc(c.PFNGLTEXPARAMETERIPROC) = undefined;
pub var GenerateMipmap: Proc(c.PFNGLGENERATEMIPMAPPROC) = undefined;

/// Signature of a GL symbol resolver (e.g. `SDL_GL_GetProcAddress`).
pub const LoaderFn = *const fn (name: [*:0]const u8) ?*const anyopaque;

pub const LoadError = error{MissingGlFunction};

/// Resolves every `pub var` function pointer in this file. Must be called
/// after a GL context is current. Returns an error naming nothing more than
/// "missing" but logs every symbol that failed to resolve.
pub fn load(getProc: LoaderFn) LoadError!void {
    var missing: usize = 0;
    inline for (@typeInfo(@This()).@"struct".decl_names) |decl_name| {
        const T = @TypeOf(@field(@This(), decl_name));
        if (comptime isGlProc(T)) {
            const sym = "gl" ++ decl_name;
            if (getProc(sym)) |ptr| {
                @field(@This(), decl_name) = @ptrCast(@alignCast(ptr));
            } else {
                log.err("unable to load {s}", .{sym});
                missing += 1;
            }
        }
    }
    if (missing != 0) return error.MissingGlFunction;
}

fn isGlProc(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    return @typeInfo(info.pointer.child) == .@"fn";
}

/// Debug helper: drains and logs pending GL errors. Compiled out of release
/// builds so it can be sprinkled liberally.
pub fn checkError(src: std.builtin.SourceLocation) void {
    if (@import("builtin").mode != .debug) return;
    while (true) {
        const err = GetError();
        if (err == c.GL_NO_ERROR) break;
        log.err("GL error 0x{x} at {s}:{d} ({s})", .{ err, src.file, src.line, src.fn_name });
    }
}

test "every declared GL proc is a function pointer" {
    var count: usize = 0;
    inline for (@typeInfo(@This()).@"struct".decl_names) |decl_name| {
        if (comptime isGlProc(@TypeOf(@field(@This(), decl_name)))) count += 1;
    }
    try std.testing.expect(count > 60);
}

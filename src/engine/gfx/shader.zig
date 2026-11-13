const std = @import("std");
const c = @import("../platform/c.zig").c;
const gl = @import("gl.zig");

const log = std.log.scoped(.gfx);

pub const ShaderProgram = struct {
    program_id: gl.GLuint,
    u_model: gl.GLint,
    u_view: gl.GLint,
    u_projection: gl.GLint,

    pub fn init(vertex_src: [*:0]const u8, fragment_src: [*:0]const u8) !ShaderProgram {
        const vert_shader = try compileShader(c.GL_VERTEX_SHADER, vertex_src);
        defer gl.DeleteShader(vert_shader);

        const frag_shader = try compileShader(c.GL_FRAGMENT_SHADER, fragment_src);
        defer gl.DeleteShader(frag_shader);

        const program = gl.CreateProgram();
        if (program == 0) return error.GlCreateProgramFailed;

        gl.AttachShader(program, vert_shader);
        gl.AttachShader(program, frag_shader);
        gl.LinkProgram(program);

        var link_status: gl.GLint = 0;
        gl.GetProgramiv(program, c.GL_LINK_STATUS, &link_status);
        if (link_status == 0) {
            var info_log: [512]u8 = undefined;
            var len: gl.GLsizei = 0;
            gl.GetProgramInfoLog(program, 512, &len, &info_log);
            log.err("Program link error: {s}", .{info_log[0..@intCast(len)]});
            gl.DeleteProgram(program);
            return error.ProgramLinkFailed;
        }

        const u_model = gl.GetUniformLocation(program, "u_model");
        const u_view = gl.GetUniformLocation(program, "u_view");
        const u_projection = gl.GetUniformLocation(program, "u_projection");

        return .{
            .program_id = program,
            .u_model = u_model,
            .u_view = u_view,
            .u_projection = u_projection,
        };
    }

    pub fn deinit(self: ShaderProgram) void {
        gl.DeleteProgram(self.program_id);
    }

    pub fn use(self: ShaderProgram) void {
        gl.UseProgram(self.program_id);
    }

    pub fn getUniform(self: ShaderProgram, name: [*:0]const u8) gl.GLint {
        return gl.GetUniformLocation(self.program_id, name);
    }

    pub fn setInt(location: gl.GLint, value: i32) void {
        gl.Uniform1i(location, value);
    }

    pub fn setFloat(location: gl.GLint, value: f32) void {
        gl.Uniform1f(location, value);
    }

    pub fn setVec3(location: gl.GLint, v: [3]f32) void {
        gl.Uniform3fv(location, 1, &v);
    }

    pub fn setVec4(location: gl.GLint, v: [4]f32) void {
        gl.Uniform4fv(location, 1, &v);
    }

    pub fn setMat3(location: gl.GLint, mat: [9]f32) void {
        gl.UniformMatrix3fv(location, 1, c.GL_FALSE, &mat);
    }

    pub fn setMat4(location: gl.GLint, mat: [16]f32) void {
        gl.UniformMatrix4fv(location, 1, c.GL_FALSE, &mat);
    }
};

fn compileShader(shader_type: gl.GLenum, src: [*:0]const u8) !gl.GLuint {
    const shader = gl.CreateShader(shader_type);
    if (shader == 0) return error.GlCreateShaderFailed;

    const src_ptr: ?[*]const u8 = src;
    gl.ShaderSource(shader, 1, &src_ptr, null);
    gl.CompileShader(shader);

    var success: gl.GLint = 0;
    gl.GetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
    if (success == 0) {
        var info_log: [512]u8 = undefined;
        var len: gl.GLsizei = 0;
        gl.GetShaderInfoLog(shader, 512, &len, &info_log);
        log.err("Shader compile error: {s}", .{info_log[0..@intCast(len)]});
        gl.DeleteShader(shader);
        return error.ShaderCompileFailed;
    }

    return shader;
}

pub const DEFAULT_VERTEX_SHADER =
    \\#version 300 es
    \\precision mediump float;
    \\
    \\layout(location = 0) in vec3 a_position;
    \\layout(location = 1) in vec3 a_normal;
    \\layout(location = 2) in vec3 a_color;
    \\
    \\uniform mat4 u_model;
    \\uniform mat4 u_view;
    \\uniform mat4 u_projection;
    \\
    \\out vec3 v_normal;
    \\out vec3 v_color;
    \\
    \\void main() {
    \\    vec4 world_pos = u_model * vec4(a_position, 1.0);
    \\    v_normal = mat3(u_model) * a_normal;
    \\    v_color = a_color;
    \\    gl_Position = u_projection * u_view * world_pos;
    \\}
;

pub const DEFAULT_FRAGMENT_SHADER =
    \\#version 300 es
    \\precision mediump float;
    \\
    \\in vec3 v_normal;
    \\in vec3 v_color;
    \\
    \\out vec4 frag_color;
    \\
    \\void main() {
    \\    vec3 norm = normalize(v_normal);
    \\    vec3 light_dir = normalize(vec3(0.4, 0.9, 0.3));
    \\    float ambient = 0.35;
    \\    float diff = max(dot(norm, light_dir), 0.0);
    \\    vec3 final_color = v_color * (ambient + diff * 0.75);
    \\    frag_color = vec4(final_color, 1.0);
    \\}
;

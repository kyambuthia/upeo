const std = @import("std");
const c = @import("c.zig").c;

pub const ShaderProgram = struct {
    program_id: c.GLuint,
    u_model: c.GLint,
    u_view: c.GLint,
    u_projection: c.GLint,

    pub fn init(vertex_src: [*:0]const u8, fragment_src: [*:0]const u8) !ShaderProgram {
        const vert_shader = try compileShader(c.GL_VERTEX_SHADER, vertex_src);
        defer c.glDeleteShader(vert_shader);

        const frag_shader = try compileShader(c.GL_FRAGMENT_SHADER, fragment_src);
        defer c.glDeleteShader(frag_shader);

        const program = c.glCreateProgram();
        if (program == 0) return error.GlCreateProgramFailed;

        c.glAttachShader(program, vert_shader);
        c.glAttachShader(program, frag_shader);
        c.glLinkProgram(program);

        var link_status: c.GLint = 0;
        c.glGetProgramiv(program, c.GL_LINK_STATUS, &link_status);
        if (link_status == 0) {
            var info_log: [512]u8 = undefined;
            var len: c.GLsizei = 0;
            c.glGetProgramInfoLog(program, 512, &len, &info_log);
            std.debug.print("Program link error: {s}\n", .{info_log[0..@intCast(len)]});
            c.glDeleteProgram(program);
            return error.ProgramLinkFailed;
        }

        const u_model = c.glGetUniformLocation(program, "u_model");
        const u_view = c.glGetUniformLocation(program, "u_view");
        const u_projection = c.glGetUniformLocation(program, "u_projection");

        return .{
            .program_id = program,
            .u_model = u_model,
            .u_view = u_view,
            .u_projection = u_projection,
        };
    }

    pub fn deinit(self: ShaderProgram) void {
        c.glDeleteProgram(self.program_id);
    }

    pub fn use(self: ShaderProgram) void {
        c.glUseProgram(self.program_id);
    }
};

fn compileShader(shader_type: c.GLenum, src: [*:0]const u8) !c.GLuint {
    const shader = c.glCreateShader(shader_type);
    if (shader == 0) return error.GlCreateShaderFailed;

    const src_ptr: ?[*]const u8 = src;
    c.glShaderSource(shader, 1, &src_ptr, null);
    c.glCompileShader(shader);

    var success: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
    if (success == 0) {
        var info_log: [512]u8 = undefined;
        var len: c.GLsizei = 0;
        c.glGetShaderInfoLog(shader, 512, &len, &info_log);
        std.debug.print("Shader compile error: {s}\n", .{info_log[0..@intCast(len)]});
        c.glDeleteShader(shader);
        return error.ShaderCompileFailed;
    }

    return shader;
}

pub const VERTEX_SHADER_SOURCE =
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

pub const FRAGMENT_SHADER_SOURCE =
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

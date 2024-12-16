const vrtx_shader_source = 
`
attribute vec2 a_Position;
void main() {
	gl_Position = vec4(0.0, 0.5, 0.0, 1.0);
	gl_PointSize = 10.0;
}
`

const pixl_shader_source = `
void main() {
	gl_FragColor = vec4(1.0, 1.0, 0.0, 1.0);
}
`
function initVRTXShader(gl)
{
        const vrtx_shader = gl.createShader(gl.VERTEX_SHADER);
        gl.shaderSource(vrtx_shader, vrtx_shader_source);
        gl.compileShader(vrtx_shader);
        return vrtx_shader;
}

function initPIXLShader(gl)
{
        const pixl_shader = gl.createShader(gl.FRAGMENT_SHADER);
        gl.shaderSource(pixl_shader, pixl_shader_source);
        gl.compileShader(pixl_shader);
        return pixl_shader;
}

function initProgram(gl, v_shader, p_shader)
{
        const program = gl.createProgram();
        gl.attachShader(program, v_shader);
        gl.attachShader(program, p_shader);
        gl.linkProgram(program);

        if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
                const info = gl.getProgramInfoLog(program);
                throw `Could not compile webGL Program. \n${info}`;
        }

        gl.deleteShader(v_shader);
        gl.deleteShader(p_shader);
        return program;
}

function main()
{
        const canva = document.querySelector("#Canvas_01");
        const gl = canva.getContext('webgl');
        
        function resizeCanvas()
        {
                gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);
                gl.clearColor(0.0, 0.0, 0.0, 1.0);
                gl.clear(gl.COLOR_BUFFER_BIT);
        }
        resizeCanvas(gl);
	window.addEventListener('resize', resizeCanvas(gl), false);
        const pixel_shader = initPIXLShader(gl);
        const vertex_shader = initVRTXShader(gl);
        const program = initProgram(gl, vertex_shader, pixel_shader);

        gl.useProgram(program);
        gl.drawArrays(gl.POINTS, 0, 1);
}

main();

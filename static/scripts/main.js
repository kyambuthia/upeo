function resizeCanvas(c)
{
	c.width = window.innerWidth;
	c.height = window.innerHeight;
}

function initGL(c)
{
	const gl = c.getContext('webgl');
	gl.clearColor(0.0, 0.0, 0.75, 1.0);
	gl.clear(gl.COLOR_BUFFER_BIT);
        return gl;
}

const vrtx_shader_source = 
`
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

console.log(vrtx_shader_source);
// createShaderProgram
function initVRTXShader(gl)
{
        const vrtx_shader = gl.createShader(gl.VERTEX_SHADER);
        gl.shaderSource(vrtx_shader, vrtx_shader_source);
        console.log(gl.compileShader(vrtx_shader));
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
                throw `Could not compile webGL Program. \n\n${info}`;
        }

        gl.deleteShader(v_shader);
        gl.deleteShader(p_shader);
        return program;
}


// attachShaderProgram

function main()
{
	const canva = document.querySelector("#Canvas_01");
	canva.width = window.innerWidth;
	canva.height = window.innerHeight;

	window.addEventListener('resize', resizeCanvas(canva));
	const gl = initGL(canva);

        console.log(gl);

        const pixel_shader = initPIXLShader(gl);
        const vertex_shader = initVRTXShader(gl);
        console.log(pixel_shader);
        console.log(vertex_shader);
        const program = initProgram(gl, vertex_shader, pixel_shader);
        console.log(program);
        gl.useProgram(program);
        gl.drawArrays(gl.POINTS, 0, 1);
}

main();

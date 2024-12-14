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
	console.log(gl);
}

const vrtx_shader = 
`
void main() {
	gl_Position = vec_4(0.0, 0.0, 0.0, 1.0);
	gl_PointSize = 10.0;
}
`

const frag_shader = `
void main() {
	gl_FragColor = vec_4(0.0, 0.0, 1.0, 1.0);
}
`

function main()
{
	const canva = document.querySelector("#Canvas_01");
	canva.width = window.innerWidth;
	canva.height = window.innerHeight;

	window.addEventListener('resize', resizeCanvas(canva));
	initGL(canva);
	console.log(vrtx_shader);
	console.log(frag_shader);
}

main();

# web-ogl (3D Marble)

A lightweight cross-platform 3D game engine and marble sandbox written in **Zig 0.16.0** with **SDL3** and **direct OpenGL ES 3.0 / GLSL ES 3.00**.

## Architecture

- **Windowing & Events**: SDL3 (handles Wayland, X11, desktop resize, and input events).
- **Renderer**: 100% direct raw OpenGL (`<GLES3/gl3.h>`) with Vertex Array Objects (VAOs), Vertex Buffers (VBOs), and directional diffuse/ambient lighting.
- **Math**: Custom column-major matrix and 3D vector library (`src/math.zig`) passing directly to `glUniformMatrix4fv`.
- **Game Physics**: Procedural UV-sphere marble with rolling angular velocity, friction, jumping, boundary bouncing, and ramp slope collision.
- **Camera**: Smooth third-person follow camera tracking the marble.

## Controls

- **W / Up**: Roll Forward
- **S / Down**: Roll Backward
- **A / Left**: Roll Left
- **D / Right**: Roll Right
- **Space**: Jump
- **Esc**: Exit

## How to Run

Enter the Nix development environment and run:

```bash
nix-shell --run "zig build run"
```

Or if you have `zig 0.16.0`, `sdl3`, and `libGL` installed globally:

```bash
zig build run
```

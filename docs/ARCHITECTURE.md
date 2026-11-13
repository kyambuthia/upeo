# Upeo Architecture

Upeo is architected as a lean, direct-to-metal 3D engine designed for instant startup, zero garbage collection pauses, and multi-platform reach.

---

## Architectural Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      Game (src/game/)                       │
│         marble.zig  ·  camera.zig  ·  arena.zig             │
└──────────────┬───────────────────────────────┬──────────────┘
               │                               │
      ┌────────▼─────────┐            ┌────────▼─────────┐
      │   Math Engine    │            │  Mesh Generators │
      │ engine/math/     │            │  engine/gfx/     │
      │   math.zig       │            │    mesh.zig      │
      └────────┬─────────┘            └────────┬─────────┘
               │                               │
┌──────────────▼───────────────────────────────▼──────────────┐
│              Direct OpenGL ES 3.0 (engine/gfx/)             │
│      buffer.zig (VAO / VBO)  ·  shader.zig (GLSL ES 3.00)   │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│     Platform, Input & Timing (engine/platform, input, core) │
│            window.zig · c.h/c.zig · input.zig · time.zig    │
├─────────────────────────────────────────────────────────────┤
│  Linux (Wayland / X11)  │  Windows / macOS*  │  Web (WASM)*  │
└─────────────────────────────────────────────────────────────┘
                         * planned, not yet wired into build.zig
```

`src/main.zig` owns the frame loop and ties every layer together.

---

## Frame Loop (`src/main.zig`)

1. `Input.resetFrame()` then drain `SDL_PollEvent` into `Input.processEvent`.
2. On resize, `Window.updateSize()` re-queries pixel dimensions and resets `glViewport`.
3. `Clock.tick()` returns a variable `dt` (clamped to 50 ms).
4. `Marble.update(input, dt)` → `Camera.update(marble.pos, dt)`.
5. Clear, bind the shader, upload projection/view, draw the arena (identity model) and the marble (its model matrix), then `Window.swap()`.

All geometry is generated once at startup (via `std.heap.c_allocator`); nothing is allocated inside the loop.

---

## Module Breakdown

### 1. Platform (`src/engine/platform/`)
- **`c.h` / `c.zig`**: C headers (`SDL3/SDL.h`, `GLES3/gl3.h`) translated by `build.zig`'s `addTranslateC` step and exposed as the `c` module.
- **`window.zig`**: Initializes SDL video, requests an OpenGL ES 3.0 context (24-bit depth, double buffered), configures vsync, and tracks High-DPI pixel size / aspect ratio.

### 2. Input (`src/engine/input/input.zig`)
- Maps SDL keyboard scancodes to boolean actions (`up`, `down`, `left`, `right`, `jump`) and tracks `quit_requested` / `resized` flags.

### 3. Timing (`src/engine/core/time.zig`)
- `Clock` computes delta time from `SDL_GetTicks()`, clamped to 50 ms to avoid a spiral of death. `fixed_delta` (1/60 s) is defined for a future fixed-timestep loop.

### 4. Graphics (`src/engine/gfx/`)
- **`shader.zig`**: Compiles/links GLSL ES 3.00 (`#version 300 es`) programs, caches `u_model` / `u_view` / `u_projection` uniform locations, and embeds the default shaders (directional sun light + ambient fill).
- **`buffer.zig`**: `MeshBuffer` uploads `[]Vertex` into a VAO/VBO (attributes: 0 = position, 1 = normal, 2 = color) and draws with `glDrawArrays(GL_TRIANGLES)`.
- **`mesh.zig`**: `Vertex` layout (`extern struct`), UV-sphere generator with striped coloring, and `putQuad` helper. All faces use CCW winding for back-face culling.

### 5. Math (`src/engine/math/math.zig`)
- Pure Zig `Vec3` and column-major `Mat4` (`[16]f32`) passed directly to `glUniformMatrix4fv` with no transposition. Provides translation, scaling, rotations, `perspective`, and `lookAt`.

### 6. Game (`src/game/`)
- **`arena.zig`**: 24×24 floor, boundary walls, and a ramp. Exposes `getSurfaceHeight`, `isOnRamp`, `resolveCollision` (ground snap + wall bounce, restitution 0.65), and `generateArenaMesh`.
- **`marble.zig`**: Sphere kinematics — input acceleration, jump, gravity, slope pull on the ramp, horizontal speed cap, ground friction, Euler integration, and rolling spin for visuals.
- **`camera.zig`**: Third-person camera that lerps toward an offset behind/above the marble and looks at it.

---

## Build & Test

- `build.zig` resolves C headers from `~/.local/include` and from `NIX_CFLAGS_COMPILE` (Nix shells), links `SDL3` and `GLESv2`, and supports both Zig 0.16 and 0.17 build APIs.
- `zig build test` runs `src/tests.zig`, which pulls in the unit tests in `math.zig`, `arena.zig`, and `marble.zig`.
- CI (`.github/workflows/ci.yml`) runs `zig fmt --check`, build, and tests inside `nix-shell`.

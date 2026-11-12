# Upeo Architecture

Upeo is architected as a lean, direct-to-metal 3D engine designed for instant startup, zero garbage collection pauses, and multi-platform reach.

---

## Architectural Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         Game Logic                          │
│               (Marble Physics, Camera, World)               │
└──────────────┬───────────────────────────────┬──────────────┘
               │                               │
      ┌────────▼────────┐             ┌────────▼────────┐
      │  3D Math Engine │             │ Mesh Generators │
      │   (src/math.zig)│             │   (src/mesh.zig)│
      └────────┬────────┘             └────────┬────────┘
               │                               │
┌──────────────▼───────────────────────────────▼──────────────┐
│                    Direct OpenGL ES 3.0                     │
│      (VAO / VBO, Instancing, GLSL ES 3.00 Shader Program)   │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                 Platform & Windowing Layer                  │
│                      (SDL3 C-Binding)                       │
├─────────────────────────────────────────────────────────────┤
│   Linux (Wayland / X11)  │  Web (WASM/WebGL2)  │  Windows   │
└─────────────────────────────────────────────────────────────┘
```

---

## Module Breakdown

### 1. Platform Host (`src/c.zig`, `src/main.zig`)
- **Role**: Initializes the display surface, acquires the hardware OpenGL ES 3.0 context, polls input devices, and swaps backbuffers.
- **Dependency**: SDL3 (`libSDL3`). Provides unified support across Wayland, X11, Win32, and Emscripten HTML5 canvases.

### 2. Graphics Pipeline (`src/shader.zig`, `src/main.zig`)
- **Role**: Direct rendering via OpenGL ES 3.0 headers (`<GLES3/gl3.h>`).
- **Shaders**: Written in GLSL ES 3.00 (`#version 300 es`) for 1:1 parity between native mobile/desktop GPU drivers and browser WebGL 2.0.
- **Lighting**: Directional sun light with ambient fill and diffuse normal calculation in hardware.

### 3. Math Engine (`src/math.zig`)
- **Role**: Pure Zig 3D vectors (`Vec3`) and column-major transformation matrices (`Mat4`).
- **Memory**: Mat4 matrices are laid out in standard column-major float arrays (`[16]f32`) so they pass directly to `glUniformMatrix4fv` with zero copy or transposition overhead.

### 4. Game Physics & Entities (`src/game.zig`, `src/mesh.zig`)
- **Role**: Simulates rigid sphere kinematics (velocity, acceleration, drag, gravity, surface slope reactions, and boundary bounces).
- **Camera**: 3rd-person spring/lerp camera keeping the player centered while following velocity vectors.

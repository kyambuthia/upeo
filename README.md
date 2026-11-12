# Upeo

**Upeo** (*Swahili for "The Horizon / Limitless Scope"*) is a lightweight, universal 3D game engine and physics sandbox targeting **OpenGL ES 3.0 / GLSL ES 3.00**, built in **Zig** with **SDL3**.

Designed to run natively across all platforms—from desktop Linux/macOS/Windows to low-power mobile devices and WebAssembly in browsers—with zero scene graph bloat and predictable frame times.

---

## Architecture & Principles

- **Direct Metal**: 100% direct OpenGL ES 3.0 calls (`<GLES3/gl3.h>`). No abstraction layers between game logic and GPU vertex/uniform buffers.
- **Cross-Platform Host**: SDL3 handles window creation, event pump, timing, and Wayland/X11 surface management.
- **Predictable Memory**: Zero hidden dynamic memory allocations during the frame loop. Deterministic geometry generation.
- **Single Shader Pipeline**: GLSL ES 3.00 shaders (`#version 300 es`) that compile identically on native GPU drivers and browser WebGL 2.0.

---

## Project Structure

```
upeo/
├── build.zig          # Zig build definitions
├── build.zig.zon      # Package metadata
├── shell.nix          # Nix environment definition
├── src/
│   ├── c.zig          # SDL3 & GLES3 C-header imports
│   ├── game.zig       # Marble physics, collisions, camera controller
│   ├── main.zig       # Entrypoint & rendering loop
│   ├── math.zig       # 3D Vector & column-major Mat4 transforms
│   ├── mesh.zig       # Procedural UV Sphere & arena geometry
│   └── shader.zig     # GLSL ES 3.00 shader compilation & error handling
└── README.md
```

---

## Quickstart

### Prerequisites
- **Zig 0.16.0+**
- **SDL3** (`libSDL3`)
- **OpenGL ES 3 / libGLESv2**

### Running with Nix (Recommended)
```bash
nix-shell --run "zig build run"
```

### Running Native
```bash
zig build run
```

---

## Controls
- **W / Up**: Roll Forward
- **S / Down**: Roll Backward
- **A / Left**: Roll Left
- **D / Right**: Roll Right
- **Space**: Jump
- **Esc**: Exit

# Upeo

**Upeo** (*Swahili for "The Horizon / Limitless Scope"*) is a lightweight, universal 3D game engine and physics sandbox targeting **OpenGL ES 3.0 / GLSL ES 3.00**, built in **Zig** with **SDL3**.

Designed to run natively across all platforms—from desktop Linux/macOS/Windows to low-power mobile devices and WebAssembly in browsers—with zero scene graph bloat and predictable frame times.

> **Status:** Desktop Linux (Wayland/X11) is the currently supported target. Windows, macOS, mobile, and WebAssembly builds are planned.

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
├── build.zig          # Zig build definitions & TranslateC pipeline
├── build.zig.zon      # Package metadata
├── shell.nix          # Nix environment definition
├── src/
│   ├── main.zig       # Entrypoint & rendering loop
│   ├── tests.zig      # Unified test runner
│   ├── engine/
│   │   ├── core/      # Delta clock & timing (time.zig)
│   │   ├── gfx/       # OpenGL ES 3.0 VAO/VBO, shaders, mesh generation
│   │   ├── input/     # Event polling and input mapping (input.zig)
│   │   ├── math/      # Pure Zig Vec3 & column-major Mat4 transforms
│   │   └── platform/  # SDL3 windowing & C header bindings
│   └── game/
│       ├── arena.zig  # Procedural geometry & collision resolution
│       ├── camera.zig # 3rd-person spring follow camera
│       └── marble.zig # Rolling physics, slope gravity & angular spin
├── docs/
│   └── ARCHITECTURE.md # Module breakdown & frame loop
├── CONTRIBUTING.md
└── README.md
```

---

## Quickstart

### Prerequisites
- **Zig 0.16.0+ / 0.17.0+**
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

### Running Unit Tests
```bash
zig build test
```

---

## Controls
- **W / Up**: Roll Forward
- **S / Down**: Roll Backward
- **A / Left**: Roll Left
- **D / Right**: Roll Right
- **Space**: Jump
- **Esc**: Exit

# Upeo

**Upeo** (*Swahili for "The Horizon / Limitless Scope"*) is a lightweight, direct-to-metal 3D game engine in **Zig** targeting **OpenGL ES 3.0 / WebGL 2.0** (GLSL ES 3.00) and **SDL3**.

Designed for predictable frame times, multi-core job parallelism, and low-latency UDP networking across native desktop and browser WebAssembly targets—with zero scene graph bloat.

> **Status:** Desktop Linux (Wayland/X11) and WebAssembly (`wasm32-emscripten` + WebGL 2.0) are currently supported. Windows, macOS, and mobile targets are planned.

---

## Architecture & Principles

- **Direct Metal**: Direct OpenGL ES 3.0 calls (`<GLES3/gl3.h>`) loaded at runtime via `SDL_GL_GetProcAddress`—avoiding a hard `libGLESv2` link dependency and keeping native and WebGL 2.0 shader pipelines identical (`#version 300 es`).
- **Unified Callback Loop**: Uses `SDL_EnterAppMainCallbacks` (`init`, `fixedUpdate`, `update`, `render`, `deinit`) so native desktop and Emscripten/WebGL 2.0 share the same non-blocking application lifecycle.
- **Predictable Memory & Parallelism**: Frame arenas, O(1) object pools, `GuardAllocator`, generational `SlotMap`s, sparse-set ECS, and a lock-free Chase–Lev work-stealing job system.
- **Low-Latency Networking**: Bit-level serialization, RFC 1982 sequence wraparound, RFC 6298 RTT/RTO reliability, reliable-ordered channels, challenge/response handshakes, non-blocking UDP/simulated transport, and snapshot interpolation/prediction.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a detailed module breakdown.

---

## Project Structure

```
upeo/
├── build.zig                # Zig build definitions (native, tests, wasm)
├── build.zig.zon            # Package metadata (minimum Zig 0.16.0)
├── shell.nix                # Nix environment definition
├── src/
│   ├── upeo.zig             # Engine root module (`@import("upeo")`)
│   └── engine/
│       ├── app.zig          # SDL3 callback lifecycle & fixed-timestep loop
│       ├── core/            # Clock, FrameArena/Pool, Handle/SlotMap, Jobs
│       ├── ecs/             # Generational EntityRegistry, sparse-set ComponentPool, join2
│       ├── gfx/             # Runtime GLES3 loader, MeshBuffer, ShaderProgram, Texture2D, Camera, mesh
│       ├── input/           # SDL3 event polling & keyboard/mouse state
│       ├── math/            # Vec2, Vec3, Vec4, Quat, column-major Mat4
│       ├── net/             # BitPacker, reliability, channels, connections, UDP/sim transport, snapshots
│       └── platform/        # SDL3 + GLES3 C header translation & Window management
├── examples/
│   └── marble/              # 3D rolling-marble demo
│       ├── main.zig         # Demo entrypoint & render loop
│       ├── arena.zig        # Procedural arena geometry & collision resolution
│       ├── camera.zig       # 3rd-person spring follow camera
│       └── marble.zig       # Rolling physics, slope gravity & angular spin
├── docs/
│   └── ARCHITECTURE.md      # Architecture diagram & module breakdown
├── CONTRIBUTING.md
└── README.md
```

---

## Quickstart

### Prerequisites (All Platforms)
- **Zig 0.16.0+** (verified on `0.17.0`)
- **SDL3** development headers and library (`SDL3`)
- **OpenGL ES 3.0** headers (`<GLES3/gl3.h>`) and drivers (e.g., Mesa on Linux, ANGLE on Windows/macOS; entry points are loaded at runtime via SDL3)
- *(Optional, for WebAssembly)* **Emscripten SDK**

### Build, Run & Test
```bash
# Build and run the marble demo
zig build run

# Run engine and example unit tests
zig build test
```

### Platform Notes
- **Linux**: Install `sdl3` and OpenGL ES 3.0 development headers from your package manager (or into `~/.local/include` and `~/.local/lib`), then run `zig build run`. If you use Nix, [shell.nix](shell.nix) provides the full environment:
  ```bash
  nix-shell --run "zig build run"
  ```
- **Windows** *(native support planned)*: Recommended via **WSL2** (using the Linux instructions above) or **WebAssembly**. Native Windows builds are not yet wired into [build.zig](build.zig) and require manual SDL3 + ANGLE/GLES3 setup.
- **macOS** *(planned)*: Requires `zig`, `sdl3` (e.g., via Homebrew), and OpenGL ES 3.0 / ANGLE headers.
- **WebAssembly (All OSes)**: With the Emscripten SDK installed (set `EMCC` and `EMSDK_SYSROOT` if not under `/usr/local/emsdk`), build the WebGL 2.0 bundle:
  ```bash
  zig build wasm
  ```
  Outputs `zig-out/web/index.html`, `index.js`, and `index.wasm`.

---

## Controls (Marble Demo)
- **W / Up**: Roll Forward
- **S / Down**: Roll Backward
- **A / Left**: Roll Left
- **D / Right**: Roll Right
- **Space**: Jump
- **Esc**: Exit

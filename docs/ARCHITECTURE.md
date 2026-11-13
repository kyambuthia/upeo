# Upeo Architecture

Upeo is a lightweight, direct-to-metal 3D engine in Zig targeting OpenGL ES 3.0 / WebGL 2.0, built for predictable frame times, multi-core job parallelism, and low-latency UDP networking.

---

## Architectural Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                       Examples / Games (examples/)                   │
│                          @import("upeo")                             │
└──────────────────────────────────┬───────────────────────────────────┘
                                   │
┌──────────────────────────────────▼───────────────────────────────────┐
│                      Upeo Engine (src/upeo.zig)                      │
├───────────────┬──────────────────┬──────────────────┬────────────────┤
│  App & Input  │ Performance Core │   ECS & Math     │   Networking   │
│  app.zig      │  core/memory.zig │  ecs/ecs.zig     │ net/           │
│  input.zig    │  core/handle.zig │  math/math.zig   │  serialize.zig │
│  window.zig   │  core/jobs.zig   │                  │  sequence.zig  │
│               │  core/time.zig   │                  │  reliability   │
├───────────────┴──────────────────┴──────────────────┴────────────────┤
│                      Graphics (src/engine/gfx/)                      │
│   gl.zig (runtime proc loader) · buffer.zig · shader.zig · texture   │
├──────────────────────────────────────────────────────────────────────┤
│       Platform & Toolchains: Linux (Wayland/X11) · WASM (WebGL2)     │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Module Breakdown

### 1. Application Lifecycle (`src/engine/app.zig`)
- Drives `Game` (`init`, `fixedUpdate`, `update`, `render`, `deinit`) via `SDL_EnterAppMainCallbacks` (`SDL_AppInit` / `SDL_AppIterate` / `SDL_AppEvent` / `SDL_AppQuit`) so native desktop and Emscripten/WebGL 2.0 share one non-blocking loop.
- Uses `DebugAllocator` in Debug builds for leak detection on shutdown and `c_allocator` in release builds.

### 2. Platform & Graphics (`src/engine/platform/`, `src/engine/gfx/`)
- **`gl.zig`**: Loads OpenGL ES 3.0 entry points at runtime through `SDL_GL_GetProcAddress`, avoiding a hard `libGLESv2` link dependency.
- **`buffer.zig`**: Comptime `VertexLayout` attribute binding for any `extern struct`, static/dynamic VBOs, index buffers (EBO), `glBufferSubData`, and instanced draws.
- **`shader.zig` / `texture.zig` / `camera.zig` / `mesh.zig`**: GLSL ES 3.00 shaders, generic uniform setters, `Texture2D`, perspective `Camera`, and procedural geometry.

### 3. Performance Core (`src/engine/core/`)
- **`time.zig`**: Nanosecond `Clock` (`SDL_GetTicksNS`) with fixed-timestep accumulator (60 Hz default, 50 ms lag clamp) and render interpolation `alpha()`.
- **`memory.zig`**: `FrameArena`, `DoubleFrameArena`, O(1) free-list `Pool(T)`, and `GuardAllocator` to catch heap allocations inside the frame loop.
- **`handle.zig`**: Type-safe generational `Handle(Tag)` and dense-array `SlotMap(T, Tag)`.
- **`jobs.zig`**: Lock-free Chase–Lev `WorkStealingDeque` (PPoPP 2013 memory orderings), cache-line-sized `Job`s, random-victim stealing, cooperative `wait()`, `parallelFor`, and single-threaded fallback.

### 4. ECS & Math (`src/engine/ecs/`, `src/engine/math/`)
- **`ecs.zig`**: Generational `EntityRegistry`, sparse-set `ComponentPool(T)` with contiguous iteration, and `join2`.
- **`math.zig`**: `Vec2`, `Vec3`, `Vec4`, `Quat` (axis-angle, SLERP, `toMat4`), and column-major `Mat4` (`perspective`, `lookAt`, `transpose`, `inverse`).

### 5. Networking (`src/engine/net/`)
- **`serialize.zig`**: 64-bit scratch `BitWriter`/`BitReader` with bounded-range ints and quantized floats.
- **`sequence.zig` / `reliability.zig`**: RFC 1982 sequence wraparound math, `SequenceBuffer`, 32-bit redundant ack bitfields, and RFC 6298 Jacobson/Karels RTT/RTO estimation.
- **`channel.zig` / `connection.zig`**: Reliable-ordered message channel and client/server state machine with padded anti-amplification challenge/response handshake.
- **`transport.zig` / `snapshot.zig`**: Non-blocking POSIX `UdpSocket`, deterministic `SimulatedNetwork` (loss/jitter/duplication), `SnapshotBuffer` interpolation, and `PredictionBuffer` reconciliation.

---

## Build & Test

- `zig build` — builds `upeo-marble` (native).
- `zig build wasm` — builds the `wasm32-emscripten` + WebGL 2.0 bundle in `zig-out/web/index.html`.
- `zig build test` — runs engine and example unit tests (`engine-tests` + `marble-tests`).

# Contributing to Upeo

Thank you for your interest in contributing to **Upeo**! We welcome bug reports, documentation improvements, optimizations, and new features.

---

## Philosophy & Guidelines

Upeo is designed around a few core technical principles:

1. **Direct Metal & Simplicity**:
   - We avoid heavy third-party abstractions. Rendering is written using direct OpenGL ES 3.0 / GLSL ES 3.00 (`<GLES3/gl3.h>`).
   - Keep the codebase transparent and readable.

2. **Deterministic & Predictable Memory**:
   - The per-frame update loop should **never allocate dynamic heap memory** (`malloc` or arbitrary `allocator.alloc`).
   - Frame-scoped memory should use arena allocators or static pre-allocated slices.

3. **Universal Portability**:
   - Code must cross-compile cleanly to Desktop (Linux/Windows/macOS), Mobile (Android), and Web (WebAssembly/WebGL 2.0 via Emscripten).
   - Shaders must adhere strictly to `#version 300 es` standards.

---

## Development Workflow

### 1. Formatting
Always format your code before committing:
```bash
zig fmt src/ build.zig
```
CI verifies that all code conforms to `zig fmt --check`.

### 2. Building & Testing
Compile and run the project locally:
```bash
# With Nix
nix-shell --run "zig build run"

# Or natively
zig build run
```

### 3. Submitting Changes
1. Fork the repository and create a feature branch (`git checkout -b feat/my-feature`).
2. Make your changes adhering to the principles above.
3. Ensure the project builds cleanly and matches formatting.
4. Open a Pull Request targeting the `trunk` branch with a clear description of your changes.

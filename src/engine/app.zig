//! Cross-platform application lifecycle driven by SDL3 main callbacks.
//!
//! Uses `SDL_EnterAppMainCallbacks` (`SDL_AppInit` / `SDL_AppIterate` /
//! `SDL_AppEvent` / `SDL_AppQuit`) so the exact same game code runs on desktop
//! native event loops, mobile, and Emscripten/WebGL without blocking `while`
//! loops or platform `#ifdef`s.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("platform/c.zig").c;
const Window = @import("platform/window.zig").Window;
const WindowConfig = @import("platform/window.zig").WindowConfig;
const Input = @import("input/input.zig").Input;
const Clock = @import("core/time.zig").Clock;

const log = std.log.scoped(.app);

pub const AppConfig = struct {
    window: WindowConfig = .{},
    fixed_dt: f32 = 1.0 / 60.0,
    max_frame_dt: f32 = 0.05,
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    window: Window,
    input: Input = .{},
    clock: Clock,
    should_quit: bool = false,

    pub fn quit(self: *Engine) void {
        self.should_quit = true;
    }
};

/// Runs `Game` using SDL3's callback main loop.
///
/// `Game` must define `pub fn init(engine: *Engine) !Game` and may define any
/// subset of:
/// - `pub fn fixedUpdate(self: *Game, engine: *Engine, dt: f32) void`
/// - `pub fn update(self: *Game, engine: *Engine, dt: f32) void`
/// - `pub fn render(self: *Game, engine: *Engine, alpha: f32) void`
/// - `pub fn deinit(self: *Game, engine: *Engine) void`
pub fn run(comptime Game: type, config: AppConfig) !void {
    const use_debug_alloc = builtin.mode == .debug and !builtin.target.cpu.arch.isWasm();
    var debug_alloc = if (use_debug_alloc) std.heap.DebugAllocator(.{}).init else {};
    defer if (use_debug_alloc) {
        if (debug_alloc.deinit() == .leak) {
            log.err("memory leak detected on shutdown", .{});
        }
    };

    const allocator = if (use_debug_alloc) debug_alloc.allocator() else std.heap.c_allocator;

    var ctx = Context(Game){
        .allocator = allocator,
        .config = config,
    };

    // Pass Context pointer via a global hook because SDL_EnterAppMainCallbacks
    // only passes (argc, argv) to AppInit.
    Context(Game).pending = &ctx;
    const rc = c.SDL_EnterAppMainCallbacks(
        0,
        null,
        &Context(Game).appInit,
        &Context(Game).appIterate,
        &Context(Game).appEvent,
        &Context(Game).appQuit,
    );
    if (rc != 0) return error.AppFailed;
}

fn Context(comptime Game: type) type {
    return struct {
        const Self = @This();

        var pending: ?*Self = null;

        allocator: std.mem.Allocator,
        config: AppConfig,
        engine: Engine = undefined,
        game: Game = undefined,
        initialized: bool = false,

        fn appInit(appstate: [*c]?*anyopaque, _: c_int, _: [*c][*c]u8) callconv(.c) c.SDL_AppResult {
            const self = pending orelse return c.SDL_APP_FAILURE;
            pending = null;
            appstate.* = self;

            const window = Window.init(self.config.window) catch |err| {
                log.err("window init failed: {}", .{err});
                return c.SDL_APP_FAILURE;
            };

            var clock = Clock.init();
            clock.fixed_dt = self.config.fixed_dt;
            clock.max_frame_dt = self.config.max_frame_dt;

            self.engine = .{
                .allocator = self.allocator,
                .window = window,
                .clock = clock,
            };

            self.game = Game.init(&self.engine) catch |err| {
                log.err("game init failed: {}", .{err});
                self.engine.window.deinit();
                return c.SDL_APP_FAILURE;
            };
            self.initialized = true;
            return c.SDL_APP_CONTINUE;
        }

        fn appEvent(appstate: ?*anyopaque, event: [*c]c.SDL_Event) callconv(.c) c.SDL_AppResult {
            const self: *Self = @ptrCast(@alignCast(appstate orelse return c.SDL_APP_FAILURE));
            self.engine.input.processEvent(event.*);
            if (self.engine.input.quit_requested or self.engine.should_quit) {
                return c.SDL_APP_SUCCESS;
            }
            return c.SDL_APP_CONTINUE;
        }

        fn appIterate(appstate: ?*anyopaque) callconv(.c) c.SDL_AppResult {
            const self: *Self = @ptrCast(@alignCast(appstate orelse return c.SDL_APP_FAILURE));

            if (self.engine.input.resized) {
                self.engine.window.updateSize();
            }

            const dt = self.engine.clock.tick();

            if (comptime @hasDecl(Game, "fixedUpdate")) {
                while (self.engine.clock.consumeFixedStep()) {
                    self.game.fixedUpdate(&self.engine, self.engine.clock.fixed_dt);
                }
            }

            if (comptime @hasDecl(Game, "update")) {
                self.game.update(&self.engine, dt);
            }

            if (self.engine.input.quit_requested or self.engine.should_quit) {
                return c.SDL_APP_SUCCESS;
            }

            if (comptime @hasDecl(Game, "render")) {
                self.game.render(&self.engine, self.engine.clock.alpha());
            }

            self.engine.window.swap();
            self.engine.input.beginFrame();
            return c.SDL_APP_CONTINUE;
        }

        fn appQuit(appstate: ?*anyopaque, _: c.SDL_AppResult) callconv(.c) void {
            const self: *Self = @ptrCast(@alignCast(appstate orelse return));
            if (self.initialized) {
                if (comptime @hasDecl(Game, "deinit")) {
                    self.game.deinit(&self.engine);
                }
                self.engine.window.deinit();
                self.initialized = false;
            }
        }
    };
}

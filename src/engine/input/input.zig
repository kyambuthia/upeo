//! Generic per-frame keyboard and mouse state with edge detection.
//!
//! Tracks current and previous frame bitsets so games can query held state
//! (`isKeyDown`), rising edges (`wasKeyPressed`), and falling edges
//! (`wasKeyReleased`) without coupling the engine to game-specific actions.

const std = @import("std");
const c = @import("../platform/c.zig").c;

pub const Scancode = c.SDL_Scancode;
pub const MAX_SCANCODES: usize = 512;

pub const MouseButton = enum(u5) {
    left = 1,
    middle = 2,
    right = 3,
    x1 = 4,
    x2 = 5,
};

pub const Key = struct {
    pub const w: Scancode = c.SDL_SCANCODE_W;
    pub const a: Scancode = c.SDL_SCANCODE_A;
    pub const s: Scancode = c.SDL_SCANCODE_S;
    pub const d: Scancode = c.SDL_SCANCODE_D;
    pub const up: Scancode = c.SDL_SCANCODE_UP;
    pub const down: Scancode = c.SDL_SCANCODE_DOWN;
    pub const left: Scancode = c.SDL_SCANCODE_LEFT;
    pub const right: Scancode = c.SDL_SCANCODE_RIGHT;
    pub const space: Scancode = c.SDL_SCANCODE_SPACE;
    pub const escape: Scancode = c.SDL_SCANCODE_ESCAPE;
    pub const lshift: Scancode = c.SDL_SCANCODE_LSHIFT;
    pub const rshift: Scancode = c.SDL_SCANCODE_RSHIFT;
};

const KeyBitSet = std.bit_set.ArrayBitSet(u64, MAX_SCANCODES);

pub const Input = struct {
    curr_keys: KeyBitSet = KeyBitSet.empty,
    prev_keys: KeyBitSet = KeyBitSet.empty,

    curr_buttons: u32 = 0,
    prev_buttons: u32 = 0,
    mouse_x: f32 = 0.0,
    mouse_y: f32 = 0.0,
    mouse_dx: f32 = 0.0,
    mouse_dy: f32 = 0.0,
    wheel_y: f32 = 0.0,

    quit_requested: bool = false,
    resized: bool = false,

    /// Call once at the start of each frame before polling SDL events.
    pub fn beginFrame(self: *Input) void {
        self.prev_keys = self.curr_keys;
        self.prev_buttons = self.curr_buttons;
        self.mouse_dx = 0.0;
        self.mouse_dy = 0.0;
        self.wheel_y = 0.0;
        self.resized = false;
    }

    pub fn processEvent(self: *Input, event: c.SDL_Event) void {
        switch (event.type) {
            c.SDL_EVENT_QUIT => self.quit_requested = true,
            c.SDL_EVENT_WINDOW_RESIZED, c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => self.resized = true,
            c.SDL_EVENT_KEY_DOWN => {
                if (!event.key.repeat) self.setKey(event.key.scancode, true);
            },
            c.SDL_EVENT_KEY_UP => self.setKey(event.key.scancode, false),
            c.SDL_EVENT_MOUSE_MOTION => {
                self.mouse_x = event.motion.x;
                self.mouse_y = event.motion.y;
                self.mouse_dx += event.motion.xrel;
                self.mouse_dy += event.motion.yrel;
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                self.curr_buttons |= buttonMask(event.button.button);
            },
            c.SDL_EVENT_MOUSE_BUTTON_UP => {
                self.curr_buttons &= ~buttonMask(event.button.button);
            },
            c.SDL_EVENT_MOUSE_WHEEL => {
                self.wheel_y += event.wheel.y;
            },
            else => {},
        }
    }

    pub fn setKey(self: *Input, scancode: Scancode, down: bool) void {
        const idx: usize = @intCast(scancode);
        if (idx >= MAX_SCANCODES) return;
        self.curr_keys.setValue(idx, down);
    }

    pub fn isKeyDown(self: Input, scancode: Scancode) bool {
        const idx: usize = @intCast(scancode);
        if (idx >= MAX_SCANCODES) return false;
        return self.curr_keys.isSet(idx);
    }

    pub fn wasKeyPressed(self: Input, scancode: Scancode) bool {
        const idx: usize = @intCast(scancode);
        if (idx >= MAX_SCANCODES) return false;
        return self.curr_keys.isSet(idx) and !self.prev_keys.isSet(idx);
    }

    pub fn wasKeyReleased(self: Input, scancode: Scancode) bool {
        const idx: usize = @intCast(scancode);
        if (idx >= MAX_SCANCODES) return false;
        return !self.curr_keys.isSet(idx) and self.prev_keys.isSet(idx);
    }

    pub fn isMouseDown(self: Input, btn: MouseButton) bool {
        return (self.curr_buttons & buttonMask(@backingInt(btn))) != 0;
    }

    pub fn wasMousePressed(self: Input, btn: MouseButton) bool {
        const m = buttonMask(@backingInt(btn));
        return (self.curr_buttons & m) != 0 and (self.prev_buttons & m) == 0;
    }

    pub fn wasMouseReleased(self: Input, btn: MouseButton) bool {
        const m = buttonMask(@backingInt(btn));
        return (self.curr_buttons & m) == 0 and (self.prev_buttons & m) != 0;
    }

    fn buttonMask(button: u8) u32 {
        if (button == 0 or button >= 32) return 0;
        return @as(u32, 1) << @intCast(button - 1);
    }
};

test "keyboard held, pressed, and released edges" {
    var input = Input{};
    input.beginFrame();
    input.setKey(Key.space, true);

    try std.testing.expect(input.isKeyDown(Key.space));
    try std.testing.expect(input.wasKeyPressed(Key.space));
    try std.testing.expect(!input.wasKeyReleased(Key.space));

    // Next frame: still held, no longer newly pressed
    input.beginFrame();
    try std.testing.expect(input.isKeyDown(Key.space));
    try std.testing.expect(!input.wasKeyPressed(Key.space));

    // Release
    input.beginFrame();
    input.setKey(Key.space, false);
    try std.testing.expect(!input.isKeyDown(Key.space));
    try std.testing.expect(input.wasKeyReleased(Key.space));
}

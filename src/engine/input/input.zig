const std = @import("std");
const c = @import("../platform/c.zig").c;

pub const Input = struct {
    // Current frame state
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
    jump: bool = false,
    quit_requested: bool = false,
    resized: bool = false,

    pub fn resetFrame(self: *Input) void {
        self.resized = false;
    }

    pub fn processEvent(self: *Input, event: c.SDL_Event) void {
        switch (event.type) {
            c.SDL_EVENT_QUIT => {
                self.quit_requested = true;
            },
            c.SDL_EVENT_WINDOW_RESIZED, c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => {
                self.resized = true;
            },
            c.SDL_EVENT_KEY_DOWN => {
                const sc = event.key.scancode;
                self.setKey(sc, true);
            },
            c.SDL_EVENT_KEY_UP => {
                const sc = event.key.scancode;
                self.setKey(sc, false);
            },
            else => {},
        }
    }

    fn setKey(self: *Input, scancode: c.SDL_Scancode, state: bool) void {
        switch (scancode) {
            c.SDL_SCANCODE_W, c.SDL_SCANCODE_UP => self.up = state,
            c.SDL_SCANCODE_S, c.SDL_SCANCODE_DOWN => self.down = state,
            c.SDL_SCANCODE_A, c.SDL_SCANCODE_LEFT => self.left = state,
            c.SDL_SCANCODE_D, c.SDL_SCANCODE_RIGHT => self.right = state,
            c.SDL_SCANCODE_SPACE => self.jump = state,
            c.SDL_SCANCODE_ESCAPE => {
                if (state) self.quit_requested = true;
            },
            else => {},
        }
    }
};

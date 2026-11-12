pub const c = @cImport({
    @cInclude("SDL3/SDL_init.h");
    @cInclude("SDL3/SDL_video.h");
    @cInclude("SDL3/SDL_events.h");
    @cInclude("SDL3/SDL_timer.h");
    @cInclude("SDL3/SDL_scancode.h");
    @cInclude("SDL3/SDL_keycode.h");
    @cInclude("GLES3/gl3.h");
});

// C headers translated into the `c` module by build.zig.
//
// GL entry points are NOT linked directly: prototypes are disabled and
// gfx/gl.zig loads them at runtime through SDL_GL_GetProcAddress. This keeps
// the binary free of a hard libGLESv2 dependency so the same code runs on
// native GLES drivers, desktop GL drivers exposing ES contexts, ANGLE
// (Windows/macOS) and WebGL 2 (Emscripten).
#define SDL_MAIN_HANDLED 1
#define GL_GLES_PROTOTYPES 0

#include <SDL3/SDL_init.h>
#include <SDL3/SDL_main.h>
#include <SDL3/SDL_video.h>
#include <SDL3/SDL_events.h>
#include <SDL3/SDL_timer.h>
#include <SDL3/SDL_scancode.h>
#include <SDL3/SDL_keycode.h>
#include <SDL3/SDL_mouse.h>
#include <SDL3/SDL_log.h>
#include <GLES3/gl3.h>

//
//  screen-porting.c
//  scrcpy-module
//
//  Created by Ethan on 2022/6/3.
//

#include "stdbool.h"

#define sc_screen_init(...)   sc_screen_init_orig(__VA_ARGS__)
#define sc_screen_handle_event(...)    sc_screen_handle_event_hijack(__VA_ARGS__)
#define SDL_CreateWindow(...)    SDL_CreateWindow_hijack(__VA_ARGS__)

#include "screen.c"

#undef sc_screen_init
#undef sc_screen_handle_event
#undef SDL_CreateWindow

struct sc_screen *
sc_screen_current_screen(struct sc_screen *screen) {
    static struct sc_screen *current_screen;
    if (screen != NULL) {
        current_screen = screen;
    }
    return current_screen;
}

__attribute__((weak))
float ScrcpyRenderScreenScale(void) {
    return 2.f;
}

bool
sc_screen_init(struct sc_screen *screen,
               const struct sc_screen_params *params) {
    bool ret = sc_screen_init_orig(screen, params);

    // Set renderer scale
    SDL_RenderSetScale(screen->display.renderer, ScrcpyRenderScreenScale(), ScrcpyRenderScreenScale());
    
    // Save current screen pointer
    sc_screen_current_screen(screen);

    return ret;
}

bool
sc_screen_handle_event(struct sc_screen *screen, SDL_Event *event) {
    // Handle Clipboard Event to Sync Clipboard to Remote
    if (event->type == SDL_CLIPBOARDUPDATE) {
        char *text = SDL_GetClipboardText();
        if (!text) {
            LOGW("Could not get clipboard text: %s", SDL_GetError());
            return false;
        }

        char *text_dup = strdup(text);
        SDL_free(text);
        if (!text_dup) {
            LOGW("Could not strdup input text");
            return false;
        }

        struct sc_control_msg msg;
        msg.type = SC_CONTROL_MSG_TYPE_SET_CLIPBOARD;
        msg.set_clipboard.sequence = SC_SEQUENCE_INVALID;
        msg.set_clipboard.text = text_dup;
        msg.set_clipboard.paste = false;

        if (!sc_controller_push_msg(screen->im.controller, &msg)) {
            free(text_dup);
            LOGW("Could not request 'set device clipboard'");
            return false;
        }
        return true;
    }
    
    return sc_screen_handle_event_hijack(screen, event);
}


#include "scrcpy-porting.h"

SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h, Uint32 flags);
SDL_Window *SDL_CreateWindow_hijack(const char *title, int x, int y, int w, int h, Uint32 flags) {
    SDL_Window *window = SDL_CreateWindow(title, x, y, w, h, flags);
    ScrcpyUpdateStatus(ScrcpyStatusSDLWindowCreated);
    return window;
}

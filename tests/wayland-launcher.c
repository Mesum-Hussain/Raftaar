/* A focused file-manager stand-in that passes a token to an unrelated process. */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"
#include "xdg-activation-client-protocol.h"

/* Headless Sway needs an input device to advertise keyboard focus events. */
static const struct wl_message virtual_keyboard_requests[] = {
    {"keymap", "uhu", NULL}, {"key", "uuu", NULL},
    {"modifiers", "uuuu", NULL}, {"destroy", "", NULL},
};
static const struct wl_interface virtual_keyboard_interface = {
    "zwp_virtual_keyboard_v1", 1, 4, virtual_keyboard_requests, 0, NULL,
};
static const struct wl_interface *virtual_keyboard_types[] = {
    &wl_seat_interface, &virtual_keyboard_interface,
};
static const struct wl_message virtual_keyboard_manager_requests[] = {
    {"create_virtual_keyboard", "on", virtual_keyboard_types},
};
static const struct wl_interface virtual_keyboard_manager_interface = {
    "zwp_virtual_keyboard_manager_v1", 1, 1,
    virtual_keyboard_manager_requests, 0, NULL,
};

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct wl_seat *seat;
static struct wl_keyboard *keyboard;
static struct xdg_wm_base *wm_base;
static struct xdg_activation_v1 *activation;
static struct wl_proxy *virtual_keyboard_manager;
static struct wl_surface *surface;
static const char *token_path;
static int width = 640, height = 400, token_requested;

static void fail(const char *message) {
    fprintf(stderr, "wayland launcher: %s\n", message);
    exit(1);
}

static void token_done(void *data, struct xdg_activation_token_v1 *token,
                       const char *value) {
    char *temporary;
    if (asprintf(&temporary, "%s.tmp", token_path) < 0) {
        fail("cannot allocate token output path");
    }
    FILE *file = fopen(temporary, "w");
    if (!file || fputs(value, file) == EOF || fclose(file)) {
        fail("cannot write activation token");
    }
    if (rename(temporary, token_path)) {
        fail("cannot publish activation token");
    }
    free(temporary);
    xdg_activation_token_v1_destroy(token);
}
static const struct xdg_activation_token_v1_listener token_listener = {
    .done = token_done,
};

static void keyboard_keymap(void *data, struct wl_keyboard *keyboard,
                            uint32_t format, int32_t fd, uint32_t size) {
    close(fd);
}
static void keyboard_enter(void *data, struct wl_keyboard *keyboard,
                           uint32_t serial, struct wl_surface *focused,
                           struct wl_array *keys) {
    if (focused != surface || token_requested) {
        return;
    }
    token_requested = 1;
    struct xdg_activation_token_v1 *token =
        xdg_activation_v1_get_activation_token(activation);
    xdg_activation_token_v1_add_listener(token, &token_listener, NULL);
    xdg_activation_token_v1_set_serial(token, serial, seat);
    xdg_activation_token_v1_set_surface(token, surface);
    xdg_activation_token_v1_set_app_id(token, "raftaar");
    xdg_activation_token_v1_commit(token);
}
static void keyboard_leave(void *data, struct wl_keyboard *keyboard,
                           uint32_t serial, struct wl_surface *surface) {}
static void keyboard_key(void *data, struct wl_keyboard *keyboard,
                         uint32_t serial, uint32_t time, uint32_t key,
                         uint32_t state) {}
static void keyboard_modifiers(void *data, struct wl_keyboard *keyboard,
                               uint32_t serial, uint32_t depressed,
                               uint32_t latched, uint32_t locked,
                               uint32_t group) {}
static const struct wl_keyboard_listener keyboard_listener = {
    .keymap = keyboard_keymap, .enter = keyboard_enter,
    .leave = keyboard_leave, .key = keyboard_key,
    .modifiers = keyboard_modifiers,
};

static void seat_capabilities(void *data, struct wl_seat *seat, uint32_t caps) {
    if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !keyboard) {
        keyboard = wl_seat_get_keyboard(seat);
        wl_keyboard_add_listener(keyboard, &keyboard_listener, NULL);
    }
}
static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities,
};

static void wm_ping(void *data, struct xdg_wm_base *wm_base, uint32_t serial) {
    xdg_wm_base_pong(wm_base, serial);
}
static const struct xdg_wm_base_listener wm_listener = {.ping = wm_ping};

static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    if (!strcmp(interface, "wl_compositor")) {
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 1);
    } else if (!strcmp(interface, "wl_shm")) {
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    } else if (!strcmp(interface, "wl_seat")) {
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
        wl_seat_add_listener(seat, &seat_listener, NULL);
    } else if (!strcmp(interface, "xdg_wm_base")) {
        wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(wm_base, &wm_listener, NULL);
    } else if (!strcmp(interface, "xdg_activation_v1")) {
        activation = wl_registry_bind(registry, name, &xdg_activation_v1_interface, 1);
    } else if (!strcmp(interface, "zwp_virtual_keyboard_manager_v1")) {
        virtual_keyboard_manager = wl_registry_bind(
            registry, name, &virtual_keyboard_manager_interface, 1);
    }
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {
    .global = global, .global_remove = global_remove,
};

static void buffer_release(void *data, struct wl_buffer *buffer) {
    wl_buffer_destroy(buffer);
}
static const struct wl_buffer_listener buffer_listener = {.release = buffer_release};

static void surface_configure(void *data, struct xdg_surface *xdg_surface,
                              uint32_t serial) {
    xdg_surface_ack_configure(xdg_surface, serial);
    size_t size = (size_t)width * height * 4;
    int fd = memfd_create("launch-window", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, size)) {
        fail("cannot allocate window buffer");
    }
    uint32_t *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED) {
        fail("cannot map window buffer");
    }
    for (size_t i = 0; i < size / 4; i++) {
        pixels[i] = 0xff334455;
    }
    munmap(pixels, size);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(
        pool, 0, width, height, width * 4, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    wl_buffer_add_listener(buffer, &buffer_listener, NULL);
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage(surface, 0, 0, width, height);
    wl_surface_commit(surface);
}
static const struct xdg_surface_listener surface_listener = {
    .configure = surface_configure,
};
static void toplevel_configure(void *data, struct xdg_toplevel *toplevel,
                               int32_t new_width, int32_t new_height,
                               struct wl_array *states) {
    if (new_width > 0) width = new_width;
    if (new_height > 0) height = new_height;
}
static void toplevel_close(void *data, struct xdg_toplevel *toplevel) { exit(0); }
static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure, .close = toplevel_close,
};

int main(int argc, char **argv) {
    if (argc != 2) fail("expected activation token output path");
    token_path = argv[1];
    display = wl_display_connect(NULL);
    if (!display) fail("cannot connect to compositor");
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0) fail("cannot read globals");
    if (!compositor || !shm || !seat || !wm_base || !activation ||
        !virtual_keyboard_manager) fail("required Wayland interface missing");

    struct wl_proxy *virtual_keyboard = wl_proxy_marshal_flags(
        virtual_keyboard_manager, 0, &virtual_keyboard_interface, 1, 0, seat, NULL);
    static const char keymap[] =
        "xkb_keymap {\n"
        "xkb_keycodes { minimum = 8; maximum = 255; <ESC> = 9; };\n"
        "xkb_types { type \"ONE_LEVEL\" { modifiers = none; "
        "level_name[Level1] = \"Any\"; }; };\n"
        "xkb_compatibility {};\n"
        "xkb_symbols { key <ESC> { [ Escape ] }; };\n"
        "};\n";
    int fd = memfd_create("launch-keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, keymap, sizeof(keymap)) != sizeof(keymap)) {
        fail("cannot create keyboard keymap");
    }
    wl_proxy_marshal_flags(virtual_keyboard, 0, NULL, 1, 0,
                           WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, sizeof(keymap));
    close(fd);

    surface = wl_compositor_create_surface(compositor);
    struct xdg_surface *xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
    xdg_surface_add_listener(xdg_surface, &surface_listener, NULL);
    struct xdg_toplevel *toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_app_id(toplevel, "raftaar-launcher");
    xdg_toplevel_set_title(toplevel, "File manager");
    wl_surface_commit(surface);
    while (wl_display_dispatch(display) >= 0) {}
    fail("compositor disconnected");
}

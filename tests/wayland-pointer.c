/* A stand-in pointer for headless Sway. Each line on stdin, "X Y SOURCE VALUE COUNT", points at
   x y of the output, then scrolls: SOURCE is wheel, finger or continuous, and VALUE each event's
   distance in surface pixels, sent COUNT times, a frame each, as a wheel or touchpad would. "ok"
   follows once Sway has them. One pointer serves every line: a seat that loses its last pointer
   takes the capability from its clients, and a new one reaches them only after its first events. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

static const struct wl_interface virtual_pointer_interface;
static const struct wl_interface *no_types[] = {NULL, NULL, NULL, NULL, NULL};
static const struct wl_message virtual_pointer_requests[] = {
    {"motion", "uff", no_types}, {"motion_absolute", "uuuuu", no_types},
    {"button", "uuu", no_types}, {"axis", "uuf", no_types}, {"frame", "", no_types},
    {"axis_source", "u", no_types}, {"axis_stop", "uu", no_types},
    {"axis_discrete", "uufi", no_types}, {"destroy", "", no_types},
};
static const struct wl_interface virtual_pointer_interface = {
    "zwlr_virtual_pointer_v1", 1, 9, virtual_pointer_requests, 0, NULL,
};
static const struct wl_interface *manager_types[] = {&wl_seat_interface, &virtual_pointer_interface};
static const struct wl_message manager_requests[] = {
    {"create_virtual_pointer", "?on", manager_types}, {"destroy", "", no_types},
};
static const struct wl_interface manager_interface = {
    "zwlr_virtual_pointer_manager_v1", 1, 2, manager_requests, 0, NULL,
};

static struct wl_seat *seat;
static struct wl_proxy *manager;

static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    if (!strcmp(interface, "wl_seat"))
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (!strcmp(interface, manager_interface.name))
        manager = wl_registry_bind(registry, name, &manager_interface, 1);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {
    .global = global, .global_remove = global_remove,
};

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "cannot connect to Wayland\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!seat || !manager) {
        fprintf(stderr, "no virtual pointer manager\n");
        return 1;
    }
    struct wl_proxy *pointer = wl_proxy_marshal_flags(manager, 0, &virtual_pointer_interface, 1, 0,
                                                      seat, NULL);
    wl_display_roundtrip(display);
    printf("ready\n");
    fflush(stdout);
    uint32_t time = 0;
    int x, y, count;
    char name[16];
    double value;
    while (scanf("%d %d %15s %lf %d", &x, &y, name, &value, &count) == 5) {
        uint32_t source = !strcmp(name, "finger") ? WL_POINTER_AXIS_SOURCE_FINGER
                        : !strcmp(name, "continuous") ? WL_POINTER_AXIS_SOURCE_CONTINUOUS
                        : WL_POINTER_AXIS_SOURCE_WHEEL;
        wl_proxy_marshal_flags(pointer, 1, NULL, 1, 0, ++time, x, y, 1280, 800);
        wl_proxy_marshal_flags(pointer, 4, NULL, 1, 0);
        wl_display_roundtrip(display);
        for (int i = 0; i < count; i++) {
            wl_proxy_marshal_flags(pointer, 5, NULL, 1, 0, source);
            wl_proxy_marshal_flags(pointer, 3, NULL, 1, 0, ++time, WL_POINTER_AXIS_VERTICAL_SCROLL,
                                   wl_fixed_from_double(value));
            wl_proxy_marshal_flags(pointer, 4, NULL, 1, 0);
            wl_display_roundtrip(display);
        }
        printf("ok\n");
        fflush(stdout);
    }
    wl_proxy_marshal_flags(pointer, 8, NULL, 1, WL_MARSHAL_FLAG_DESTROY);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}

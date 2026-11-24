// Minimal virtual-pointer client: vptr <x> <y> <W> <H> [click]
// Moves the pointer to absolute (x,y) on a WxH output via zwlr_virtual_pointer_v1 and optionally left-clicks.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <linux/input-event-codes.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"
static struct zwlr_virtual_pointer_manager_v1 *mgr; static struct wl_seat *seat;
static void reg(void *d, struct wl_registry *r, uint32_t n, const char *i, uint32_t v) {
  if (!strcmp(i, zwlr_virtual_pointer_manager_v1_interface.name)) mgr = wl_registry_bind(r, n, &zwlr_virtual_pointer_manager_v1_interface, 1);
  else if (!strcmp(i, "wl_seat") && !seat) seat = wl_registry_bind(r, n, &wl_seat_interface, 1);
}
static void rem(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener rl = { reg, rem };
static uint32_t now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000 + t.tv_nsec / 1000000; }
int main(int argc, char **argv) {
  if (argc < 5) return 2;
  struct wl_display *d = wl_display_connect(NULL); if (!d) { fprintf(stderr, "no display\n"); return 1; }
  struct wl_registry *r = wl_display_get_registry(d); wl_registry_add_listener(r, &rl, NULL); wl_display_roundtrip(d);
  if (!mgr) { fprintf(stderr, "compositor has no zwlr_virtual_pointer_manager_v1\n"); return 1; }
  struct zwlr_virtual_pointer_v1 *p = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(mgr, seat);
  zwlr_virtual_pointer_v1_motion_absolute(p, now(), atoi(argv[1]), atoi(argv[2]), atoi(argv[3]), atoi(argv[4]));
  zwlr_virtual_pointer_v1_frame(p); wl_display_roundtrip(d); usleep(300000);
  if (argc > 5 && !strcmp(argv[5], "click")) {
    zwlr_virtual_pointer_v1_button(p, now(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED); zwlr_virtual_pointer_v1_frame(p); wl_display_roundtrip(d); usleep(150000);
    zwlr_virtual_pointer_v1_button(p, now(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED); zwlr_virtual_pointer_v1_frame(p); wl_display_roundtrip(d);
  }
  usleep(200000); return 0;
}

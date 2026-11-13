// The Rust static library's functions (crates/horizon-ios/src/lib.rs).
#pragma once
#include <stdbool.h>

/// Runs the app's only event loop (winit's UIApplicationMain). Never returns on a device.
int hz_run(void);
/// Play: a JSON array of the game's arguments. The game starts inside the running loop.
bool hz_play(const char *args_json);
/// A touch control's control line: "key space down", "mouse left click", "turn 2.5 -1".
void hz_input(const char *line);
/// Whether the player is in the world with no screen open.
bool hz_playing(void);
/// Why the last Play stopped before the game opened, or NULL. Valid until the next call.
const char *hz_last_error(void);
/// The virtual mouse: cursor position in pixels of the game view, buttons (0 left, 1 right,
/// 2 middle) and the wheel in lines.
void hz_pointer_move(double x, double y);
void hz_pointer_button(unsigned char button, bool pressed);
void hz_pointer_wheel(float lines);

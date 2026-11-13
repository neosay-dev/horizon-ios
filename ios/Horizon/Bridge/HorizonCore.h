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

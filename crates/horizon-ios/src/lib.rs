//! The iOS app's Rust side, a static library the Swift app links (`ios/`).
//!
//! Swift's `main` calls [`hz_run`], which never returns: winit starts `UIApplicationMain` and
//! the loop calls back `hz_swift_show_launcher` (Swift shows its SwiftUI launcher window). Play
//! calls [`hz_play`] with the game's command line; the game starts inside the same loop
//! (`horizon_client::ios`). The touch controls send control lines with [`hz_input`].
//!
//! C declarations: `ios/Horizon/Bridge/HorizonCore.h`.

use std::ffi::{CStr, c_char};

unsafe extern "C" {
    fn hz_swift_show_launcher();
    fn hz_swift_game_started();
    fn hz_swift_game_failed();
}

fn show_launcher() {
    // Safety: a Swift `@_cdecl` function with no arguments, called on the main thread.
    unsafe { hz_swift_show_launcher() }
}
fn game_started() {
    // Safety: as above.
    unsafe { hz_swift_game_started() }
}
fn game_failed() {
    // Safety: as above.
    unsafe { hz_swift_game_failed() }
}

/// Reads a C string from Swift; `None` for null or text that isn't UTF-8.
///
/// # Safety
/// `ptr` is null or a NUL-terminated string valid for the call.
unsafe fn text(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    // Safety: the caller's contract.
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .ok()
        .map(str::to_owned)
}

/// Runs the app. Call once, from `main`, on the main thread; returns only if the loop could not start.
#[unsafe(no_mangle)]
pub extern "C" fn hz_run() -> i32 {
    let hooks = horizon_client::ios::Hooks {
        show_launcher,
        game_started,
        game_failed,
    };
    match horizon_client::ios::run(hooks) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("Horizon: the event loop did not start: {e}");
            1
        }
    }
}

/// Play: `args_json` is a JSON array of the game's arguments, e.g.
/// `["--game-dir", "/…/Documents/game", "--resources", "/…/Documents/resources/26.3",
/// "--home", "/…/Library/Horizon", "--session-file", "/…/tmp/session.json"]`.
/// The working directory becomes `--game-dir`'s, where the game keeps its files.
///
/// # Safety
/// `args_json` is null or a NUL-terminated string valid for the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_play(args_json: *const c_char) -> bool {
    // Safety: the caller's contract.
    let Some(json) = (unsafe { text(args_json) }) else {
        return false;
    };
    let Ok(args) = serde_json::from_str::<Vec<String>>(&json) else {
        return false;
    };
    if let Some(dir) = args
        .iter()
        .skip_while(|a| *a != "--game-dir")
        .nth(1)
    {
        let _ = std::fs::create_dir_all(dir);
        let _ = std::env::set_current_dir(dir);
    }
    horizon_client::ios::request_play(args);
    true
}

/// A touch control's control line (`key space down`, `mouse left click`, `turn 2.5 -1`), run at
/// the next frame. Any thread.
///
/// # Safety
/// `line` is null or a NUL-terminated string valid for the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_input(line: *const c_char) {
    // Safety: the caller's contract.
    if let Some(line) = unsafe { text(line) } {
        horizon_client::ios::push_input(line);
    }
}

/// Whether the player is in the world with no screen open: the touch controls show only then,
/// and elsewhere a finger is the pointer.
#[unsafe(no_mangle)]
pub extern "C" fn hz_playing() -> bool {
    horizon_client::ios::playing()
}

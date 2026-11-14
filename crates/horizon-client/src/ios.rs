//! iOS: one winit event loop for the whole app.
//!
//! winit's `run_app` calls `UIApplicationMain`, which may run once per process and never
//! returns. So on iOS the app's loop starts first ([`run`]) with nothing but the launcher (a
//! SwiftUI window the `horizon-ios` crate shows through [`Hooks`]); Play hands the command line
//! to [`request_play`], the root handler runs [`crate::entry::main`] inside the loop, and the
//! game's own handler, which elsewhere would open a loop of its own, is handed to the root
//! ([`hand_off`]) and gets every later event.
//!
//! Touch controls reach the game as control-socket lines ([`push_input`]): `key w down`,
//! `mouse left click`, `turn 3.5 -1.0`. The game drains them once a frame
//! (`Game::poll_control`) through the same path a replay takes. Over the screens a virtual
//! mouse (a cursor Swift draws, moved like a trackpad) sends window events
//! ([`pointer_move`], [`pointer_button`], [`pointer_wheel`]).

use std::cell::RefCell;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
use winit::application::ApplicationHandler;
use winit::event::{DeviceEvent, DeviceId, StartCause, WindowEvent};
use winit::event_loop::{ActiveEventLoop, EventLoop, EventLoopProxy};
use winit::window::WindowId;

/// What the app (Swift, through `horizon-ios`) does at the loop's turns.
#[derive(Clone, Copy)]
pub struct Hooks {
    /// The loop is up and there is no game yet: show the launcher.
    pub show_launcher: fn(),
    /// Play was pressed and the game is starting: hide the launcher, show the touch controls.
    pub game_started: fn(),
    /// The game stopped before it opened its window (an error): show the launcher again.
    pub game_failed: fn(),
}

static ARGS: Mutex<Option<Vec<String>>> = Mutex::new(None);
static PLAY: Mutex<Option<Vec<String>>> = Mutex::new(None);
static INPUT: Mutex<Vec<String>> = Mutex::new(Vec::new());
static PROXY: OnceLock<EventLoopProxy<()>> = OnceLock::new();
static PLAYING: AtomicBool = AtomicBool::new(false);
static ERROR: Mutex<Option<String>> = Mutex::new(None);

/// Why the game stopped before it opened (elsewhere the process would exit with it).
pub fn set_error(message: String) {
    *lock(&ERROR) = Some(message);
}

/// The last start's error, for the launcher to show.
pub fn take_error() -> Option<String> {
    lock(&ERROR).take()
}

/// Whether the player is in the world with no screen open, where the touch controls show.
/// The game says so each frame.
pub fn playing() -> bool {
    PLAYING.load(Ordering::Relaxed)
}

/// The game's frame: in the world with no screen open, or not.
pub fn set_playing(playing: bool) {
    PLAYING.store(playing, Ordering::Relaxed);
}

thread_local! {
    static HANDOFF: RefCell<Option<Box<dyn Handoff>>> = const { RefCell::new(None) };
}

/// A game handler the root loop runs, which can say why it asked the loop to end.
pub trait Handoff: ApplicationHandler {
    /// The error it stopped with, if any. Elsewhere `run_app` returns and the caller logs it;
    /// on iOS winit ignores the request to end the loop, so the root checks after each turn.
    fn error_text(&mut self) -> Option<String>;
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// The command line Play gave, in place of the process's (an iOS app has none).
pub fn args() -> Vec<String> {
    lock(&ARGS).clone().unwrap_or_default()
}

/// Play: start the game with this command line (`--game-dir`, `--resources`, `--session-file`...).
/// Any thread; the loop wakes and starts it on the main thread.
pub fn request_play(args: Vec<String>) {
    *lock(&PLAY) = Some(args);
    if let Some(proxy) = PROXY.get() {
        let _ = proxy.send_event(());
    }
}

/// A touch control's line, run at the next frame as a control-socket command.
pub fn push_input(line: impl Into<String>) {
    lock(&INPUT).push(line.into());
}

/// The lines the touch controls sent since the last frame.
pub fn take_input() -> Vec<String> {
    std::mem::take(&mut *lock(&INPUT))
}

/// The game's handler, where another platform would run `EventLoop::run_app` with it.
pub fn hand_off(app: impl Handoff + 'static) {
    HANDOFF.with(|h| *h.borrow_mut() = Some(Box::new(app)));
}

/// Whether the game handed its handler to the root (so `entry::main` returning is not the end).
pub fn handed_off() -> bool {
    HANDOFF.with(|h| h.borrow().is_some())
}

/// Runs the app's only event loop. Never returns on a device.
pub fn run(hooks: Hooks) -> Result<(), winit::error::EventLoopError> {
    let event_loop = EventLoop::new()?;
    let _ = PROXY.set(event_loop.create_proxy());
    let mut root = Root {
        hooks,
        game: None,
        shown: false,
        window: None,
    };
    // iOS gives the main thread 1 MB of stack, and the game needs the 8 MB it has on macOS and
    // Linux (Windows links 8 MB for it: packaging/windows/exe.rs): the handoff to the game builds
    // `Game` deep in the event loop, and with 1 MB the process died there without a note. The
    // whole loop (UIApplicationMain and every callback) runs on a stack of its own instead, still
    // on the main thread. It never returns, so the stack is never freed.
    stacker::grow(MAIN_STACK, || event_loop.run_app(&mut root))
}

/// The main thread's stack for the event loop: twice the desktop's 8 MB, as headroom; only the
/// pages it touches take memory.
const MAIN_STACK: usize = 16 << 20;

struct Root {
    hooks: Hooks,
    game: Option<Box<dyn Handoff>>,
    shown: bool,
    /// The game's window, which the virtual mouse's events go to.
    window: Option<WindowId>,
}

impl Root {
    fn start(&mut self, event_loop: &ActiveEventLoop) {
        if self.game.is_some() {
            return;
        }
        let Some(args) = lock(&PLAY).take() else {
            return;
        };
        log::info!("Horizon iOS: starting with {args:?}");
        *lock(&ARGS) = Some(args);
        (self.hooks.game_started)();
        crate::entry::main();
        match HANDOFF.with(|h| h.borrow_mut().take()) {
            Some(mut game) => {
                game.resumed(event_loop);
                self.game = Some(game);
            }
            None => (self.hooks.game_failed)(),
        }
    }
}

impl ApplicationHandler for Root {
    fn new_events(&mut self, event_loop: &ActiveEventLoop, cause: StartCause) {
        if let Some(g) = &mut self.game {
            g.new_events(event_loop, cause);
        }
    }
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if let Some(g) = &mut self.game {
            g.resumed(event_loop);
        } else if !self.shown {
            self.shown = true;
            (self.hooks.show_launcher)();
        }
    }
    fn user_event(&mut self, event_loop: &ActiveEventLoop, _: ()) {
        self.start(event_loop);
    }
    fn window_event(&mut self, event_loop: &ActiveEventLoop, id: WindowId, event: WindowEvent) {
        self.window = Some(id);
        // Fingers never reach the game: the Swift overlay turns them into keys, the view's
        // turns and the virtual mouse.
        if matches!(event, WindowEvent::Touch(_)) {
            return;
        }
        if let Some(g) = &mut self.game {
            g.window_event(event_loop, id, event);
        }
    }
    fn device_event(&mut self, event_loop: &ActiveEventLoop, id: DeviceId, event: DeviceEvent) {
        if let Some(g) = &mut self.game {
            g.device_event(event_loop, id, event);
        }
    }
    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        // A Play sent before the proxy existed.
        if self.game.is_none() {
            self.start(event_loop);
        }
        if let Some(g) = &mut self.game {
            if let Some(id) = self.window {
                for event in pointer_events() {
                    g.window_event(event_loop, id, event);
                }
            }
            g.about_to_wait(event_loop);
            // The game stopped with an error and asked the loop to end, which iOS ignores:
            // log it and go back to the launcher with it.
            if let Some(e) = g.error_text() {
                log::error!("Horizon: {e}");
                let _ = std::fs::write(crate::logging::game_home().join("last-error.txt"), &e);
                crate::logging::flush();
                self.game = None;
                set_error(e);
                (self.hooks.game_failed)();
            }
        }
    }
    fn suspended(&mut self, event_loop: &ActiveEventLoop) {
        if let Some(g) = &mut self.game {
            g.suspended(event_loop);
        }
    }
    fn exiting(&mut self, event_loop: &ActiveEventLoop) {
        if let Some(g) = &mut self.game {
            g.exiting(event_loop);
            crate::logging::flush();
        }
    }
    fn memory_warning(&mut self, event_loop: &ActiveEventLoop) {
        if let Some(g) = &mut self.game {
            g.memory_warning(event_loop);
        }
    }
}

/// The virtual mouse's events (Swift's cursor over the screens), in the game view's pixels.
enum Pointer {
    Move(f64, f64),
    Button(winit::event::MouseButton, bool),
    Wheel(f32),
}

static POINTER: Mutex<Vec<Pointer>> = Mutex::new(Vec::new());

/// The virtual cursor moved to (x, y), in pixels from the game view's top left.
pub fn pointer_move(x: f64, y: f64) {
    lock(&POINTER).push(Pointer::Move(x, y));
}

/// A virtual mouse button: 0 left, 1 right, 2 middle.
pub fn pointer_button(button: u8, pressed: bool) {
    use winit::event::MouseButton;
    let button = match button {
        1 => MouseButton::Right,
        2 => MouseButton::Middle,
        _ => MouseButton::Left,
    };
    lock(&POINTER).push(Pointer::Button(button, pressed));
}

/// The virtual wheel, in lines (up is positive).
pub fn pointer_wheel(lines: f32) {
    lock(&POINTER).push(Pointer::Wheel(lines));
}

/// The virtual mouse's events since the last turn, as the window events a mouse would send.
fn pointer_events() -> Vec<WindowEvent> {
    use winit::event::{ElementState, MouseScrollDelta, TouchPhase};
    let device_id = DeviceId::dummy();
    std::mem::take(&mut *lock(&POINTER))
        .into_iter()
        .map(|p| match p {
            Pointer::Move(x, y) => WindowEvent::CursorMoved {
                device_id,
                position: winit::dpi::PhysicalPosition::new(x, y),
            },
            Pointer::Button(button, pressed) => WindowEvent::MouseInput {
                device_id,
                state: if pressed {
                    ElementState::Pressed
                } else {
                    ElementState::Released
                },
                button,
            },
            Pointer::Wheel(lines) => WindowEvent::MouseWheel {
                device_id,
                delta: MouseScrollDelta::LineDelta(0.0, lines),
                phase: TouchPhase::Moved,
            },
        })
        .collect()
}

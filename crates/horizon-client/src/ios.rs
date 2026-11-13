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
//! (`Game::poll_control`) through the same path a replay takes.

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
    static HANDOFF: RefCell<Option<Box<dyn ApplicationHandler>>> = const { RefCell::new(None) };
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
pub fn hand_off(app: impl ApplicationHandler + 'static) {
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
    };
    event_loop.run_app(&mut root)
}

struct Root {
    hooks: Hooks,
    game: Option<Box<dyn ApplicationHandler>>,
    shown: bool,
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
            g.about_to_wait(event_loop);
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
        }
    }
    fn memory_warning(&mut self, event_loop: &ActiveEventLoop) {
        if let Some(g) = &mut self.game {
            g.memory_warning(event_loop);
        }
    }
}

thread_local! {
    static POINTER: RefCell<TouchPointer> = RefCell::new(TouchPointer::default());
}

/// The mouse events a touch on the game's view stands for (see [`TouchPointer`]).
pub fn touch_as_mouse(touch: &winit::event::Touch) -> Vec<WindowEvent> {
    POINTER.with(|p| p.borrow_mut().events(touch))
}

/// Touches as the pointer, for the screens (menus, inventory): the first finger moves the cursor
/// and presses the left button. In the world the Swift overlay takes the touches itself.
#[derive(Default)]
pub struct TouchPointer {
    finger: Option<u64>,
}

impl TouchPointer {
    /// The mouse events one touch event stands for.
    pub fn events(&mut self, touch: &winit::event::Touch) -> Vec<WindowEvent> {
        use winit::event::{ElementState, MouseButton, TouchPhase};
        let device_id = DeviceId::dummy();
        let moved = WindowEvent::CursorMoved {
            device_id,
            position: touch.location,
        };
        let button = |state| WindowEvent::MouseInput {
            device_id,
            state,
            button: MouseButton::Left,
        };
        match touch.phase {
            TouchPhase::Started if self.finger.is_none() => {
                self.finger = Some(touch.id);
                vec![moved, button(ElementState::Pressed)]
            }
            TouchPhase::Moved if self.finger == Some(touch.id) => vec![moved],
            TouchPhase::Ended | TouchPhase::Cancelled if self.finger == Some(touch.id) => {
                self.finger = None;
                vec![moved, button(ElementState::Released)]
            }
            _ => Vec::new(),
        }
    }
}

# Horizon for iOS

An unofficial iOS port of Horizon: the Rust game as a static library (`crates/horizon-ios`), with a
SwiftUI launcher in Liquid Glass (iOS 26; a material fallback from iOS 17) and touch controls.

## How it fits together

- `main.swift` calls `hz_run()` (Rust). winit starts `UIApplicationMain` and calls back
  `hz_swift_show_launcher`, and Swift shows the launcher window.
- **Play** gets a fresh Microsoft session (the owner gate), writes `--session-file`, and calls
  `hz_play([...args])`. The game starts inside the same event loop (`horizon_client::ios`): on iOS
  the game's handler is handed to the app's loop instead of opening a loop of its own.
- **Touch controls** are a pass-through window above the game's window. They send control-socket
  lines (`key w down`, `mouse left click`, `turn 2.5 -1`, `hotbar 3`) through `hz_input`, and the
  game runs them each frame as a replay would. They show only while `hz_playing()` (in the world
  with no screen open). Elsewhere a finger is the pointer: winit's touches become cursor moves and
  left clicks.

## Controls

| Control | Action |
|---|---|
| Stick (left) | W A S D; pushed to the rim straight ahead: sprint |
| Drag anywhere | look around |
| Tap | use / place (right click) |
| Hold still | break / attack (left button held) |
| Jump, Attack, Use, Sneak (toggle), Sprint (toggle) | Space, left button, right button, Shift, Ctrl |
| Inventory, Drop, Chat, Pause, View | E, Q, T + system keyboard, Esc, F5 |
| Hotbar strip | `hotbar 1-9`; resize it in the editor to sit over the game's |
| Layout | the editor: drag, resize, opacity, toggle, add custom buttons (any key or mouse button) |

The layout lives in `Library/Horizon/controls.json`.

## Resources

The game needs the resources `horizon-prepare` builds from **your own** copy of Java Edition 26.3
(`.local/horizon-client/26.3`). Import that folder in the launcher (Files), or copy it to
`Documents/resources/26.3` with Finder (file sharing is on). Never commit or share it.

## Microsoft sign-in

Play needs a Microsoft account that owns Minecraft: Java Edition. There are no offline accounts,
as in Horizon's own launcher (docs/microsoft-account.md). A port may not use Horizon's client ID
(docs/forking.md). Register your own:

1. Azure portal → App registrations → New: personal Microsoft accounts only, *Allow public client
   flows: Yes*.
2. Apply for Minecraft API access with the App ID review form (https://aka.ms/mce-reviewappid).
   Until Mojang approves it, sign-in stops with "not approved by Mojang yet".
3. Put the client ID in the repository variable `HZ_MSA_CLIENT_ID` (Settings → Variables →
   Actions). The workflow passes it into `Info.plist`.

## Build

GitHub Actions: **Actions → iOS → Run workflow**. It builds the Rust library, generates the Xcode
project and makes `Horizon-unsigned.ipa` (an artifact). Sideload it with AltStore, SideStore,
Sideloadly or TrollStore.

On a Mac:

```sh
ios/build-rust.sh                       # target/aarch64-apple-ios/release/libhorizon_ios.a
cd ios && xcodegen generate && open Horizon.xcodeproj
```

## Not done yet

- Controllers (GameController.framework): gilrs has no iOS backend, so `controllers` is off.
- Horizon's extras (Discord, friends, heartbeat) are off.
- Quitting the game ends the app. iOS can't restart a winit loop, so there is no way back to the launcher.
- The system clipboard: text copied in the game pastes only in the game.
- Nothing here has been compiled yet. Expect a round of build fixes on the first CI run.

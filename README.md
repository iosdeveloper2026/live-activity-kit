# Live Activity Kit

Reusable pieces for adding a remote-controlled iOS Live Activity to any app, in the background,
with no new screens. Extracted from the GiftBox Live Activity demo.

| Folder | What it is |
|---|---|
| `Package.swift`, `ios/Sources/` | Swift package with three libraries (see below) |
| `skill/live-activity-integrator/` | Claude Code skill that installs all of this into an app |
| `schema/live_activity_config.schema.json` | JSON Schema for the `live_activity_config` Remote Config parameter |
| `examples/live_activity_config.json` | Example config with four rotating cards |
| `firebase/firestore.rules` | Firestore rules: apps may only write their own token record |
| `INSTALL.md` | Step-by-step install into an existing app |

The scheduler is the separate template repo
[`live-activity-cron`](https://github.com/iosdeveloper2026/live-activity-cron).

## Quick start

**Add to an app by hand:** follow [INSTALL.md](INSTALL.md). Swift Package URL: `https://github.com/iosdeveloper2026/live-activity-kit`.

**Let Claude Code do it:** on the Mac where you build the app, run

```bash
git clone https://github.com/iosdeveloper2026/live-activity-kit.git
./live-activity-kit/skill/install.sh
```

then, in Claude Code in the app's folder: *"add the Live Activity kit to this app"*.

## Swift package

| Library | Target | Purpose |
|---|---|---|
| `LiveActivityKit` | App | Headless runtime: `LiveActivityKit.start()` saves push tokens to Firestore, syncs the config, downloads every card's images, tracks remotely started Live Activities, and forwards the APNs token to Firebase (works for SwiftUI apps without an app delegate). |
| `LiveActivityKitWidget` | Widget extension | `LiveActivityKitWidget()`: all Lock Screen and Dynamic Island layouts |
| `LiveActivityKitShared` | Both (internal) | `LiveActivityAttributes`, App Group lookup, colour helper |

No code is templated per app: the App Group comes from the `LiveActivityAppGroup` Info.plist key.

## Requirements

- iOS 17 deployment target; remote start needs iOS 17.2 (the kit does nothing on older versions).
- Firebase (Core, Messaging, Remote Config) 12.x, added automatically by the package.
- Live Activities are started only by the cron. Debug builds accept `-LiveActivityPreview [card]`
  to start a sample card locally.

## Several apps in one Firebase project

Each app saves its bundle ID with its tokens. Set the cron repo variable `APP_BUNDLE_ID` so each
app's cron only sends to its own devices.

## Validate a config

```bash
npx --yes ajv-cli@5.0.0 validate --spec=draft2020 -s schema/live_activity_config.schema.json -d my-config.json
```

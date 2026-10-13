---
name: live-activity-integrator
description: Add a remote-controlled iOS Live Activity (Lock Screen + Dynamic Island) to an existing iOS app in the background, with no new screens, using LiveActivityKit, Firebase Remote Config/FCM/Firestore, a GitHub Actions cron repo and a cron-job.org trigger. Use when the user asks to add, integrate, set up or install a Live Activity (or "the Live Activity kit") in an app, to build or rotate Live Activity cards from Firebase, or to set up the Live Activity cron for an app. Also use to check or repair an existing integration (tokens not arriving, cards not rotating, cron not running).
---

# Live Activity integrator

You add the LiveActivityKit system to the iOS app in the current folder (or the folder the user
names), following seven stages. **Show every step as you go**: say which stage you're in, print each
command before running it, and end each stage with its check and the result.

The kit lives at `../../` relative to this file (`ios/` package, `schema/`, `examples/`,
`firebase/`, `INSTALL.md`). Scripts are in `scripts/`, detailed references in `references/`.

## Rules

- **No screens.** Never add or change views, view controllers or navigation in the app. The only
  edit to the app's own code is the `LiveActivityKit.start()` line (plus `FirebaseApp.configure()`
  if the app has no Firebase yet).
- **Nothing new without approval.** Never create a Firebase app, a GitHub repo, or anything in
  Apple Developer / App Store Connect without the user saying yes for that specific item. Look for
  existing ones first. Never register demo or test apps.
- **No keys.** Never ask for, read, paste or print keys, tokens, passwords or `.p8` / service-account
  files. Tell the user exactly where to put them (`references/user-steps.md`).
- **Simulator first.** Use the iOS Simulator for checks. Install on a physical iPhone only when the
  user asks.
- **Confirm before publishing.** Remote Config changes are published only after the user approved
  previews of every card.
- **Re-runnable.** Every script skips what's already done. If an integration is half finished,
  run Stage 1 and continue from the first stage whose check fails.

## Stage 1 · Inspect

```bash
ruby scripts/inspect_app.rb <app folder>
```

Report: app target, bundle ID, team, deployment target, UI stack (swiftui / uikit /
compose-multiplatform), launch file, Firebase state, existing widget extensions and Live
Activities, suspicious build phases.

- **Stop** if `suspiciousBuildPhases` is not empty: show them and don't build.
- **Warn** if the app already has its own `ActivityAttributes`: ask whether to add the kit alongside.
- Ask the user (one message): **brand name, Firebase project ID, Firebase CLI account, Apple Team
  ID** (if not in the project), **repo setup** (one repo per app, the default, or a shared repo).

**Check:** the app builds unchanged on the simulator before any edit:
`xcodebuild -project <p> -scheme <s> -destination 'id=<simulator>' build`.

## Stage 2 · iOS

```bash
ruby scripts/add_kit.rb --project <App.xcodeproj> --kit <kit/ios path or Git URL> --dry-run   # show the plan
ruby scripts/add_kit.rb --project <App.xcodeproj> --kit <kit/ios path or Git URL>
python3 scripts/insert_start_line.py <launch file> [--firebase-configured] --dry-run      # show the diff
python3 scripts/insert_start_line.py <launch file> [--firebase-configured]
```

- `add_kit.rb` adds the package, the widget extension (one file from `templates/AppWidgets.swift`),
  the embed step, App Group `group.<bundle-id>` and push entitlements, Info.plist keys, and raises
  the deployment target to iOS 17 if needed.
- Pass `--firebase-configured` when Stage 1 found `FirebaseApp.configure` already.
- **Compose Multiplatform apps:** the launch file is the Swift `iOSApp.swift`; the Kotlin code is untouched.
- **User step:** if signing fails with "No Accounts", the user signs Xcode in to their Apple account.
  If the bundle ID is unavailable for the team, stop and ask; never rename without approval.

**Check:** the app builds; its screens look exactly as before; launching with
`-LiveActivityPreview 1` on the simulator shows a sample card on the Lock Screen (press Lock twice
with the simulator tool, then screenshot).

## Stage 3 · Firebase

```bash
scripts/firebase_app.sh --account <email> --project <id> --bundle-id <bundle> --out <App>/GoogleService-Info.plist
```

- If it prints NOT FOUND: ask the user whether to create the Firebase iOS app. Only after a yes,
  rerun with `--create "<App name>"`.
- Add the downloaded plist to the app target if the project doesn't pick it up automatically.
- Build the cards: see `references/card-builder.md`. Write the config to `live_activity_config.json`.
- Validate: `python3 scripts/validate_config.py live_activity_config.json --repeat-minutes <n>`.
  Fix every ERROR; explain every WARNING to the user.
- **Preview every card** on the simulator (`-LiveActivityPreview <n>` for n = 1…cards) and show
  the screenshots. Publish only after the user approves:
  `python3 scripts/publish_config.py --account <email> --project <id> --config live_activity_config.json` (dry),
  then again with `--yes`.
- Firestore: if not set up, deploy `firebase/firestore.rules` (ask before enabling Firestore in a project).
- **User step:** upload the APNs key (.p8) to Firebase Cloud Messaging, both rows (`references/user-steps.md`).

**Check:** `python3 scripts/check_tokens.py --account <email> --project <id> --bundle-id <bundle>`
shows the simulator or device with an FCM token and a push-to-start token.

## Stage 4 · GitHub

```bash
scripts/cron_repo.sh --repo <owner>/<app>-live-activity-cron --bundle-id <bundle> --repeat-minutes <n> --dry-run
scripts/cron_repo.sh --repo <owner>/<app>-live-activity-cron --bundle-id <bundle> --repeat-minutes <n>
```

- Ask before creating the repo (it's public). Set `REPEAT_EVERY_MINUTES` to at least the longest timer.
- **User steps:** `gh auth login` if needed; add the `FIREBASE_SERVICE_ACCOUNT` secret.
- Run once: `gh workflow run live-activity.yml -R <repo>`, then read the log line with the counts.

**Check:** the run succeeds with `"failed":0`. `"failed"` with `THIRD_PARTY_AUTH_ERROR` means the
APNs key isn't uploaded (Stage 3 user step).

## Stage 5 · Timer (cron-job.org)

`cron_repo.sh` prints the curl command. **User steps:** create the fine-grained token (this repo
only, Actions: Read and write) and the cron-job.org job via Import from curl; set Content-Type to
`application/json`; Test run must return 204.

**Check:** three runs about 5 minutes apart in `gh run list -R <repo>`.

## Stage 6 · Device (only when the user asks)

```bash
scripts/device.sh status
scripts/device.sh install <path>/Build/Products/Debug-iphoneos/<App>.app
scripts/device.sh open <bundle-id>      # saves tokens, downloads every card's images
scripts/device.sh close <AppName>
gh workflow run live-activity.yml -R <repo>
scripts/device.sh screenshot shot.png   # ask the user to wake the phone first
```

Build for a device with `-destination 'generic/platform=iOS' -allowProvisioningUpdates` (signing
uses the user's team; this may register the bundle ID, so it needs the user's go-ahead).

**Check:** a card appears on the Lock Screen with the app closed; different cards arrive on repeats.

## Stage 7 · Handover

Write `LIVE_ACTIVITY.md` in the app repo: where each part lives, how to edit cards
(`references/config-fields.md`), how to pause (`cron.startEnabled: false`), expiry dates (GitHub
token, APNs key, GitHub API version 2022-11-28 sunsets March 2028), App Store notes (Live Activities
arrive by push; privacy answers for push tokens).

## Reporting

End with a short table: each stage, done / waiting for the user / failed, and the user's remaining
steps. Point out anything from `references/snags.md` you hit.

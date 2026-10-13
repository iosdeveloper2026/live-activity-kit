# Known snags (from the first build) and what to do

| Symptom | Cause | Fix |
|---|---|---|
| Signing: bundle ID "not available" | Another team owns it | Stop and ask for a unique ID; update Firebase, App Group and widget ID together |
| Signing: "No Accounts" | Xcode not signed in | User step: Xcode → Settings → Accounts |
| Compose app crashes at launch | Missing `CADisableMinimumFrameDurationOnPhone` | Add it to the app Info.plist |
| No FCM token in a SwiftUI app | No app delegate, so Firebase never gets the APNs token | The kit hooks it (`APNsTokenHook`); make sure `LiveActivityKit.start()` runs |
| "already configured" crash | `LiveActivityKit.start()` placed before `FirebaseApp.configure()` | `insert_start_line.py` puts it after; check by hand if edited |
| Card shows black instead of image | Image not downloaded yet | Open the app once after changing images |
| Card layout unexpected | Field inherited from the top level | Set `titlePosition`/`showTimer` on each card |
| Image cropped badly | Not wide enough for ~3:1 | Use `w=1100&h=360&fit=crop` (or `&crop=entropy`) |
| Timer shows `29:--` on the Lock Screen | iOS hides seconds there | Normal; not a bug |
| Timer restarts before reaching zero | `REPEAT_EVERY_MINUTES` shorter than the timer | Raise the repeat interval |
| FCM `THIRD_PARTY_AUTH_ERROR` / "Invalid APNs credential" | APNs key not uploaded for this Firebase app | User step: upload the .p8 in both rows |
| FCM `400 INVALID_ARGUMENT` for a simulator | Simulator token not accepted | Test pushes on a real iPhone; don't delete the token |
| Cron runs hours late | GitHub's schedule is best-effort | cron-job.org triggers it every 5 minutes |
| cron-job.org 4xx | Wrong token permission or Content-Type | Actions: Read and write; Content-Type `application/json` |
| `firebase-admin` crash in Actions | Needs Node 22; Firestore client is optional | The template pins Node 22 and installs `@google-cloud/firestore` |
| `git push` 403 as another user | Mac keychain holds another GitHub account | `git config --local credential.helper '!gh auth git-credential'` |
| Cron sends to the wrong app | Several apps share one Firebase project | Set `APP_BUNDLE_ID` in the app's cron repo |
| iPhone "unavailable" | Locked, Wi-Fi only, or not trusted | Cable, unlock, Trust, keep unlocked |
| Card vanishes 10–40 s after starting | User dismissed it | Explain; the next repeat starts a new one |
| iOS 18 API fails to build | Deployment target is iOS 17 | Build against the minimum iOS version |
| "Multiple commands produce …/Info.plist" | A new Info.plist inside an Xcode 16 synchronized folder | `add_kit.rb` writes it next to the project; move it there if added by hand |
| Preview card didn't start on the very first launch | First-launch timing (seen once with a Compose app) | Relaunch with `-LiveActivityPreview n`; it works on the next launch |
| Cron sends the wrong Live Activity type | App has its own Live Activity and the kit in one Firebase project | Kit 1.1.0+ labels records; cron skips other types |
| Build fails: duplicate Firebase symbols | App gets Firebase from CocoaPods | Move Firebase to SPM 12.19.2+ before adding the kit |

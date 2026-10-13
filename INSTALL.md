# Installing LiveActivityKit in an iOS app

Adds a remote-controlled Live Activity to an existing app **without any new screens**. The app's own
code changes by one line. Live Activities are started by the cron through push-to-start (iOS 17.2+).

Placeholders: `<bundle-id>` is the app's bundle ID, e.g. `com.example.shop`.

## 1. Add the package

Xcode → File → Add Package Dependencies → this repo's `ios` folder (or its Git URL).

| Product | Add to |
|---|---|
| `LiveActivityKit` | the app target |
| `LiveActivityKitWidget` | the widget extension target (step 2) |

## 2. Add a Widget Extension

File → New → Target → Widget Extension, name it e.g. `LiveActivityWidget`, untick "Include
Configuration App Intent". Replace its generated files with one file:

```swift
import LiveActivityKitWidget
import SwiftUI
import WidgetKit

@main
struct AppWidgets: WidgetBundle {
    var body: some Widget {
        LiveActivityKitWidget()
    }
}
```

If the app already has a widget extension, add `LiveActivityKitWidget()` to its existing bundle instead.

## 3. Capabilities and Info.plist

| Target | Setting |
|---|---|
| App | App Groups: `group.<bundle-id>` |
| App | Push Notifications |
| App | Background Modes: Remote notifications (`UIBackgroundModes` = `remote-notification`) |
| App | Info.plist `NSSupportsLiveActivities` = YES |
| App and widget | Info.plist `LiveActivityAppGroup` = `group.<bundle-id>` |
| Widget | App Groups: `group.<bundle-id>` |

The bundle ID must be registered to your team. If Xcode says it's unavailable, pick a unique one.

## 4. The one line

SwiftUI:

```swift
import FirebaseCore
import LiveActivityKit

@main
struct MyApp: App {
    init() {
        FirebaseApp.configure()     // skip if the app already does this
        LiveActivityKit.start()     // ← the only line added to the app's code
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

UIKit: call `LiveActivityKit.start()` in `application(_:didFinishLaunchingWithOptions:)`.

If the app turns Firebase swizzling off (`FirebaseAppDelegateProxyEnabled` = NO), also forward the
APNs token: `LiveActivityKit.setAPNSToken(deviceToken)`.

## 5. Firebase

1. Register the iOS app and add its `GoogleService-Info.plist` to the app target.
2. Publish `live_activity_config` (see `examples/` and `schema/`) to Remote Config.
3. Deploy `firebase/firestore.rules` to Firestore.
4. Upload the APNs key (.p8) under Cloud Messaging, for development and production.

## 6. Cron

Create a repo from the `live-activity-cron` template, add the `FIREBASE_SERVICE_ACCOUNT` secret,
and set the repo variable `ATTRIBUTES_TYPE` = `LiveActivityAttributes`.

## Preview without the cron

Debug builds accept a launch argument that starts a sample card locally:

```
-LiveActivityPreview 2    # card 2 from contents
```

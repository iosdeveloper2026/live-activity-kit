import ActivityKit
import FirebaseCore
import FirebaseMessaging
import FirebaseRemoteConfig
import Foundation
import LiveActivityKitShared
import os
import UIKit

enum Log {
    static let kit = Logger(subsystem: "LiveActivityKit", category: "LiveActivityKit")
}

/// Headless Live Activity runtime. The app adds no screens; it calls `start()` once at launch:
///
///     FirebaseApp.configure()
///     LiveActivityKit.start()
///
/// In the background it then:
/// - saves the FCM token and the push-to-start token to Firestore (for the cron),
/// - fetches `live_activity_config` from Remote Config and downloads every card's images,
/// - tracks Live Activities the cron starts remotely and saves their update tokens.
///
/// Live Activities are only ever started by the cron (push-to-start, iOS 17.2+). On older iOS
/// versions the kit does nothing. Debug builds also accept the launch argument
/// `-LiveActivityPreview [card number]`, which starts a sample card locally for previews.
@MainActor
public enum LiveActivityKit {
    public struct Options {
        /// Remote Config parameter holding the JSON config.
        public var remoteConfigKey = "live_activity_config"
        /// Firestore collection the cron reads tokens from.
        public var tokensCollection = "liveActivityDevices"
        /// Register for remote notifications (no permission prompt). Turn off if the app already does.
        public var registerForRemoteNotifications = true

        public init() {}
    }

    /// Typed as `AnyObject` because `Runtime` needs iOS 17.2 and the package supports iOS 17.
    private static var runtime: AnyObject?

    /// Starts the kit. Call once at launch, after `FirebaseApp.configure()`.
    public static func start(_ options: Options = Options()) {
        guard runtime == nil else { return }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        guard #available(iOS 17.2, *) else {
            Log.kit.info("LiveActivityKit needs iOS 17.2 for remote start; doing nothing")
            return
        }
        let runtime = Runtime(options: options)
        self.runtime = runtime
        runtime.start()
    }

    /// For apps with Firebase method swizzling turned off: forward the APNs device token here
    /// from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    public static func setAPNSToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

@available(iOS 17.2, *)
@MainActor
private final class Runtime {
    private let options: LiveActivityKit.Options
    private let tokens: TokenStore
    private var config: LiveActivityConfig?
    private var trackedActivityIds = Set<String>()
    private var observers: [NSObjectProtocol] = []

    init(options: LiveActivityKit.Options) {
        self.options = options
        self.tokens = TokenStore(collection: options.tokensCollection)
    }

    func start() {
        // Push tokens: FCM token (for the FCM message) and push-to-start token (Live Activity).
        // Wait one run-loop turn so the app delegate exists, hook the APNs token callback, then
        // register. The FCM token arrives through the refresh notification below.
        DispatchQueue.main.async { [options] in
            APNsTokenHook.install()
            if options.registerForRemoteNotifications {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        refreshFCMToken()
        observers.append(NotificationCenter.default.addObserver(
            forName: .MessagingRegistrationTokenRefreshed, object: nil, queue: .main
        ) { [weak self] note in
            let token = note.object as? String
            Task { @MainActor in
                if let token { self?.tokens.setFCMToken(token) } else { self?.refreshFCMToken() }
            }
        })
        Task {
            for await token in Activity<LiveActivityAttributes>.pushToStartTokenUpdates {
                tokens.setStartToken(token)
            }
        }

        // Activities started remotely by the cron (or still running from earlier).
        for existing in Activity<LiveActivityAttributes>.activities { track(existing) }
        Task {
            for await activity in Activity<LiveActivityAttributes>.activityUpdates { track(activity) }
        }

        // Content: at launch and every time the app returns to the foreground.
        Task { await syncContent(thenPreview: true) }
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.syncContent(thenPreview: false) }
        })
    }

    // MARK: - Tokens

    private func refreshFCMToken() {
        Messaging.messaging().token { [weak self] token, error in
            if let error { Log.kit.info("FCM token not ready yet: \(error.localizedDescription)") }
            guard let token else { return }
            Task { @MainActor in self?.tokens.setFCMToken(token) }
        }
    }

    private func track(_ activity: Activity<LiveActivityAttributes>) {
        guard trackedActivityIds.insert(activity.id).inserted else { return }
        tokens.setActivity(.init(
            activityId: activity.id,
            pushToken: activity.pushToken?.hexString,
            orderNumber: activity.attributes.orderNumber,
            stageIndex: activity.content.state.stageIndex,
            startedAt: .now,
            status: "active"
        ))
        Task {
            for await token in activity.pushTokenUpdates {
                tokens.updateActivity(id: activity.id) { $0.pushToken = token.hexString }
            }
        }
        Task {
            for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
                tokens.updateActivity(id: activity.id) { $0.status = "ended" }
                break
            }
        }
    }

    // MARK: - Content

    /// Fetches the config and downloads every card's images, so cards the cron sends later
    /// can show them (the widget only reads images already on the phone).
    private func syncContent(thenPreview: Bool) async {
        let remoteConfig = RemoteConfig.remoteConfig()
        #if DEBUG
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 0
        remoteConfig.configSettings = settings
        #endif
        do {
            _ = try await remoteConfig.fetchAndActivate()
        } catch {
            Log.kit.error("Remote Config fetch failed: \(error.localizedDescription)")
        }
        let raw = remoteConfig.configValue(forKey: options.remoteConfigKey).dataValue
        if !raw.isEmpty {
            do {
                config = try JSONDecoder().decode(LiveActivityConfig.self, from: raw)
            } catch {
                Log.kit.error("\(self.options.remoteConfigKey) is not valid JSON for the kit: \(error.localizedDescription)")
            }
        }
        guard let config else { return }
        for (image, banner) in config.allImages {
            _ = await ImageStore.file(for: image, size: .thumbnail)
            _ = await ImageStore.file(for: banner, size: .banner)
        }
        Log.kit.info("Content synced: \(config.contents.count) card(s)")

        #if DEBUG
        if thenPreview { await startDebugPreviewIfRequested(config) }
        #endif
    }

    #if DEBUG
    /// `-LiveActivityPreview [card number]`: starts a sample card locally, for simulator screenshots.
    /// Compiled out of release builds.
    private func startDebugPreviewIfRequested(_ config: LiveActivityConfig) async {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-LiveActivityPreview") else { return }
        let card = args.indices.contains(flag + 1) ? Int(args[flag + 1]).map { $0 - 1 } : nil
        let resolved = config.withContent(card ?? (config.contents.isEmpty ? nil : 0))
        let banner = resolved.bannerImageUrl.isEmpty ? resolved.imageUrl : resolved.bannerImageUrl
        let state = resolved.contentState(
            stageIndex: 0,
            orderNumber: "#PREVIEW",
            imageFile: await ImageStore.file(for: resolved.imageUrl, size: .thumbnail),
            bannerFile: await ImageStore.file(for: banner, size: .banner)
        )
        for old in Activity<LiveActivityAttributes>.activities { await old.end(nil, dismissalPolicy: .immediate) }
        do {
            _ = try Activity.request(
                attributes: LiveActivityAttributes(orderNumber: "#PREVIEW"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: .token
            )
            Log.kit.info("Debug preview started (card \(card.map { $0 + 1 } ?? 1))")
        } catch {
            Log.kit.error("Debug preview failed: \(error.localizedDescription)")
        }
    }
    #endif
}

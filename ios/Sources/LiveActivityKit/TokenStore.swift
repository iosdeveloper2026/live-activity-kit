import FirebaseCore
import Foundation

/// Saves this install's push tokens to Firestore (`liveActivityDevices/{installId}`), where the
/// cron reads them to send Live Activity pushes through FCM.
///
/// Uses the Firestore REST API instead of the Firestore SDK, to keep the kit light. The security
/// rules in `firebase/firestore.rules` only allow writing these fields; nobody can read them from the app.
@MainActor
final class TokenStore {
    struct ActivityInfo {
        var activityId: String
        var pushToken: String?
        var orderNumber: String
        var stageIndex: Int
        var startedAt: Date
        var status: String // "active" | "ended"
    }

    private let collection: String
    private(set) var fcmToken: String?
    private var startToken: String?
    private var activity: ActivityInfo?
    private var pendingSave: Task<Void, Never>?

    init(collection: String) {
        self.collection = collection
    }

    /// Random per-install ID; reset when the app is reinstalled.
    private let installId: String = {
        let key = "LiveActivityKit.installId"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    func setFCMToken(_ token: String?) {
        guard token != fcmToken else { return }
        fcmToken = token
        scheduleSave()
    }

    func setStartToken(_ token: Data) {
        let hex = token.hexString
        guard hex != startToken else { return }
        startToken = hex
        scheduleSave()
    }

    func setActivity(_ info: ActivityInfo) {
        activity = info
        scheduleSave()
    }

    func updateActivity(id: String, _ change: (inout ActivityInfo) -> Void) {
        guard var current = activity, current.activityId == id else { return }
        change(&current)
        activity = current
        scheduleSave()
    }

    /// Coalesces bursts of token updates into one write.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    private func save() async {
        // The security rules require an FCM token, and the cron can't send without one.
        guard let fcmToken, let options = FirebaseApp.app()?.options, let projectId = options.projectID else { return }

        var fields: [String: Any] = [
            "fcmToken": ["stringValue": fcmToken],
            "platform": ["stringValue": "IOS"],
            // Lets one Firebase project serve several apps: each app's cron only sends to its own devices.
            "bundleId": ["stringValue": Bundle.main.bundleIdentifier ?? ""],
            "appVersion": ["stringValue": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""],
            "updatedAt": ["timestampValue": ISO8601DateFormatter().string(from: .now)],
        ]
        if let startToken { fields["startToken"] = ["stringValue": startToken] }
        if let activity {
            var activityFields: [String: Any] = [
                "activityId": ["stringValue": activity.activityId],
                "orderNumber": ["stringValue": activity.orderNumber],
                "stageIndex": ["integerValue": String(activity.stageIndex)],
                "startedAt": ["integerValue": String(Int(activity.startedAt.timeIntervalSince1970))],
                "status": ["stringValue": activity.status],
            ]
            if let pushToken = activity.pushToken { activityFields["pushToken"] = ["stringValue": pushToken] }
            fields["activity"] = ["mapValue": ["fields": activityFields]]
        }

        let path = "projects/\(projectId)/databases/(default)/documents/\(collection)/\(installId)"
        guard let url = URL(string: "https://firestore.googleapis.com/v1/\(path)?key=\(options.apiKey ?? "")") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH" // replaces the whole document
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": fields])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                Log.kit.info("Saved push tokens (start: \(self.startToken != nil), activity: \(self.activity?.pushToken != nil))")
            } else {
                Log.kit.error("Saving push tokens failed: HTTP \(status)")
            }
        } catch {
            Log.kit.error("Saving push tokens failed: \(error.localizedDescription)")
        }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

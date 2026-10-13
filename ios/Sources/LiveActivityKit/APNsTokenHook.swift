import FirebaseMessaging
import ObjectiveC
import UIKit

/// Forwards the APNs device token to Firebase Messaging without the app having to implement
/// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
///
/// Firebase's own swizzling misses SwiftUI apps that have no app delegate (it runs before the
/// delegate exists), so no FCM token is ever created. This hook is installed after launch, adds
/// the callback to whatever delegate the app has (SwiftUI provides one), and keeps calling any
/// existing implementation.
@MainActor
enum APNsTokenHook {
    private static var installed = false

    static func install() {
        guard !installed, let delegate = UIApplication.shared.delegate else { return }
        installed = true

        let cls: AnyClass = type(of: delegate)
        let selector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        typealias Callback = @convention(c) (AnyObject, Selector, UIApplication, Data) -> Void

        if let method = class_getInstanceMethod(cls, selector) {
            // The app already handles it: run ours, then the original.
            let original = unsafeBitCast(method_getImplementation(method), to: Callback.self)
            let block: @convention(block) (AnyObject, UIApplication, Data) -> Void = { object, application, token in
                Messaging.messaging().apnsToken = token
                original(object, selector, application, token)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        } else {
            let block: @convention(block) (AnyObject, UIApplication, Data) -> Void = { _, _, token in
                Messaging.messaging().apnsToken = token
            }
            class_addMethod(cls, selector, imp_implementationWithBlock(block), "v@:@@")
        }
    }
}

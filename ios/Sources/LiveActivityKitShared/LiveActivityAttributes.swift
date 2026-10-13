import ActivityKit
import Foundation
import SwiftUI

/// The Live Activity type shared by the app and the widget extension.
/// Every visible field lives in `ContentState`, so pushes from the cron can change any of it.
/// The JSON keys must match what the cron sends (`attributes-type: "LiveActivityAttributes"`).
public struct LiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var brandName: String
        public var title: String
        public var subtitle: String
        /// Downloaded image file names inside the App Group container (widgets can't load URLs).
        public var imageFile: String?
        public var imageStyle: String?
        public var bannerFile: String?
        public var symbol: String
        public var accentColor: String
        public var stageIndex: Int
        public var stageCount: Int
        public var stageTitle: String
        public var statusText: String
        public var stageSymbol: String
        /// Swift `Date` encodes as seconds since 2001-01-01; the cron converts for this.
        public var eta: Date
        public var progress: Double
        public var isFinal: Bool
        public var showStages: Bool?
        public var titlePosition: String?
        public var showTimer: Bool?

        public init(
            brandName: String, title: String, subtitle: String, imageFile: String?, imageStyle: String?,
            bannerFile: String?, symbol: String, accentColor: String, stageIndex: Int, stageCount: Int,
            stageTitle: String, statusText: String, stageSymbol: String, eta: Date, progress: Double,
            isFinal: Bool, showStages: Bool?, titlePosition: String?, showTimer: Bool?
        ) {
            self.brandName = brandName; self.title = title; self.subtitle = subtitle
            self.imageFile = imageFile; self.imageStyle = imageStyle; self.bannerFile = bannerFile
            self.symbol = symbol; self.accentColor = accentColor
            self.stageIndex = stageIndex; self.stageCount = stageCount
            self.stageTitle = stageTitle; self.statusText = statusText; self.stageSymbol = stageSymbol
            self.eta = eta; self.progress = progress; self.isFinal = isFinal
            self.showStages = showStages; self.titlePosition = titlePosition; self.showTimer = showTimer
        }
    }

    /// A reference shown nowhere by default; the cron fills it (e.g. "#2136").
    public var orderNumber: String

    public init(orderNumber: String) { self.orderNumber = orderNumber }
}

public extension LiveActivityAttributes.ContentState {
    var usesLargeImage: Bool { imageStyle == "large" && bannerFile != nil }
    var displaysStages: Bool { showStages ?? true }
    var titleBelowImage: Bool { !displaysStages && titlePosition != "overlay" }
    var displaysTimer: Bool { displaysStages || (showTimer ?? false) }
}

/// App Group shared by the app and the widget. Set `LiveActivityAppGroup` in both Info.plists;
/// without it, `group.<app bundle id>` is assumed.
public enum LiveActivityAppGroup {
    public static var id: String {
        if let id = Bundle.main.object(forInfoDictionaryKey: "LiveActivityAppGroup") as? String, !id.isEmpty {
            return id
        }
        var bundleId = Bundle.main.bundleIdentifier ?? ""
        // In the widget extension, drop the extension's own suffix to get the app's bundle ID.
        if Bundle.main.bundlePath.hasSuffix(".appex"), let dot = bundleId.lastIndex(of: ".") {
            bundleId = String(bundleId[..<dot])
        }
        return "group." + bundleId
    }

    public static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}

public extension Color {
    /// `#RRGGBB` or `#AARRGGBB`.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let a, r, g, b: UInt64
        switch hex.count {
        case 8: (a, r, g, b) = (value >> 24 & 0xFF, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default: (a, r, g, b) = (0xFF, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

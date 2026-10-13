import Foundation
import LiveActivityKitShared
import UIKit

/// Downloads remote images into the App Group container so the widget extension can show them
/// (widgets can't load URLs). File names are derived from the URL exactly like the cron does,
/// so pushes can refer to images the app downloaded earlier.
enum ImageStore {
    enum Size: String {
        /// Square thumbnail beside the title.
        case thumbnail
        /// Full-width banner across the top.
        case banner

        var maxPixels: CGSize {
            switch self {
            case .thumbnail: CGSize(width: 160, height: 160)
            case .banner: CGSize(width: 900, height: 300)
            }
        }
    }

    /// The image's file name if it has already been downloaded.
    static func cachedFile(for urlString: String, size: Size) -> String? {
        guard let (name, destination) = location(for: urlString, size: size) else { return nil }
        return FileManager.default.fileExists(atPath: destination.path) ? name : nil
    }

    static func file(for urlString: String, size: Size) async -> String? {
        guard let url = URL(string: urlString), let (name, destination) = location(for: urlString, size: size) else { return nil }
        if FileManager.default.fileExists(atPath: destination.path) { return name }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Live Activity images must stay small, so downscale (keeping the aspect ratio).
            guard let image = UIImage(data: data) else { return nil }
            let scale = min(1, size.maxPixels.width / image.size.width, size.maxPixels.height / image.size.height)
            let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            guard let jpeg = image.preparingThumbnail(of: target)?.jpegData(compressionQuality: 0.85) else { return nil }
            try jpeg.write(to: destination, options: .atomic)
            return name
        } catch {
            Log.kit.error("Image download failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Stable name: djb2 over the URL bytes (Swift's `hashValue` is randomized per launch).
    /// Must match `imageFileName` in the cron script.
    private static func location(for urlString: String, size: Size) -> (String, URL)? {
        guard !urlString.isEmpty, let dir = LiveActivityAppGroup.container else { return nil }
        let hash = urlString.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }
        let name = "la-\(size.rawValue)-" + String(hash, radix: 16) + ".jpg"
        return (name, dir.appendingPathComponent(name))
    }
}

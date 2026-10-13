import Foundation
import LiveActivityKitShared

/// The `live_activity_config` Remote Config parameter. Every field is optional in the JSON;
/// missing fields fall back to the defaults below. See `schema/live_activity_config.schema.json`.
struct LiveActivityConfig: Decodable {
    var brandName = ""
    var title = ""
    var subtitle = ""
    var imageUrl = ""
    var imageStyle = "small"
    var bannerImageUrl = ""
    var symbol = "bag.fill"
    var accentColor = "#FF6B35"
    var recipientName = ""
    var showStages = true
    var titlePosition = "below"
    var showTimer = false
    var timerMinutes = 0
    var stages: [StageConfig] = []
    var contents: [ContentItem] = []
    var rotation = "sequential"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        brandName = try value(.brandName, brandName)
        title = try value(.title, title)
        subtitle = try value(.subtitle, subtitle)
        imageUrl = try value(.imageUrl, imageUrl)
        imageStyle = try value(.imageStyle, imageStyle)
        bannerImageUrl = try value(.bannerImageUrl, bannerImageUrl)
        symbol = try value(.symbol, symbol)
        accentColor = try value(.accentColor, accentColor)
        recipientName = try value(.recipientName, recipientName)
        showStages = try value(.showStages, showStages)
        titlePosition = try value(.titlePosition, titlePosition)
        showTimer = try value(.showTimer, showTimer)
        timerMinutes = try value(.timerMinutes, timerMinutes)
        stages = try value(.stages, stages)
        contents = try value(.contents, contents)
        rotation = try value(.rotation, rotation)
    }

    private enum CodingKeys: String, CodingKey {
        case brandName, title, subtitle, imageUrl, imageStyle, bannerImageUrl, symbol, accentColor
        case recipientName, showStages, titlePosition, showTimer, timerMinutes, stages, contents, rotation
    }

    // MARK: - Rotation (same rules as the cron)

    /// This config with `contents[index]` applied on top; unchanged when there are no items.
    func withContent(_ index: Int?) -> LiveActivityConfig {
        guard let index, contents.indices.contains(index) else { return self }
        let item = contents[index]
        var c = self
        c.brandName = item.brandName ?? brandName
        c.title = item.title ?? title
        c.subtitle = item.subtitle ?? subtitle
        c.imageUrl = item.imageUrl ?? imageUrl
        c.bannerImageUrl = item.bannerImageUrl ?? bannerImageUrl
        c.imageStyle = item.imageStyle ?? imageStyle
        c.symbol = item.symbol ?? symbol
        c.accentColor = item.accentColor ?? accentColor
        c.showStages = item.showStages ?? showStages
        c.titlePosition = item.titlePosition ?? titlePosition
        c.showTimer = item.showTimer ?? showTimer
        c.timerMinutes = item.timerMinutes ?? timerMinutes
        return c
    }

    /// Every (thumbnail, banner) image any card can show, so they can all be downloaded ahead.
    var allImages: [(image: String, banner: String)] {
        ([nil] + contents.indices.map { Optional($0) }).map { i in
            let c = withContent(i)
            return (c.imageUrl, c.bannerImageUrl.isEmpty ? c.imageUrl : c.bannerImageUrl)
        }
    }

    // MARK: - Content state (same rules as the cron's contentState)

    private var effectiveStages: [StageConfig] {
        stages.isEmpty ? [StageConfig(title: "", status: "", etaMinutes: 0, symbol: nil)] : stages
    }

    private var displaysStages: Bool { showStages && !stages.isEmpty }

    func contentState(
        stageIndex: Int, orderNumber: String, imageFile: String?, bannerFile: String?, now: Date = .now
    ) -> LiveActivityAttributes.ContentState {
        let all = effectiveStages
        let index = min(max(stageIndex, 0), all.count - 1)
        let stage = all[index]
        func fill(_ s: String) -> String {
            s.replacingOccurrences(of: "{order}", with: orderNumber)
                .replacingOccurrences(of: "{name}", with: recipientName)
        }
        let etaMinutes = !showStages && showTimer ? timerMinutes : stage.etaMinutes
        return LiveActivityAttributes.ContentState(
            brandName: fill(brandName),
            title: fill(title),
            subtitle: fill(subtitle),
            imageFile: imageFile,
            imageStyle: imageStyle,
            bannerFile: bannerFile,
            symbol: symbol,
            accentColor: accentColor,
            stageIndex: index,
            stageCount: all.count,
            stageTitle: fill(stage.title),
            statusText: fill(stage.status),
            stageSymbol: (stage.symbol?.isEmpty == false ? stage.symbol : nil) ?? symbol,
            eta: now.addingTimeInterval(TimeInterval(etaMinutes * 60)),
            progress: all.count > 1 ? Double(index) / Double(all.count - 1) : 1,
            isFinal: index == all.count - 1,
            showStages: displaysStages,
            titlePosition: titlePosition,
            showTimer: !displaysStages && showTimer
        )
    }
}

/// One card in `contents`. Nil fields fall back to the top-level value.
struct ContentItem: Decodable {
    var brandName: String?
    var title: String?
    var subtitle: String?
    var imageUrl: String?
    var bannerImageUrl: String?
    var imageStyle: String?
    var symbol: String?
    var accentColor: String?
    var showStages: Bool?
    var titlePosition: String?
    var showTimer: Bool?
    var timerMinutes: Int?
}

struct StageConfig: Decodable {
    var title: String
    var status: String
    var etaMinutes: Int
    var symbol: String?
}

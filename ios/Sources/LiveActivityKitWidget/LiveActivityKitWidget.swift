import ActivityKit
import LiveActivityKitShared
import SwiftUI
import WidgetKit

/// The Live Activity widget. Add it to your widget extension's bundle:
///
///     @main
///     struct AppWidgets: WidgetBundle {
///         var body: some Widget { LiveActivityKitWidget() }
///     }
///
/// Every layout is driven by the pushed `ContentState`, which the cron builds from the
/// `live_activity_config` Remote Config parameter.
public struct LiveActivityKitWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let accent = Color(hex: state.accentColor)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Thumbnail(state: state, size: 52)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.displaysTimer {
                        EtaView(state: state, font: .title2)
                            .foregroundStyle(accent)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title).font(.headline).lineLimit(state.displaysStages ? 1 : 2)
                        if !state.subtitle.isEmpty {
                            Text(state.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.displaysStages {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(state.stageTitle, systemImage: state.stageSymbol)
                                .font(.subheadline.bold())
                                .foregroundStyle(accent)
                            Text(state.statusText).font(.caption).foregroundStyle(.secondary)
                            StageProgress(state: state, accent: accent)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                if state.displaysStages {
                    Image(systemName: state.stageSymbol)
                        .foregroundStyle(accent)
                } else {
                    Thumbnail(state: state, size: 24)
                }
            } compactTrailing: {
                if state.displaysStages {
                    EtaView(state: state, font: .caption.bold())
                        .foregroundStyle(accent)
                        .frame(maxWidth: 44)
                } else if state.displaysTimer {
                    EtaView(state: state, font: .caption.bold(), showsHours: true)
                        .frame(maxWidth: 52)
                } else {
                    Text(state.title)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .frame(maxWidth: 64)
                }
            } minimal: {
                if state.displaysStages {
                    Image(systemName: state.stageSymbol)
                        .foregroundStyle(accent)
                } else {
                    Thumbnail(state: state, size: 22)
                }
            }
            .keylineTint(accent)
        }
    }
}

// MARK: - Lock Screen / banner

private struct LockScreenView: View {
    let state: LiveActivityAttributes.ContentState

    var body: some View {
        if state.usesLargeImage {
            LargeImageLayout(state: state)
        } else {
            SmallImageLayout(state: state)
        }
    }
}

/// `imageStyle: "small"` — square thumbnail beside the title.
private struct SmallImageLayout: View {
    let state: LiveActivityAttributes.ContentState

    var body: some View {
        let accent = Color(hex: state.accentColor)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Thumbnail(state: state, size: state.displaysStages ? 48 : 64)
                TitleBlock(state: state)
                Spacer(minLength: 0)
                if state.displaysStages {
                    EtaView(state: state, font: .title3)
                        .foregroundStyle(accent)
                }
            }
            if state.displaysStages {
                HStack(spacing: 6) {
                    Image(systemName: state.stageSymbol).foregroundStyle(accent)
                    Text(state.stageTitle).font(.subheadline.bold()).foregroundStyle(.white)
                }
                Text(state.statusText).font(.caption).foregroundStyle(.white.opacity(0.75))
                StageProgress(state: state, accent: accent)
            }
        }
        .padding(16)
    }
}

/// `imageStyle: "large"` — full-width banner on top with the title over it.
/// Lock Screen Live Activities are capped at 160pt tall, so the banner is 92pt.
private struct LargeImageLayout: View {
    let state: LiveActivityAttributes.ContentState

    var body: some View {
        if state.titleBelowImage {
            ImageThenTitle(state: state)
        } else {
            overlayLayout
        }
    }

    /// Title over the image (`titlePosition: "overlay"`, or whenever stages are shown).
    private var overlayLayout: some View {
        let accent = Color(hex: state.accentColor)
        return VStack(spacing: 0) {
            // Fixed-height box; the image fills it without growing it, then text sits on top.
            // Without stages the banner takes the whole Live Activity (max 160pt tall).
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: state.displaysStages ? 92 : 150)
                .overlay { BannerImage(file: state.bannerFile) }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .bottom) {
                        TitleBlock(state: state)
                        Spacer(minLength: 8)
                        if state.displaysTimer {
                            EtaView(state: state, font: .title3.bold(), showsHours: true)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .clipped()

            if state.displaysStages {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: state.stageSymbol).foregroundStyle(accent)
                        Text(state.stageTitle).font(.subheadline.bold()).foregroundStyle(.white)
                        Text(state.statusText).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                    StageProgress(state: state, accent: accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }
}

/// `showStages: false` + `titlePosition: "below"`: full-width image, then title and subtitle.
/// Lock Screen Live Activities are capped at 160pt tall, so the image is 110pt (filled and
/// cropped evenly top/bottom) and the brand sits on the image as a small tag to save space.
private struct ImageThenTitle: View {
    let state: LiveActivityAttributes.ContentState

    /// Empty title and subtitle: no text area, the image fills the whole card.
    private var hasText: Bool { !state.title.isEmpty || !state.subtitle.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: hasText ? 110 : 160)
                .overlay { BannerImage(file: state.bannerFile) }
                .overlay(alignment: .topLeading) {
                    if !state.brandName.isEmpty {
                        Text(state.brandName.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if state.displaysTimer {
                        TimerPill(state: state)
                            .padding(10)
                    }
                }
                .clipped()
            if hasText {
                VStack(alignment: .leading, spacing: 1) {
                    if !state.title.isEmpty {
                        Text(state.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    }
                    if !state.subtitle.isEmpty {
                        Text(state.subtitle).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

/// Countdown pill for the image card: clock icon + rounded monospaced time on a frosted dark capsule.
private struct TimerPill: View {
    let state: LiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: state.accentColor))
                .brightness(0.3) // lift dark accent colours so the icon reads on the dark pill
            EtaView(state: state, font: .system(.subheadline, design: .rounded).weight(.semibold), showsHours: true)
                .foregroundStyle(.white)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.6), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
    }
}

private struct TitleBlock: View {
    let state: LiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.brandName.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(Color(hex: state.accentColor))
            Text(state.title).font(.headline).foregroundStyle(.white).lineLimit(1)
            if !state.subtitle.isEmpty {
                Text(state.subtitle).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
        }
    }
}

// MARK: - Pieces

private struct Thumbnail: View {
    let state: LiveActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Group {
            if let file = state.imageFile,
               let url = LiveActivityAppGroup.container?.appendingPathComponent(file),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: state.symbol)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: state.accentColor))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

private struct EtaView: View {
    let state: LiveActivityAttributes.ContentState
    let font: Font
    /// Long timers (an hour or more) read better as 1:05:00 than 65:00.
    var showsHours = false

    var body: some View {
        Group {
            if (state.displaysStages && state.isFinal) || state.eta <= .now {
                Image(systemName: "checkmark.circle.fill")
            } else {
                // Timer text is greedy about width; cap it so titles don't get truncated.
                Text(timerInterval: Date.now...state.eta, countsDown: true, showsHours: showsHours)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 64, alignment: .trailing)
            }
        }
        .font(font)
    }
}

private struct BannerImage: View {
    let file: String?
    /// `true`: show the whole image (letterboxed); `false`: fill and crop.
    var fit = false

    var body: some View {
        if let file,
           let url = LiveActivityAppGroup.container?.appendingPathComponent(file),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: fit ? .fit : .fill)
        } else {
            Color.black
        }
    }
}

/// Segmented bar: one segment per stage.
private struct StageProgress: View {
    let state: LiveActivityAttributes.ContentState
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(state.stageCount, 1), id: \.self) { i in
                Capsule()
                    .fill(i <= state.stageIndex ? accent : Color.white.opacity(0.2))
                    .frame(height: 5)
            }
        }
    }
}

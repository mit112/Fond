import AppIntents
import WidgetKit
import SwiftUI

struct FondEntry: TimelineEntry {
    let date: Date
    let partnerName: String?
    let status: UserStatus?
    let message: String?
    let lastUpdated: Date?
    let connectionState: ConnectionState
    let promptText: String?
    let myPromptAnswer: String?
    let partnerPromptAnswer: String?

    var sharedWords: String? {
        let candidate = partnerPromptAnswer ?? message
        guard let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text != "💛" else { return nil }
        return text
    }

    var isStale: Bool {
        guard let lastUpdated else { return false }
        return date.timeIntervalSince(lastUpdated) > 3_600
    }

    static var placeholder: FondEntry {
        FondEntry(
            date: .now,
            partnerName: "Maya",
            status: .available,
            message: "I saved you the window seat.",
            lastUpdated: Date().addingTimeInterval(-360),
            connectionState: .connected,
            promptText: "What's a song that reminds you of us?",
            myPromptAnswer: nil,
            partnerPromptAnswer: nil
        )
    }

    static var stale: FondEntry {
        FondEntry(
            date: .now,
            partnerName: "Maya",
            status: .sleeping,
            message: "Call me when you wake up.",
            lastUpdated: Date().addingTimeInterval(-7_200),
            connectionState: .connected,
            promptText: nil,
            myPromptAnswer: nil,
            partnerPromptAnswer: nil
        )
    }

    static var missingMessage: FondEntry {
        FondEntry(
            date: .now,
            partnerName: "Maya",
            status: .busy,
            message: nil,
            lastUpdated: Date().addingTimeInterval(-540),
            connectionState: .connected,
            promptText: nil,
            myPromptAnswer: nil,
            partnerPromptAnswer: nil
        )
    }

    static var notConnected: FondEntry {
        FondEntry(
            date: .now,
            partnerName: nil,
            status: nil,
            message: nil,
            lastUpdated: nil,
            connectionState: .unpaired,
            promptText: nil,
            myPromptAnswer: nil,
            partnerPromptAnswer: nil
        )
    }
}

struct FondTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = FondWidgetConfigIntent

    func placeholder(in context: Context) -> FondEntry { .placeholder }

    func snapshot(for configuration: Intent, in context: Context) async -> FondEntry {
        readEntry()
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<FondEntry> {
        let entry = readEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    func relevance() async -> WidgetRelevance<Intent> {
        var attributes: [WidgetRelevanceAttribute<Intent>] = []
        let config = FondWidgetConfigIntent()

        if let defaults = UserDefaults(suiteName: FondConstants.appGroupID),
           let lastUpdated = defaults.object(forKey: FondConstants.partnerLastUpdatedKey) as? Date {
            let boostEnd = lastUpdated.addingTimeInterval(
                Double(FondConstants.relevancePartnerBoostMinutes) * 60
            )
            if boostEnd > .now {
                attributes.append(WidgetRelevanceAttribute(
                    configuration: config,
                    context: .date(range: lastUpdated...boostEnd, kind: .scheduled)
                ))
            }
        }

        let calendar = Calendar.current
        let leadMin = FondConstants.relevanceWindowLeadMinutes
        let trailMin = FondConstants.relevanceWindowTrailMinutes

        if let morningStart = calendar.date(
            bySettingHour: FondConstants.relevanceMorningHour - 1,
            minute: 60 - leadMin,
            second: 0,
            of: .now
        ),
           let morningEnd = calendar.date(
            bySettingHour: FondConstants.relevanceMorningHour,
            minute: trailMin,
            second: 0,
            of: .now
           ),
           morningEnd > .now {
            attributes.append(WidgetRelevanceAttribute(
                configuration: config,
                context: .date(range: morningStart...morningEnd, kind: .scheduled)
            ))
        }

        if let eveningStart = calendar.date(
            bySettingHour: FondConstants.relevanceEveningHour - 1,
            minute: 60 - leadMin,
            second: 0,
            of: .now
        ),
           let eveningEnd = calendar.date(
            bySettingHour: FondConstants.relevanceEveningHour,
            minute: trailMin,
            second: 0,
            of: .now
           ),
           eveningEnd > .now {
            attributes.append(WidgetRelevanceAttribute(
                configuration: config,
                context: .date(range: eveningStart...eveningEnd, kind: .scheduled)
            ))
        }

        return WidgetRelevance(attributes)
    }

    private func readEntry() -> FondEntry {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else {
            return .notConnected
        }
        let stateRaw = defaults.string(forKey: FondConstants.connectionStateKey)
        let connectionState = stateRaw.flatMap(ConnectionState.init(rawValue:)) ?? .unpaired
        guard connectionState == .connected else { return .notConnected }

        return FondEntry(
            date: .now,
            partnerName: defaults.string(forKey: FondConstants.partnerNameKey),
            status: defaults.string(forKey: FondConstants.partnerStatusKey)
                .flatMap(UserStatus.init(rawValue:)),
            message: defaults.string(forKey: FondConstants.partnerMessageKey),
            lastUpdated: defaults.object(forKey: FondConstants.partnerLastUpdatedKey) as? Date,
            connectionState: .connected,
            promptText: defaults.string(forKey: FondConstants.dailyPromptTextKey),
            myPromptAnswer: defaults.string(forKey: FondConstants.myPromptAnswerKey),
            partnerPromptAnswer: defaults.string(forKey: FondConstants.partnerPromptAnswerKey)
        )
    }
}

struct FondInlineView: View {
    let entry: FondEntry

    var body: some View {
        if let name = entry.partnerName, let status = entry.status {
            Text("\(name) · \(status.displayName.lowercased()) · \(freshness)")
                .accessibilityLabel(
                    "\(name), \(status.displayName), updated \(freshness) ago"
                )
        } else {
            Text("Fond · not connected")
        }
    }

    private var freshness: String {
        entry.lastUpdated?.widgetFreshness(relativeTo: entry.date) ?? "—"
    }
}

struct FondCircularView: View {
    let entry: FondEntry

    var body: some View {
        if let name = entry.partnerName, let status = entry.status {
            VStack(spacing: 2) {
                Text(String(name.prefix(1)))
                    .font(FondWidgetType.name(size: 28))
                    .minimumScaleFactor(0.8)
                WidgetStatusDot(status: status, size: 6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name), \(status.displayName)")
        } else {
            Text("F")
                .font(FondWidgetType.name(size: 26))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Fond, not connected")
        }
    }
}

struct FondRectangularView: View {
    let entry: FondEntry

    var body: some View {
        if let name = entry.partnerName, let status = entry.status {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    WidgetStatusDot(status: status)
                    Text("\(name) · \(status.displayName.lowercased())")
                        .font(.headline)
                        .lineLimit(1)
                }
                if let words = entry.sharedWords {
                    Text(words)
                        .font(FondWidgetType.voice(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fond").font(.headline)
                Text("Not connected").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct FondSmallView: View {
    let entry: FondEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let style = FondWidgetStyle(renderingMode: renderingMode)
        if let name = entry.partnerName, let status = entry.status {
            ViewThatFits {
                connected(
                    name: name,
                    status: status,
                    style: style,
                    nameSize: widgetNameSize,
                    showsFreshness: true
                )
                connected(
                    name: name,
                    status: status,
                    style: style,
                    nameSize: widgetNameSize,
                    showsFreshness: false
                )
                connected(
                    name: name,
                    status: status,
                    style: style,
                    nameSize: widgetNameSize - 4,
                    showsFreshness: false
                )
            }
        } else {
            notConnected(style)
        }
    }

    private func connected(
        name: String,
        status: UserStatus,
        style: FondWidgetStyle,
        nameSize: CGFloat,
        showsFreshness: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                WidgetStatusDot(status: status, size: 7)
                Text(status.displayName.lowercased())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(style.secondary)
            }

            Text(name)
                .font(FondWidgetType.name(size: nameSize))
            .foregroundStyle(style.primary)
            .lineLimit(1)

            if !isLuminanceReduced, let words = entry.sharedWords {
                Text(words)
                    .font(FondWidgetType.voice())
                    .foregroundStyle(style.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if showsFreshness, let lastUpdated = entry.lastUpdated {
                Text("\(entry.isStale ? "last seen" : "updated") \(lastUpdated.widgetFreshness(relativeTo: entry.date))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isLuminanceReduced ? style.primary : style.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func notConnected(_ style: FondWidgetStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fond")
                .font(FondWidgetType.name(size: 30))
                .foregroundStyle(style.primary)
            Text("Connect with your person")
                .font(.caption)
                .foregroundStyle(style.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var widgetNameSize: CGFloat {
        #if os(watchOS)
        22
        #else
        30
        #endif
    }
}

struct FondMediumView: View {
    let entry: FondEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let style = FondWidgetStyle(renderingMode: renderingMode)
        if let name = entry.partnerName, let status = entry.status {
            GeometryReader { proxy in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            WidgetStatusDot(status: status, size: 7)
                            Text(status.displayName.lowercased())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(style.secondary)
                        }
                        ViewThatFits(in: .horizontal) {
                            Text(name).font(FondWidgetType.name(size: 34))
                            Text(name).font(FondWidgetType.name(size: 30))
                        }
                        .foregroundStyle(style.primary)
                        .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .frame(width: proxy.size.width * 0.38, alignment: .leading)

                    WidgetVoiceRule()

                    VStack(alignment: .leading, spacing: 8) {
                        if !isLuminanceReduced, let words = entry.sharedWords {
                            Text(words)
                                .font(FondWidgetType.voice(size: 18))
                                .foregroundStyle(style.primary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        if let lastUpdated = entry.lastUpdated {
                            Text("\(entry.isStale ? "last seen" : "updated") \(lastUpdated.widgetFreshness(relativeTo: entry.date))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(isLuminanceReduced ? style.primary : style.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            HStack(spacing: 12) {
                Text("Fond")
                    .font(FondWidgetType.name(size: 34))
                    .foregroundStyle(style.primary)
                WidgetVoiceRule()
                Text("Open the app to connect with your person")
                    .font(.callout)
                    .foregroundStyle(style.secondary)
                Spacer(minLength: 0)
            }
        }
    }
}

struct FondWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FondEntry

    var body: some View {
        switch family {
        case .accessoryInline: FondInlineView(entry: entry)
        case .accessoryCircular: FondCircularView(entry: entry)
        case .accessoryRectangular: FondRectangularView(entry: entry)
        case .systemSmall: FondSmallView(entry: entry)
        case .systemMedium: FondMediumView(entry: entry)
        default: FondSmallView(entry: entry)
        }
    }
}

struct FondWidget: Widget {
    let kind = "FondWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: FondWidgetConfigIntent.self,
            provider: FondTimelineProvider()
        ) { entry in
            FondWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "fond://open")!)
                .containerBackground(for: .widget) { WidgetKeepsakeBackground() }
        }
        .configurationDisplayName("Your Person")
        .description("See your partner's status and messages at a glance.")
        .supportedFamilies(supportedFamilies)
        .pushHandler(FondWidgetPushHandler.self)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(macOS)
        [.systemSmall, .systemMedium]
        #else
        [.accessoryInline, .accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium]
        #endif
    }
}

#Preview("Presence — Small States", as: .systemSmall) {
    FondWidget()
} timeline: {
    FondEntry.placeholder
    FondEntry.stale
    FondEntry.missingMessage
    FondEntry.notConnected
}

#Preview("Presence — Medium", as: .systemMedium) {
    FondWidget()
} timeline: {
    FondEntry.placeholder
    FondEntry.stale
}

#if !os(macOS)
#Preview("Presence — Inline", as: .accessoryInline) {
    FondWidget()
} timeline: { FondEntry.placeholder }

#Preview("Presence — Circular", as: .accessoryCircular) {
    FondWidget()
} timeline: { FondEntry.placeholder }

#Preview("Presence — Rectangular", as: .accessoryRectangular) {
    FondWidget()
} timeline: { FondEntry.placeholder }
#endif

#Preview("Presence — Accented") {
    FondSmallView(entry: .placeholder)
        .environment(\.widgetRenderingMode, .accented)
        .frame(width: 170, height: 170)
        .padding()
}

#Preview("Presence — Vibrant") {
    FondSmallView(entry: .placeholder)
        .environment(\.widgetRenderingMode, .vibrant)
        .frame(width: 170, height: 170)
        .padding()
}

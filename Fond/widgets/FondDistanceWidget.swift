import AppIntents
import WidgetKit
import SwiftUI

struct FondDistanceEntry: TimelineEntry {
    let date: Date
    let partnerName: String?
    let distanceMiles: Double?
    let partnerCity: String?
    let connectionState: ConnectionState

    var formattedDistance: String? {
        guard let distanceMiles else { return nil }
        let usesMetric = Locale.current.measurementSystem == .metric
        if usesMetric {
            let kilometers = distanceMiles * 1.60934
            if kilometers < 0.3 { return "Right here" }
            if kilometers < 1 { return String(format: "%.1f km", kilometers) }
            return "\(Int(kilometers)) km"
        }
        if distanceMiles < 0.2 { return "Right here" }
        if distanceMiles < 1 { return String(format: "%.1f mi", distanceMiles) }
        return "\(Int(distanceMiles)) mi"
    }

    var shortDistance: String? {
        guard let distanceMiles else { return nil }
        let usesMetric = Locale.current.measurementSystem == .metric
        let value = usesMetric ? distanceMiles * 1.60934 : distanceMiles
        if value < 1 { return String(format: "%.1f", value) }
        return "\(Int(value))"
    }

    var unitLabel: String {
        Locale.current.measurementSystem == .metric ? "km" : "mi"
    }

    var contextual: String? {
        guard let distanceMiles else { return nil }
        if distanceMiles < 0.2 { return "Right here" }
        if distanceMiles < 30 { return "A quick drive away" }
        if distanceMiles < 300 { return "~\(Int(distanceMiles / 60))hr drive" }
        return "~\(String(format: "%.1f", distanceMiles / 500))hr flight"
    }

    static var placeholder: FondDistanceEntry {
        FondDistanceEntry(
            date: .now,
            partnerName: "Maya",
            distanceMiles: 427,
            partnerCity: "Chicago",
            connectionState: .connected
        )
    }

    static var notConnected: FondDistanceEntry {
        FondDistanceEntry(
            date: .now,
            partnerName: nil,
            distanceMiles: nil,
            partnerCity: nil,
            connectionState: .unpaired
        )
    }
}

struct FondDistanceTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = FondDistanceWidgetConfigIntent

    func placeholder(in context: Context) -> FondDistanceEntry { .placeholder }

    func snapshot(for configuration: Intent, in context: Context) async -> FondDistanceEntry {
        readEntry()
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<FondDistanceEntry> {
        let entry = readEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    func relevance() async -> WidgetRelevance<Intent> {
        var attributes: [WidgetRelevanceAttribute<Intent>] = []
        let config = FondDistanceWidgetConfigIntent()
        let calendar = Calendar.current
        let leadMin = FondConstants.relevanceWindowLeadMinutes
        let trailMin = FondConstants.relevanceWindowTrailMinutes

        if let morningStart = calendar.date(
            bySettingHour: FondConstants.relevanceCommuteAMHour - 1,
            minute: 60 - leadMin,
            second: 0,
            of: .now
        ),
           let morningEnd = calendar.date(
            bySettingHour: FondConstants.relevanceCommuteAMHour,
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
            bySettingHour: FondConstants.relevanceCommutePMHour - 1,
            minute: 60 - leadMin,
            second: 0,
            of: .now
        ),
           let eveningEnd = calendar.date(
            bySettingHour: FondConstants.relevanceCommutePMHour,
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

    private func readEntry() -> FondDistanceEntry {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else {
            return .notConnected
        }
        let stateRaw = defaults.string(forKey: FondConstants.connectionStateKey)
        let connectionState = stateRaw.flatMap(ConnectionState.init(rawValue:)) ?? .unpaired
        guard connectionState == .connected else { return .notConnected }

        return FondDistanceEntry(
            date: .now,
            partnerName: defaults.string(forKey: FondConstants.partnerNameKey),
            distanceMiles: defaults.object(forKey: FondConstants.distanceMilesKey) as? Double,
            partnerCity: defaults.string(forKey: FondConstants.partnerCityKey),
            connectionState: .connected
        )
    }
}

struct DistanceInlineView: View {
    let entry: FondDistanceEntry

    var body: some View {
        if let formattedDistance = entry.formattedDistance {
            Text("\(formattedDistance) apart")
        } else if entry.connectionState == .connected {
            Text("Fond · enable location")
        } else {
            Text("Fond · not connected")
        }
    }
}

struct DistanceCircularView: View {
    let entry: FondDistanceEntry

    var body: some View {
        if let shortDistance = entry.shortDistance {
            VStack(spacing: 0) {
                Text(shortDistance)
                    .font(FondWidgetType.value(size: 27))
                    .minimumScaleFactor(0.5)
                Text(entry.unitLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.formattedDistance ?? shortDistance) apart")
        } else {
            VStack(spacing: 1) {
                Text("F").font(FondWidgetType.name(size: 22))
                Text("location").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }
}

struct DistanceSmallView: View {
    let entry: FondDistanceEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let style = FondWidgetStyle(renderingMode: renderingMode)
        if entry.connectionState != .connected {
            messageView(title: "Fond", message: "Connect to share distance", style: style)
        } else if let formattedDistance = entry.formattedDistance {
            VStack(alignment: .leading, spacing: 7) {
                Text("APART")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(style.secondary)
                ViewThatFits(in: .horizontal) {
                    Text(formattedDistance).font(FondWidgetType.value(size: 38))
                    Text(formattedDistance).font(FondWidgetType.value(size: 32))
                }
                .foregroundStyle(style.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

                Rectangle().fill(FondColors.amber).frame(height: 1).widgetAccentable()

                if !isLuminanceReduced,
                   let partnerName = entry.partnerName,
                   let partnerCity = entry.partnerCity {
                    Text("\(partnerName) in \(partnerCity)")
                        .font(.caption)
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                } else if let contextual = entry.contextual {
                    Text(contextual)
                        .font(.caption)
                        .foregroundStyle(isLuminanceReduced ? style.primary : style.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            messageView(title: "Distance", message: "Open Fond to share location", style: style)
        }
    }

    private func messageView(
        title: String,
        message: String,
        style: FondWidgetStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FondWidgetType.name(size: 30))
                .foregroundStyle(style.primary)
            Rectangle().fill(FondColors.amber).frame(height: 1).widgetAccentable()
            Text(message)
                .font(.caption)
                .foregroundStyle(style.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct FondDistanceWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FondDistanceEntry

    var body: some View {
        switch family {
        case .accessoryInline: DistanceInlineView(entry: entry)
        case .accessoryCircular: DistanceCircularView(entry: entry)
        case .systemSmall: DistanceSmallView(entry: entry)
        default: DistanceSmallView(entry: entry)
        }
    }
}

struct FondDistanceWidget: Widget {
    let kind = "FondDistanceWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: FondDistanceWidgetConfigIntent.self,
            provider: FondDistanceTimelineProvider()
        ) { entry in
            FondDistanceWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "fond://open")!)
                .containerBackground(for: .widget) { WidgetKeepsakeBackground() }
        }
        .configurationDisplayName("Distance")
        .description("See how far apart you and your person are.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(macOS)
        [.systemSmall]
        #else
        [.accessoryInline, .accessoryCircular, .systemSmall]
        #endif
    }
}

#Preview("Distance — Small", as: .systemSmall) {
    FondDistanceWidget()
} timeline: { FondDistanceEntry.placeholder; FondDistanceEntry.notConnected }

#if !os(macOS)
#Preview("Distance — Circular", as: .accessoryCircular) {
    FondDistanceWidget()
} timeline: { FondDistanceEntry.placeholder }

#Preview("Distance — Inline", as: .accessoryInline) {
    FondDistanceWidget()
} timeline: { FondDistanceEntry.placeholder }
#endif

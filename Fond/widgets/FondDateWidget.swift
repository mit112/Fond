import AppIntents
import WidgetKit
import SwiftUI

struct FondDateEntry: TimelineEntry {
    let date: Date
    let partnerName: String?
    let anniversaryDate: Date?
    let countdownDate: Date?
    let countdownLabel: String?
    let connectionState: ConnectionState

    var daysTogether: Int? {
        guard let anniversaryDate else { return nil }
        return max(
            0,
            Calendar.current.dateComponents([.day], from: anniversaryDate, to: date).day ?? 0
        )
    }

    var daysUntilCountdown: Int? {
        guard let countdownDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: date, to: countdownDate).day ?? 0
        return days >= 0 ? days : nil
    }

    var isCountdownToday: Bool {
        guard let countdownDate else { return false }
        return Calendar.current.isDateInToday(countdownDate)
    }

    static var placeholder: FondDateEntry {
        FondDateEntry(
            date: .now,
            partnerName: "Maya",
            anniversaryDate: Calendar.current.date(byAdding: .day, value: -412, to: .now),
            countdownDate: Calendar.current.date(byAdding: .day, value: 18, to: .now),
            countdownLabel: "Lisbon",
            connectionState: .connected
        )
    }

    static var notConnected: FondDateEntry {
        FondDateEntry(
            date: .now,
            partnerName: nil,
            anniversaryDate: nil,
            countdownDate: nil,
            countdownLabel: nil,
            connectionState: .unpaired
        )
    }
}

struct FondDateTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = FondDateWidgetConfigIntent

    func placeholder(in context: Context) -> FondDateEntry { .placeholder }

    func snapshot(for configuration: Intent, in context: Context) async -> FondDateEntry {
        readEntry()
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<FondDateEntry> {
        let entry = readEntry()
        let midnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now)
                ?? .now.addingTimeInterval(86_400)
        )
        return Timeline(entries: [entry], policy: .after(midnight))
    }

    func relevance() async -> WidgetRelevance<Intent> {
        var attributes: [WidgetRelevanceAttribute<Intent>] = []
        let config = FondDateWidgetConfigIntent()
        let calendar = Calendar.current

        let tomorrow = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now)
                ?? .now.addingTimeInterval(86_400)
        )
        let midnightStart = tomorrow.addingTimeInterval(
            Double(-FondConstants.relevanceMidnightWindowMinutes) * 60
        )
        let midnightEnd = tomorrow.addingTimeInterval(
            Double(FondConstants.relevanceMidnightWindowMinutes) * 60
        )
        attributes.append(WidgetRelevanceAttribute(
            configuration: config,
            context: .date(range: midnightStart...midnightEnd, kind: .scheduled)
        ))

        if let defaults = UserDefaults(suiteName: FondConstants.appGroupID),
           let countdownDate = defaults.object(forKey: FondConstants.countdownDateKey) as? Date {
            let countdownStart = calendar.startOfDay(for: countdownDate)
            let countdownEnd = countdownStart.addingTimeInterval(24 * 60 * 60)
            if countdownEnd > .now {
                attributes.append(WidgetRelevanceAttribute(
                    configuration: config,
                    context: .date(range: countdownStart...countdownEnd, kind: .scheduled)
                ))
            }
        }
        return WidgetRelevance(attributes)
    }

    private func readEntry() -> FondDateEntry {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else {
            return .notConnected
        }
        let stateRaw = defaults.string(forKey: FondConstants.connectionStateKey)
        let connectionState = stateRaw.flatMap(ConnectionState.init(rawValue:)) ?? .unpaired
        guard connectionState == .connected else { return .notConnected }

        return FondDateEntry(
            date: .now,
            partnerName: defaults.string(forKey: FondConstants.partnerNameKey),
            anniversaryDate: defaults.object(forKey: FondConstants.anniversaryDateKey) as? Date,
            countdownDate: defaults.object(forKey: FondConstants.countdownDateKey) as? Date,
            countdownLabel: defaults.string(forKey: FondConstants.countdownLabelKey),
            connectionState: .connected
        )
    }
}

struct DateInlineView: View {
    let entry: FondDateEntry

    var body: some View {
        if let days = entry.daysTogether, let name = entry.partnerName {
            Text("\(days) \(days == 1 ? "day" : "days") with \(name)")
        } else if let days = entry.daysUntilCountdown, let label = entry.countdownLabel {
            Text("\(days) \(days == 1 ? "day" : "days") until \(label)")
        } else {
            Text("Fond · set your date")
        }
    }
}

struct DateCircularView: View {
    let entry: FondDateEntry

    var body: some View {
        if let days = entry.daysTogether {
            VStack(spacing: 0) {
                Text("\(days)")
                    .font(FondWidgetType.value(size: 27))
                    .minimumScaleFactor(0.55)
                Text("days")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(days) days together")
        } else {
            VStack(spacing: 1) {
                Text("F").font(FondWidgetType.name(size: 22))
                Text("set date").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }
}

struct DateSmallView: View {
    let entry: FondDateEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let style = FondWidgetStyle(renderingMode: renderingMode)
        if entry.connectionState != .connected {
            notConnected(style)
        } else if let days = entry.daysTogether {
            VStack(alignment: .leading, spacing: 6) {
                Text("TOGETHER")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(style.secondary)
                Text("\(days)")
                    .font(FondWidgetType.value(size: 46))
                    .foregroundStyle(style.primary)
                    .minimumScaleFactor(0.62)
                Text(days == 1 ? "day" : "days")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(style.secondary)
                Spacer(minLength: 0)
                if !isLuminanceReduced, let name = entry.partnerName {
                    Text("with \(name)")
                        .font(.caption2)
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                }
                if !isLuminanceReduced,
                   let countdownDays = entry.daysUntilCountdown,
                   let label = entry.countdownLabel,
                   !label.isEmpty {
                    Rectangle().fill(FondColors.amber).frame(height: 1).widgetAccentable()
                    Text("\(countdownDays) until \(label)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            setup(style)
        }
    }

    private func notConnected(_ style: FondWidgetStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fond").font(FondWidgetType.name(size: 30)).foregroundStyle(style.primary)
            Text("Connect to begin counting")
                .font(.caption)
                .foregroundStyle(style.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func setup(_ style: FondWidgetStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Together")
                .font(FondWidgetType.name(size: 30))
                .foregroundStyle(style.primary)
            Rectangle().fill(FondColors.amber).frame(height: 1).widgetAccentable()
            Text("Set your anniversary in Fond")
                .font(.caption)
                .foregroundStyle(style.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct DateMediumView: View {
    let entry: FondDateEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let style = FondWidgetStyle(renderingMode: renderingMode)
        if entry.connectionState != .connected {
            HStack(spacing: 14) {
                Text("Fond").font(FondWidgetType.name(size: 36)).foregroundStyle(style.primary)
                WidgetVoiceRule()
                Text("Connect to start your shared count")
                    .font(.callout)
                    .foregroundStyle(style.secondary)
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 16) {
                dateColumn(
                    eyebrow: "TOGETHER",
                    value: entry.daysTogether.map(String.init) ?? "—",
                    detail: entry.partnerName.map { "days with \($0)" } ?? "days together",
                    style: style
                )
                WidgetVoiceRule()
                if let days = entry.daysUntilCountdown {
                    dateColumn(
                        eyebrow: "COUNTDOWN",
                        value: String(days),
                        detail: entry.countdownLabel.flatMap { $0.isEmpty ? nil : "until \($0)" }
                            ?? "days to go",
                        style: style
                    )
                } else if !isLuminanceReduced {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("COUNTDOWN")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(style.secondary)
                        Text("Set the next date in Fond")
                            .font(FondWidgetType.voice(size: 17))
                            .foregroundStyle(style.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func dateColumn(
        eyebrow: String,
        value: String,
        detail: String,
        style: FondWidgetStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow).font(.caption2.weight(.semibold)).foregroundStyle(style.secondary)
            Text(value)
                .font(FondWidgetType.value(size: 44))
                .foregroundStyle(style.primary)
                .minimumScaleFactor(0.62)
            Text(detail)
                .font(.caption)
                .foregroundStyle(style.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct FondDateWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FondDateEntry

    var body: some View {
        switch family {
        case .accessoryInline: DateInlineView(entry: entry)
        case .accessoryCircular: DateCircularView(entry: entry)
        case .systemSmall: DateSmallView(entry: entry)
        case .systemMedium: DateMediumView(entry: entry)
        default: DateSmallView(entry: entry)
        }
    }
}

struct FondDateWidget: Widget {
    let kind = "FondDateWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: FondDateWidgetConfigIntent.self,
            provider: FondDateTimelineProvider()
        ) { entry in
            FondDateWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "fond://open")!)
                .containerBackground(for: .widget) { WidgetKeepsakeBackground() }
        }
        .configurationDisplayName("Days Together")
        .description("Count the days with your person. Set a countdown for your next visit.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .systemSmall, .systemMedium])
    }
}

#Preview("Date — Small", as: .systemSmall) {
    FondDateWidget()
} timeline: { FondDateEntry.placeholder; FondDateEntry.notConnected }

#Preview("Date — Medium", as: .systemMedium) {
    FondDateWidget()
} timeline: { FondDateEntry.placeholder }

#Preview("Date — Circular", as: .accessoryCircular) {
    FondDateWidget()
} timeline: { FondDateEntry.placeholder }

#Preview("Date — Inline", as: .accessoryInline) {
    FondDateWidget()
} timeline: { FondDateEntry.placeholder }

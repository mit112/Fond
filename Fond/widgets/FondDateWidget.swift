//
//  FondDateWidget.swift
//  widgets
//
//  Fond date widgets — days-together counter and countdown timer.
//  Reads dates from App Group UserDefaults. Pure client-side date math.
//
//  Separate from the main FondWidget so users can place both on
//  their home screen simultaneously.
//
//  Families: accessoryInline, accessoryCircular, systemSmall.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct FondDateEntry: TimelineEntry {
    let date: Date
    let partnerName: String?
    let anniversaryDate: Date?
    let countdownDate: Date?
    let countdownLabel: String?
    let connectionState: ConnectionState

    var daysTogether: Int? {
        guard let anniversary = anniversaryDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: anniversary, to: date).day ?? 0)
    }

    var daysUntilCountdown: Int? {
        guard let countdown = countdownDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: date, to: countdown).day ?? 0
        return days >= 0 ? days : nil // nil if in the past
    }

    /// True if countdown date is today or just passed (within 24h).
    var isCountdownToday: Bool {
        guard let countdown = countdownDate else { return false }
        return Calendar.current.isDateInToday(countdown)
    }

    static var placeholder: FondDateEntry {
        FondDateEntry(
            date: .now,
            partnerName: "Alex",
            anniversaryDate: Calendar.current.date(byAdding: .day, value: -347, to: .now),
            countdownDate: Calendar.current.date(byAdding: .day, value: 14, to: .now),
            countdownLabel: "NYC trip",
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

// MARK: - Timeline Provider

struct FondDateTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FondDateEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (FondDateEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FondDateEntry>) -> Void) {
        let entry = readEntry()
        // Refresh at midnight so the day count updates
        let midnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        )
        let timeline = Timeline(entries: [entry], policy: .after(midnight))
        completion(timeline)
    }

    private func readEntry() -> FondDateEntry {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else {
            return .notConnected
        }

        let stateRaw = defaults.string(forKey: FondConstants.connectionStateKey)
        let connectionState = stateRaw.flatMap { ConnectionState(rawValue: $0) } ?? .unpaired

        guard connectionState == .connected else {
            return .notConnected
        }

        let anniversary = defaults.object(forKey: FondConstants.anniversaryDateKey) as? Date
        let countdown = defaults.object(forKey: FondConstants.countdownDateKey) as? Date
        let countdownLabel = defaults.string(forKey: FondConstants.countdownLabelKey)
        let partnerName = defaults.string(forKey: FondConstants.partnerNameKey)

        return FondDateEntry(
            date: .now,
            partnerName: partnerName,
            anniversaryDate: anniversary,
            countdownDate: countdown,
            countdownLabel: countdownLabel,
            connectionState: .connected
        )
    }
}

// MARK: - Views

/// accessoryInline: "Day 347 with Alex 💛" or "14 days until NYC ✈️"
struct DateInlineView: View {
    let entry: FondDateEntry

    var body: some View {
        if let days = entry.daysTogether, let name = entry.partnerName {
            Text("Day \(days) with \(name) 💛")
        } else if let days = entry.daysUntilCountdown, let label = entry.countdownLabel {
            Text("\(days)d until \(label) ✈️")
        } else {
            Text("Fond — Set your date")
        }
    }
}

/// accessoryCircular: Large number, "days" label.
struct DateCircularView: View {
    let entry: FondDateEntry

    var body: some View {
        if let days = entry.daysTogether {
            VStack(spacing: 0) {
                Text("\(days)")
                    .font(.system(.title2, design: .rounded).bold())
                    .minimumScaleFactor(0.6)
                Text("days")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 2) {
                Image(systemName: "heart")
                    .font(.title3)
                Text("—")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// systemSmall: Hero number, label, partner name.
struct DateSmallView: View {
    let entry: FondDateEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        if entry.connectionState != .connected {
            notConnectedView
        } else if let days = entry.daysTogether {
            daysTogether(days)
        } else {
            setupPromptView
        }
    }

    private func daysTogether(_ days: Int) -> some View {
        VStack(spacing: 6) {
            Text("\(days)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(textPrimary)
                .minimumScaleFactor(0.5)

            Text("days together")
                .font(.caption.weight(.medium))
                .foregroundStyle(textSecondary)

            if let name = entry.partnerName {
                Text("with \(name) 💛")
                    .font(.caption2)
                    .foregroundStyle(textSecondary.opacity(0.8))
            }

            // Show countdown below if set
            if let countdownDays = entry.daysUntilCountdown {
                Divider().opacity(0.3)
                HStack(spacing: 4) {
                    Text("✈️")
                        .font(.caption2)
                    Text("\(countdownDays)d")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(renderingMode == .fullColor ? FondColors.amber : textPrimary)
                    if let label = entry.countdownLabel {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notConnectedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart")
                .font(.largeTitle)
                .foregroundStyle(textSecondary)
            Text("Not Connected")
                .font(.caption)
                .foregroundStyle(textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var setupPromptView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.title2)
                .foregroundStyle(textSecondary)
            Text("Set your\nanniversary")
                .font(.caption)
                .foregroundStyle(textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var textPrimary: Color {
        renderingMode == .fullColor ? FondColors.text : .primary
    }

    private var textSecondary: Color {
        renderingMode == .fullColor ? FondColors.textSecondary : .secondary
    }
}

/// systemMedium: Split — days-together left, countdown right.
struct DateMediumView: View {
    let entry: FondDateEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        if entry.connectionState != .connected {
            notConnectedView
        } else {
            HStack(spacing: 0) {
                // Left: days together
                VStack(spacing: 6) {
                    if let days = entry.daysTogether {
                        Text("\(days)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(textPrimary)
                            .minimumScaleFactor(0.5)
                        Text("days together")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(textSecondary)
                        if let name = entry.partnerName {
                            Text("with \(name) 💛")
                                .font(.caption2)
                                .foregroundStyle(textSecondary.opacity(0.8))
                        }
                    } else {
                        Image(systemName: "calendar.badge.plus")
                            .font(.title2)
                            .foregroundStyle(textSecondary)
                        Text("Set anniversary\nin Fond")
                            .font(.caption)
                            .foregroundStyle(textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Divider
                if entry.daysUntilCountdown != nil {
                    Rectangle()
                        .fill(textSecondary.opacity(0.2))
                        .frame(width: 1)
                        .padding(.vertical, 12)
                }

                // Right: countdown (if set)
                if let countdownDays = entry.daysUntilCountdown {
                    VStack(spacing: 6) {
                        Text("\(countdownDays)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(renderingMode == .fullColor ? FondColors.amber : textPrimary)
                            .minimumScaleFactor(0.5)
                        Text("days until")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(textSecondary)
                        if let label = entry.countdownLabel, !label.isEmpty {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(textSecondary.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entry.isCountdownToday {
                    VStack(spacing: 6) {
                        Text("🎉")
                            .font(.system(size: 36))
                        Text("It's here!")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(renderingMode == .fullColor ? FondColors.amber : textPrimary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var notConnectedView: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.largeTitle)
                .foregroundStyle(textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fond")
                    .font(.headline)
                    .foregroundStyle(textPrimary)
                Text("Open app to connect")
                    .font(.caption)
                    .foregroundStyle(textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var textPrimary: Color {
        renderingMode == .fullColor ? FondColors.text : .primary
    }

    private var textSecondary: Color {
        renderingMode == .fullColor ? FondColors.textSecondary : .secondary
    }
}

// MARK: - Widget Entry View

struct FondDateWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: FondDateEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            DateInlineView(entry: entry)
        case .accessoryCircular:
            DateCircularView(entry: entry)
        case .systemSmall:
            DateSmallView(entry: entry)
        case .systemMedium:
            DateMediumView(entry: entry)
        default:
            DateSmallView(entry: entry)
        }
    }
}

// MARK: - Widget Definition

struct FondDateWidget: Widget {
    let kind = "FondDateWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FondDateTimelineProvider()) { entry in
            FondDateWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    FondColors.background
                }
        }
        .configurationDisplayName("Days Together")
        .description("Count the days with your person. Set a countdown for your next visit.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .systemSmall,
            .systemMedium,
        ])
    }
}

// MARK: - Previews

#Preview("Small — Connected", as: .systemSmall) {
    FondDateWidget()
} timeline: {
    FondDateEntry.placeholder
}

#Preview("Medium — Both Dates", as: .systemMedium) {
    FondDateWidget()
} timeline: {
    FondDateEntry.placeholder
}

#Preview("Circular", as: .accessoryCircular) {
    FondDateWidget()
} timeline: {
    FondDateEntry.placeholder
}

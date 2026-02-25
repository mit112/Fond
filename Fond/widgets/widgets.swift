//
//  FondWidget.swift
//  widgets
//
//  Fond widget — shows partner's status, name, and message.
//  Reads decrypted data from App Group UserDefaults.
//  Supports: accessoryInline, accessoryCircular, accessoryRectangular,
//            systemSmall, systemMedium.
//
//  iOS 26 Liquid Glass: Uses widgetRenderingMode to adapt:
//    - .fullColor: warm Fond colors on home screen
//    - .accented: system handles tinting (warm amber accent color)
//    - .vibrant: lock screen — white on translucent
//
//  Design reference: docs/02-design-direction.md
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct FondEntry: TimelineEntry {
    let date: Date
    let partnerName: String?
    let status: UserStatus?
    let message: String?
    let lastUpdated: Date?
    let connectionState: ConnectionState

    // Daily prompt (optional — shown when available)
    let promptText: String?
    let myPromptAnswer: String?
    let partnerPromptAnswer: String?

    static var placeholder: FondEntry {
        FondEntry(
            date: .now,
            partnerName: "Alex",
            status: .available,
            message: "Thinking of you 💛",
            lastUpdated: Date().addingTimeInterval(-300),
            connectionState: .connected,
            promptText: "What's a song that reminds you of us?",
            myPromptAnswer: "Our Song by Taylor Swift",
            partnerPromptAnswer: "Yellow by Coldplay"
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

// MARK: - Timeline Provider

struct FondTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FondEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (FondEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FondEntry>) -> Void) {
        let entry = readEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func readEntry() -> FondEntry {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else {
            return .notConnected
        }

        let stateRaw = defaults.string(forKey: FondConstants.connectionStateKey)
        let connectionState = stateRaw.flatMap { ConnectionState(rawValue: $0) } ?? .unpaired

        guard connectionState == .connected else {
            return .notConnected
        }

        return FondEntry(
            date: .now,
            partnerName: defaults.string(forKey: FondConstants.partnerNameKey),
            status: defaults.string(forKey: FondConstants.partnerStatusKey)
                .flatMap { UserStatus(rawValue: $0) },
            message: defaults.string(forKey: FondConstants.partnerMessageKey),
            lastUpdated: defaults.object(forKey: FondConstants.partnerLastUpdatedKey) as? Date,
            connectionState: .connected,
            promptText: defaults.string(forKey: FondConstants.dailyPromptTextKey),
            myPromptAnswer: defaults.string(forKey: FondConstants.myPromptAnswerKey),
            partnerPromptAnswer: defaults.string(forKey: FondConstants.partnerPromptAnswerKey)
        )
    }
}

// MARK: - Widget Views

/// accessoryInline: "Alex is available 💚"
struct FondInlineView: View {
    let entry: FondEntry

    var body: some View {
        if let name = entry.partnerName, let status = entry.status {
            Text("\(name) is \(status.displayName.lowercased()) \(status.emoji)")
        } else {
            Text("Fond — Not connected")
        }
    }
}

/// accessoryCircular: Status emoji + time ago
struct FondCircularView: View {
    let entry: FondEntry

    var body: some View {
        if let status = entry.status {
            VStack(spacing: 2) {
                Text(status.emoji)
                    .font(.title2)
                if let lastUpdated = entry.lastUpdated {
                    Text(lastUpdated.shortTimeAgo)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Image(systemName: "heart.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

/// accessoryRectangular: Name + status + message or prompt preview
struct FondRectangularView: View {
    let entry: FondEntry

    var body: some View {
        if let name = entry.partnerName, let status = entry.status {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(status.emoji) \(name)")
                    .font(.headline)
                    .lineLimit(1)
                Text(status.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Show prompt answer if available, otherwise message
                if entry.promptText != nil,
                   let answer = entry.partnerPromptAnswer {
                    Text("💬 \(answer)")
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                } else if let message = entry.message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fond")
                    .font(.headline)
                Text("Not connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// systemSmall: Compact home screen view — emoji hero, name, status.
struct FondSmallView: View {
    let entry: FondEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        if let name = entry.partnerName, let status = entry.status {
            VStack(spacing: 8) {
                // Emoji is the dominant visual — readable from across the room in StandBy
                Text(status.emoji)
                    .font(.system(size: 44))

                Text(name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(status.displayName)
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)

                if let lastUpdated = entry.lastUpdated {
                    Text(lastUpdated.shortTimeAgo)
                        .font(.caption2)
                        .foregroundStyle(textSecondary.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
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
    }

    // Adapt colors per rendering mode
    private var textPrimary: Color {
        renderingMode == .fullColor ? FondColors.text : .primary
    }

    private var textSecondary: Color {
        renderingMode == .fullColor ? FondColors.textSecondary : .secondary
    }
}

/// systemMedium: Full status + message — the flagship widget.
struct FondMediumView: View {
    let entry: FondEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        if let name = entry.partnerName, let status = entry.status {
            HStack(spacing: 16) {
                Text(status.emoji)
                    .font(.system(size: 48))

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textPrimary)

                    Text(status.displayName)
                        .font(.subheadline)
                        .foregroundStyle(
                            renderingMode == .fullColor
                                ? status.accentColor
                                : textSecondary
                        )

                    if let message = entry.message, !message.isEmpty {
                        Text(message)
                            .font(.body)
                            .foregroundStyle(textPrimary.opacity(0.85))
                            .lineLimit(2)
                            .padding(.top, 2)
                    }

                    if let lastUpdated = entry.lastUpdated {
                        Text(lastUpdated.shortTimeAgo)
                            .font(.caption2)
                            .foregroundStyle(textSecondary.opacity(0.7))
                    }

                    // Daily prompt section
                    if let prompt = entry.promptText {
                        Divider().opacity(0.3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("💬 \(prompt)")
                                .font(.caption2)
                                .foregroundStyle(textSecondary)
                                .lineLimit(1)
                            if let myAns = entry.myPromptAnswer,
                               let partnerAns = entry.partnerPromptAnswer {
                                HStack(spacing: 8) {
                                    Text("You: \(myAns)")
                                        .font(.caption2)
                                        .foregroundStyle(textPrimary.opacity(0.7))
                                        .lineLimit(1)
                                    Text("•")
                                        .foregroundStyle(textSecondary.opacity(0.5))
                                    Text("\(entry.partnerName ?? "Them"): \(partnerAns)")
                                        .font(.caption2)
                                        .foregroundStyle(textPrimary.opacity(0.7))
                                        .lineLimit(1)
                                }
                            } else if entry.myPromptAnswer == nil {
                                Text("Tap to answer")
                                    .font(.caption2)
                                    .foregroundStyle(renderingMode == .fullColor ? FondColors.amber : textSecondary)
                            } else {
                                Text("Waiting for \(entry.partnerName ?? "partner")...")
                                    .font(.caption2)
                                    .foregroundStyle(textSecondary.opacity(0.7))
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "heart")
                    .font(.largeTitle)
                    .foregroundStyle(textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fond")
                        .font(.headline)
                        .foregroundStyle(textPrimary)
                    Text("Open app to connect with your person")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
    }

    private var textPrimary: Color {
        renderingMode == .fullColor ? FondColors.text : .primary
    }

    private var textSecondary: Color {
        renderingMode == .fullColor ? FondColors.textSecondary : .secondary
    }
}

// MARK: - Widget Entry View (routes per family)

struct FondWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode
    let entry: FondEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            FondInlineView(entry: entry)
        case .accessoryCircular:
            FondCircularView(entry: entry)
        case .accessoryRectangular:
            FondRectangularView(entry: entry)
        case .systemSmall:
            FondSmallView(entry: entry)
        case .systemMedium:
            FondMediumView(entry: entry)
        default:
            FondSmallView(entry: entry)
        }
    }
}

// MARK: - Widget Definition

struct FondWidget: Widget {
    let kind = "FondWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FondTimelineProvider()) { entry in
            FondWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    // Full-color: warm Fond background
                    // Accented/vibrant: system handles it automatically
                    FondColors.background
                }
        }
        .configurationDisplayName("Your Person")
        .description("See your partner's status and messages at a glance.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .systemSmall,
            .systemMedium,
        ])
        .pushHandler(FondWidgetPushHandler.self)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    FondWidget()
} timeline: {
    FondEntry.placeholder
    FondEntry.notConnected
}

#Preview("Medium", as: .systemMedium) {
    FondWidget()
} timeline: {
    FondEntry.placeholder
}

#Preview("Rectangular", as: .accessoryRectangular) {
    FondWidget()
} timeline: {
    FondEntry.placeholder
}

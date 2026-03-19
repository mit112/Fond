//
//  FondDistanceWidget.swift
//  widgets
//
//  Fond distance widget — shows how far apart two partners are.
//  Reads distance (miles) and partner city from App Group UserDefaults.
//  Pure client-side display — distance computed by the main app.
//
//  Separate from the main FondWidget so users can place it independently
//  on their lock screen or home screen.
//
//  Families: accessoryInline, accessoryCircular, systemSmall.
//

import AppIntents
import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct FondDistanceEntry: TimelineEntry {
    let date: Date
    let partnerName: String?
    let distanceMiles: Double?
    let partnerCity: String?
    let connectionState: ConnectionState

    /// Locale-appropriate distance string.
    var formattedDistance: String? {
        guard let miles = distanceMiles else { return nil }
        let usesMetric = Locale.current.measurementSystem == .metric
        if usesMetric {
            let km = miles * 1.60934
            if km < 0.3 { return "Right here 💛" }
            if km < 1 { return String(format: "%.1f km", km) }
            return "\(Int(km)) km"
        } else {
            if miles < 0.2 { return "Right here 💛" }
            if miles < 1 { return String(format: "%.1f mi", miles) }
            return "\(Int(miles)) mi"
        }
    }

    /// Short unit-only distance for circular widget.
    var shortDistance: String? {
        guard let miles = distanceMiles else { return nil }
        let usesMetric = Locale.current.measurementSystem == .metric
        if usesMetric {
            let km = miles * 1.60934
            if km < 1 { return String(format: "%.1f", km) }
            return "\(Int(km))"
        } else {
            if miles < 1 { return String(format: "%.1f", miles) }
            return "\(Int(miles))"
        }
    }

    var unitLabel: String {
        Locale.current.measurementSystem == .metric ? "km" : "mi"
    }

    /// Contextual message for small widget.
    var contextual: String? {
        guard let miles = distanceMiles else { return nil }
        if miles < 0.2 { return "Right here 💛" }
        if miles < 30 { return "A quick drive away" }
        if miles < 300 { return "~\(Int(miles / 60))hr drive" }
        return "~\(String(format: "%.1f", miles / 500))hr flight"
    }

    static var placeholder: FondDistanceEntry {
        FondDistanceEntry(
            date: .now,
            partnerName: "Alex",
            distanceMiles: 347,
            partnerCity: "New York",
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

// MARK: - Timeline Provider

struct FondDistanceTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = FondDistanceWidgetConfigIntent

    func placeholder(in context: Context) -> FondDistanceEntry {
        .placeholder
    }

    func snapshot(for configuration: Intent, in context: Context) async -> FondDistanceEntry {
        readEntry()
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<FondDistanceEntry> {
        let entry = readEntry()
        // Refresh every 30 min — location updates are infrequent
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func readEntry() -> FondDistanceEntry {
        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else {
            return .notConnected
        }

        let stateRaw = defaults.string(forKey: FondConstants.connectionStateKey)
        let connectionState = stateRaw.flatMap { ConnectionState(rawValue: $0) } ?? .unpaired

        guard connectionState == .connected else {
            return .notConnected
        }

        let miles = defaults.object(forKey: FondConstants.distanceMilesKey) as? Double
        let city = defaults.string(forKey: FondConstants.partnerCityKey)
        let name = defaults.string(forKey: FondConstants.partnerNameKey)

        return FondDistanceEntry(
            date: .now,
            partnerName: name,
            distanceMiles: miles,
            partnerCity: city,
            connectionState: .connected
        )
    }
}

// MARK: - Views

/// accessoryInline: "347 mi apart 📍"
struct DistanceInlineView: View {
    let entry: FondDistanceEntry

    var body: some View {
        if let formatted = entry.formattedDistance {
            Text("\(formatted) apart 📍")
        } else if entry.connectionState == .connected {
            Text("Fond — Enable location")
        } else {
            Text("Fond — Not connected")
        }
    }
}

/// accessoryCircular: Large distance number, unit label.
struct DistanceCircularView: View {
    let entry: FondDistanceEntry

    var body: some View {
        if let short = entry.shortDistance {
            VStack(spacing: 0) {
                Text(short)
                    .font(.system(.title2, design: .rounded).bold())
                    .minimumScaleFactor(0.5)
                Text(entry.unitLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 2) {
                Image(systemName: "location.slash")
                    .font(.title3)
                Text("—")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// systemSmall: Hero distance, city names, contextual hint.
struct DistanceSmallView: View {
    let entry: FondDistanceEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        if entry.connectionState != .connected {
            notConnectedView
        } else if let formatted = entry.formattedDistance {
            distanceView(formatted)
        } else {
            noLocationView
        }
    }

    private func distanceView(_ formatted: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundStyle(renderingMode == .fullColor ? FondColors.amber : textPrimary)

            Text(formatted)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(textPrimary)
                .minimumScaleFactor(0.5)

            Text("apart")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(textSecondary)

            if let city = entry.partnerCity, let name = entry.partnerName {
                Text("\(name) in \(city)")
                    .font(.caption2)
                    .foregroundStyle(textSecondary.opacity(0.8))
                    .lineLimit(1)
            } else if let contextual = entry.contextual {
                Text(contextual)
                    .font(.caption2)
                    .foregroundStyle(textSecondary.opacity(0.8))
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

    private var noLocationView: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash")
                .font(.title2)
                .foregroundStyle(textSecondary)
            Text("Open Fond to\nshare location")
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

// MARK: - Widget Entry View

struct FondDistanceWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: FondDistanceEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            DistanceInlineView(entry: entry)
        case .accessoryCircular:
            DistanceCircularView(entry: entry)
        case .systemSmall:
            DistanceSmallView(entry: entry)
        default:
            DistanceSmallView(entry: entry)
        }
    }
}

// MARK: - Widget Definition

struct FondDistanceWidget: Widget {
    let kind = "FondDistanceWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FondDistanceWidgetConfigIntent.self, provider: FondDistanceTimelineProvider()) { entry in
            FondDistanceWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "fond://open")!)
                .containerBackground(for: .widget) {
                    FondColors.background
                }
        }
        .configurationDisplayName("Distance")
        .description("See how far apart you and your person are.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .systemSmall,
        ])
    }
}

// MARK: - Previews

#Preview("Small — Connected", as: .systemSmall) {
    FondDistanceWidget()
} timeline: {
    FondDistanceEntry.placeholder
}

#Preview("Circular", as: .accessoryCircular) {
    FondDistanceWidget()
} timeline: {
    FondDistanceEntry.placeholder
}

#Preview("Inline", as: .accessoryInline) {
    FondDistanceWidget()
} timeline: {
    FondDistanceEntry.placeholder
}

import Foundation
import SwiftUI

struct NowFaceModel: Sendable {
    let partnerName: String
    let status: UserStatus?
    let message: String?
    let lastUpdated: Date?
    let heartbeatBpm: Int?
    let heartbeatTime: Date?
    let distanceMiles: Double?
    let relationshipLine: String?
    let isStale: Bool
}

enum RelationshipDateSummary {
    static func make(
        anniversary: Date?,
        countdown: Date?,
        label: String?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        let today = calendar.startOfDay(for: now)
        var parts: [String] = []

        if let anniversary {
            let start = calendar.startOfDay(for: anniversary)
            if let days = calendar.dateComponents([.day], from: start, to: today).day,
               days >= 0 {
                parts.append("\(days) \(days == 1 ? "day" : "days") together")
            }
        }

        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let countdown, !trimmedLabel.isEmpty {
            let target = calendar.startOfDay(for: countdown)
            if let days = calendar.dateComponents([.day], from: today, to: target).day,
               days >= 0 {
                parts.append("\(days) until \(trimmedLabel)")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct NowFaceView: View {
    let model: NowFaceModel
    let isBreathing: Bool
    let onNudge: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    identityBlock
                }

                if let message = trimmedMessage {
                    GridRow {
                        latestWords(message)
                            .padding(.top, 54)
                    }
                }

                if !signalFacts.isEmpty {
                    GridRow {
                        signalsBlock
                            .padding(.top, 48)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.vertical, 34)
        }
        .scrollIndicators(.hidden)
        .scaleEffect(reduceMotion ? 1 : (isBreathing ? 1.003 : 1))
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 5.6).repeatForever(autoreverses: true),
            value: isBreathing
        )
        .foregroundStyle(FondColors.ink)
    }

    private var identityBlock: some View {
        Button {
            onNudge()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let status = model.status {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(status.statusColor)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(status.displayName.lowercased())
                            .font(FondType.eyebrow)
                            .foregroundStyle(FondColors.inkSecondary)
                    }
                }

                Text(model.partnerName)
                    .font(FondType.partnerName)
                    .foregroundStyle(FondColors.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                if let relationshipLine = model.relationshipLine {
                    Text(relationshipLine)
                        .font(FondType.metadata)
                        .foregroundStyle(FondColors.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send a nudge to \(model.partnerName)")
        .accessibilityAction(named: "Send nudge") {
            onNudge()
        }
    }

    private func latestWords(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Rectangle()
                .fill(FondColors.amber)
                .frame(width: 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(FondType.pullQuote)
                    .foregroundStyle(FondColors.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(attribution)
                    .font(FondType.metadata)
                    .foregroundStyle(FondColors.inkSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var signalsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(FondColors.rule)
                .frame(height: 1)
                .accessibilityHidden(true)

            Text(signalFacts.joined(separator: " · "))
                .font(FondType.metadata)
                .foregroundStyle(FondColors.inkSecondary)
                .contentTransition(.numericText())
        }
    }

    private var trimmedMessage: String? {
        guard let message = model.message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else { return nil }
        return message
    }

    private var attribution: String {
        var value = "from \(model.partnerName)"
        if let lastUpdated = model.lastUpdated {
            value += " · \(lastUpdated.shortTimeAgo)"
        }
        return value
    }

    private var signalFacts: [String] {
        var facts: [String] = []
        if let distanceMiles = model.distanceMiles {
            facts.append(LocationManager.formattedDistance(distanceMiles))
        }
        if let heartbeatBpm = model.heartbeatBpm, heartbeatBpm > 0 {
            facts.append("\(heartbeatBpm) bpm")
        }
        if let lastUpdated = model.lastUpdated {
            let freshness = model.isStale ? "last seen" : "updated"
            facts.append("\(freshness) \(lastUpdated.shortTimeAgo)")
        }
        return facts
    }

}

private let nowFacePreviewModel = NowFaceModel(
    partnerName: "Maya",
    status: .available,
    message: "I keep thinking about the walk home.",
    lastUpdated: .now.addingTimeInterval(-420),
    heartbeatBpm: 72,
    heartbeatTime: .now.addingTimeInterval(-600),
    distanceMiles: 427.3,
    relationshipLine: "412 days together · 18 until Lisbon",
    isStale: false
)

#Preview("Now — Light") {
    NowFaceView(model: nowFacePreviewModel, isBreathing: false) {}
        .fondKeepsakeCard()
        .padding(20)
        .background(FondColors.field)
        .preferredColorScheme(.light)
}

#Preview("Now — Dark") {
    NowFaceView(model: nowFacePreviewModel, isBreathing: false) {}
        .fondKeepsakeCard()
        .padding(20)
        .background(FondColors.field)
        .preferredColorScheme(.dark)
}

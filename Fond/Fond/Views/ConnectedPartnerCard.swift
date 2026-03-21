//
//  ConnectedPartnerCard.swift
//  Fond
//
//  The partner "hero" card — the emotional center of the app.
//  Shows status atmosphere, emoji, name, message bubble, time-ago,
//  ambient data row (distance + heartbeat), and nudge hint.
//

import SwiftUI

struct ConnectedPartnerCard: View {
    let partnerName: String
    let partnerStatus: UserStatus?
    let partnerMessage: String?
    let partnerLastUpdated: Date?
    let partnerHeartbeatBpm: Int?
    let partnerHeartbeatTime: Date?
    var distanceMiles: Double? = nil
    var partnerCity: String? = nil
    var isBreathing: Bool = false
    var nudgeHintVisible: Bool = true
    var isStale: Bool = false
    var onNudge: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            statusIndicator
            statusEmoji
            nameLabel
            messageBubble
            timeAgoLabel
            ambientDataRow
            nudgeHint
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .fondCard(cornerRadius: 24)
        .overlay { statusAtmosphere }
        .scaleEffect(reduceMotion ? 1.0 : (isBreathing ? 1.003 : 1.0))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAction(named: "Send nudge") { onNudge?() }
    }

    // MARK: - Status Color

    private var statusColor: Color {
        partnerStatus?.statusColor ?? FondColors.amber
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusIndicator: some View {
        if let status = partnerStatus {
            HStack(spacing: 6) {
                Circle()
                    .fill(status.statusColor)
                    .frame(width: 7, height: 7)
                Text(status.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(status.statusColor)
            }
        }
    }

    private var statusEmoji: some View {
        Text(partnerStatus?.emoji ?? "\u{23F3}")
            .font(.system(size: 52))
            .animation(.fondSpring, value: partnerStatus?.emoji)
    }

    private var nameLabel: some View {
        Text(partnerName)
            .font(.title.bold())
            .tracking(-0.5)
            .foregroundStyle(FondColors.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var messageBubble: some View {
        if let message = partnerMessage, !message.isEmpty {
            Text(message)
                .font(.body)
                .foregroundStyle(FondColors.text.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(FondColors.lavender.opacity(0.18))
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    private var timeAgoLabel: some View {
        if let lastUpdated = partnerLastUpdated {
            Text(lastUpdated.shortTimeAgo)
                .font(.caption)
                .foregroundStyle(
                    isStale
                        ? FondColors.amber.opacity(0.6)
                        : FondColors.textSecondary
                )
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private var ambientDataRow: some View {
        let hasDistance = distanceMiles != nil
        let hasHeartbeat: Bool = {
            guard let bpm = partnerHeartbeatBpm,
                  bpm > 0,
                  let time = partnerHeartbeatTime else { return false }
            return Date().timeIntervalSince(time) < 1800
        }()

        if hasDistance || hasHeartbeat {
            HStack(spacing: 14) {
                if let miles = distanceMiles {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(FondColors.amber)
                        Text(LocationManager.formattedDistance(miles))
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(FondColors.text)
                        if let city = partnerCity {
                            Text(city)
                                .font(.caption2)
                                .foregroundStyle(FondColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                if hasDistance && hasHeartbeat {
                    Rectangle()
                        .fill(FondColors.textSecondary.opacity(0.4))
                        .frame(width: 1, height: 12)
                }

                if let bpm = partnerHeartbeatBpm,
                   let time = partnerHeartbeatTime,
                   Date().timeIntervalSince(time) < 1800 {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(FondColors.rose)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("\(bpm) bpm")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(FondColors.text)
                    }
                }
            }
            .opacity(isStale ? 0.4 : 1.0)
        }
    }

    @ViewBuilder
    private var nudgeHint: some View {
        if nudgeHintVisible {
            Text("hold to nudge")
                .font(.caption2)
                .foregroundStyle(FondColors.textSecondary.opacity(0.4))
        }
    }

    // MARK: - Status Atmosphere Overlay

    private var statusAtmosphere: some View {
        EllipticalGradient(
            colors: [statusColor.opacity(isStale ? 0.05 : 0.18), .clear],
            center: .init(x: 0.5, y: 0.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .allowsHitTesting(false)
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let status = partnerStatus {
            parts.append("\(partnerName), \(status.displayName)")
        } else {
            parts.append(partnerName)
        }
        if let message = partnerMessage, !message.isEmpty {
            parts.append("says \(message)")
        }
        if let lastUpdated = partnerLastUpdated {
            parts.append("updated \(lastUpdated.shortTimeAgo)")
        }
        if let miles = distanceMiles {
            parts.append("\(LocationManager.formattedDistance(miles)) away")
            if let city = partnerCity {
                parts.append("in \(city)")
            }
        }
        if let bpm = partnerHeartbeatBpm,
           let time = partnerHeartbeatTime,
           Date().timeIntervalSince(time) < 1800 {
            parts.append("heart rate \(bpm) beats per minute")
        }
        if isStale {
            parts.append("data may be outdated")
        }
        return parts.joined(separator: ", ")
    }
}

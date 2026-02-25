//
//  WatchConnectedView.swift
//  watchkitapp Watch App
//
//  Displays partner's status, message, and name on the watch.
//  Bidirectional: also sends nudge ("thinking of you") and heartbeat
//  to the partner via iPhone → Firebase pipeline.
//
//  Design: Warm background, centered layout, status emoji as visual anchor.
//  Action buttons at the bottom for nudge + heartbeat.
//
//  Design reference: docs/02-design-direction.md (watchOS section)
//

import SwiftUI
import WatchKit

struct WatchConnectedView: View {
    var dataStore: WatchDataStore

    @State private var emojiBounce = false
    @State private var heartbeatManager = HeartbeatManager.shared

    var body: some View {
        ZStack {
            FondMeshGradient()

            ScrollView {
                VStack(spacing: 10) {

                    // ── Partner Display ──

                    Text(dataStore.partnerStatusEmoji ?? "⏳")
                        .font(.system(size: 48))
                        .scaleEffect(emojiBounce ? 1.15 : 1.0)
                        .animation(.fondSpring, value: emojiBounce)

                    Text(dataStore.partnerName ?? "Your person")
                        .font(.title3.bold())
                        .foregroundStyle(FondColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let status = dataStore.partnerStatus {
                        Text(statusDisplayName(status))
                            .font(.callout)
                            .foregroundStyle(statusColor(status))
                    }

                    if let message = dataStore.partnerMessage, !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(FondColors.text.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 4)
                    }

                    if let lastUpdated = dataStore.partnerLastUpdated {
                        Text(lastUpdated.shortTimeAgo)
                            .font(.caption2)
                            .foregroundStyle(FondColors.textSecondary)
                            .contentTransition(.numericText())
                    }

                    // ── Action Buttons ──

                    Divider()
                        .padding(.vertical, 4)

                    nudgeButton
                    heartbeatButton

                    // Feedback
                    if let error = dataStore.sendError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(FondColors.rose)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .onChange(of: dataStore.partnerStatus) {
            emojiBounce = true
            WKInterfaceDevice.current().play(.notification)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                emojiBounce = false
            }
        }
    }

    // MARK: - Nudge Button

    private var nudgeButton: some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            dataStore.sendNudge()
        } label: {
            HStack(spacing: 8) {
                if dataStore.isSending {
                    ProgressView()
                        .tint(FondColors.text)
                } else if dataStore.sendSuccess {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                } else {
                    Text("💛")
                    Text("Thinking of You")
                        .font(.footnote.weight(.medium))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(FondColors.amber.opacity(0.3))
        .disabled(dataStore.isSending || !dataStore.canSend)
    }

    // MARK: - Heartbeat Button

    private var heartbeatButton: some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            Task {
                if let bpm = await heartbeatManager.queryLatestHeartRate() {
                    dataStore.sendHeartbeat(bpm: bpm)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if heartbeatManager.isQuerying {
                    ProgressView()
                        .tint(FondColors.text)
                } else {
                    Image(systemName: "heart.fill")
                        .font(.footnote)
                        .foregroundStyle(FondColors.rose)
                    if let bpm = heartbeatManager.lastBpm {
                        Text("Send \(bpm) bpm")
                            .font(.footnote.weight(.medium))
                    } else {
                        Text("Send Heartbeat")
                            .font(.footnote.weight(.medium))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .disabled(
            dataStore.isSending
            || !dataStore.canSend
            || heartbeatManager.isQuerying
        )
    }

    // MARK: - Helpers

    private func statusDisplayName(_ raw: String) -> String {
        if let status = UserStatus(rawValue: raw) {
            return status.displayName
        }
        return UserStatus.displayInfo(forRawValue: raw).displayName
    }

    private func statusColor(_ raw: String) -> Color {
        if let status = UserStatus(rawValue: raw) {
            return status.accentColor
        }
        return FondColors.textSecondary
    }
}

#Preview {
    let store = WatchDataStore()
    WatchConnectedView(dataStore: store)
}

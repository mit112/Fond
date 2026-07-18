import SwiftUI
import WatchKit

struct WatchConnectedView: View {
    var dataStore: WatchDataStore

    @State private var heartbeatManager = HeartbeatManager.shared
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                presenceCard

                VStack(spacing: 8) {
                    nudgeButton
                    heartbeatButton
                }

                if let error = dataStore.sendError ?? heartbeatManager.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(FondColors.ink)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 4)
        }
        .background(FondColors.field)
        .onChange(of: dataStore.partnerStatus) {
            WKInterfaceDevice.current().play(.notification)
        }
    }

    private var presenceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let rawStatus = dataStore.partnerStatus {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(rawStatus))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(statusDisplayName(rawStatus).lowercased())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(FondColors.inkSecondary)
                }
            }

            Text(dataStore.partnerName ?? "Your person")
                .font(watchNameFont)
                .foregroundStyle(FondColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if !isLuminanceReduced,
               let message = displayedMessage {
                Text(message)
                    .font(FondType.voice)
                    .foregroundStyle(FondColors.ink)
                    .lineLimit(1)
            }

            if let lastUpdated = dataStore.partnerLastUpdated {
                Text("updated \(lastUpdated.shortTimeAgo)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(
                        isLuminanceReduced ? FondColors.ink : FondColors.inkSecondary
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FondColors.keepsake)
                .overlay {
                    if !isLuminanceReduced {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(FondColors.amber, lineWidth: 1)
                    }
                }
        }
    }

    private var nudgeButton: some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            dataStore.sendNudge()
        } label: {
            HStack(spacing: 7) {
                if dataStore.isSending {
                    ProgressView().tint(FondColors.sendForeground)
                } else if dataStore.sendSuccess {
                    Image(systemName: "checkmark")
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Image(systemName: "hand.tap")
                    Text("Nudge")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(FondColors.sendForeground)
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .fondGlassInteractive(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            tinted: true
        )
        .disabled(dataStore.isSending || !dataStore.canSend)
        .accessibilityLabel("Send a nudge")
    }

    private var heartbeatButton: some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            Task {
                if let bpm = await heartbeatManager.queryLatestHeartRate() {
                    dataStore.sendHeartbeat(bpm: bpm)
                }
            }
        } label: {
            HStack(spacing: 7) {
                if heartbeatManager.isQuerying {
                    ProgressView().tint(FondColors.ink)
                } else {
                    Image(systemName: "heart")
                    Text(heartbeatManager.lastBpm.map { "Send \($0) bpm" } ?? "Send heartbeat")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(FondColors.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .fondGlassInteractive(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            tinted: false
        )
        .disabled(dataStore.isSending || !dataStore.canSend || heartbeatManager.isQuerying)
    }

    private var displayedMessage: String? {
        guard let message = dataStore.partnerMessage?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
              !message.isEmpty,
              message != "💛" else { return nil }
        return message
    }

    private var watchNameFont: Font {
        FondVariableFont.make(
            name: "Fraunces",
            size: 22,
            relativeTo: .title3,
            axes: ["opsz": 28, "SOFT": 28, "WONK": 1, "wght": 540]
        )
    }

    private func statusDisplayName(_ raw: String) -> String {
        UserStatus.displayInfo(forRawValue: raw).displayName
    }

    private func statusColor(_ raw: String) -> Color {
        UserStatus(rawValue: raw)?.statusColor ?? FondColors.inkSecondary
    }
}

#Preview {
    WatchConnectedView(dataStore: WatchDataStore())
}

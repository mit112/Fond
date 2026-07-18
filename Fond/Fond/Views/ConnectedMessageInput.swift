import SwiftUI

struct ConnectedMessageInput: View {
    @Binding var messageText: String
    var myStatus: UserStatus = .available
    let isSending: Bool
    let sendSuccess: Bool
    let cooldownRemaining: Int
    let errorMessage: String?
    let onSend: () -> Void
    var onStatusTap: (() -> Void)?

    var body: some View {
        VStack(spacing: FondSpacing.one) {
            feedbackBar
                .animation(.fondQuick, value: errorMessage)
                .animation(.fondQuick, value: charCount)

            GlassEffectContainer(spacing: FondSpacing.two) {
                HStack(spacing: FondSpacing.two) {
                    composeShell
                    sendButton
                }
            }
        }
        .onChange(of: messageText) { _, newValue in
            if newValue.count > FondConstants.maxMessageLength {
                messageText = String(newValue.prefix(FondConstants.maxMessageLength))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fond.compose")
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var composeShell: some View {
        HStack(spacing: FondSpacing.two) {
            Button {
                onStatusTap?()
            } label: {
                Circle()
                    .fill(myStatus.statusColor)
                    .frame(width: 10, height: 10)
                    .frame(width: FondGeometry.minimumTarget, height: FondGeometry.minimumTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your status: \(myStatus.displayName). Change status.")

            Rectangle()
                .fill(FondColors.rule)
                .frame(width: 1, height: 22)
                .accessibilityHidden(true)

            TextField("Say something…", text: $messageText)
                .font(FondType.body)
                .foregroundStyle(FondColors.ink)
                .submitLabel(.send)
                .onSubmit(onSend)
                .accessibilityLabel("Message")
        }
        .padding(.horizontal, FondSpacing.two)
        .frame(maxWidth: .infinity, minHeight: 48)
        .fondControlPlate(in: Capsule())
        .padding(2)
        .frame(height: 56)
        .fondFloatingControl(in: Capsule())
    }

    @ViewBuilder
    private var sendButton: some View {
        let button = Button(action: onSend) {
            Group {
                if isSending {
                    ProgressView()
                        .tint(sendForeground)
                } else if sendSuccess {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .medium))
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .medium))
                }
            }
            .foregroundStyle(sendForeground)
            .frame(width: 52, height: 52)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(sendDisabled)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("Send message")
        .accessibilityIdentifier("fond.send")
        .overlay {
            if cooldownProgress > 0 {
                Circle()
                    .trim(from: 0, to: cooldownProgress)
                    .stroke(
                        FondColors.amber,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 46, height: 46)
                    .animation(.linear(duration: 1), value: cooldownProgress)
                    .accessibilityHidden(true)
            }
        }

        if sendDisabled {
            button.fondFloatingControl(in: Circle())
        } else {
            button.fondSendControl()
        }
    }

    @ViewBuilder
    private var feedbackBar: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(FondType.metadata)
                .foregroundStyle(FondColors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        } else if charCount > charCountThreshold {
            Text("\(charCount)/\(FondConstants.maxMessageLength)")
                .font(FondType.metadata)
                .foregroundStyle(
                    charCount == FondConstants.maxMessageLength
                        ? FondColors.amber
                        : FondColors.inkSecondary
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentTransition(.numericText())
                .transition(.opacity)
        }
    }

    private var trimmedText: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sendDisabled: Bool {
        trimmedText.isEmpty || isSending
    }

    private var sendForeground: Color {
        sendDisabled ? FondColors.inkSecondary : FondColors.sendForeground
    }

    private var charCount: Int { messageText.count }

    private var charCountThreshold: Int {
        Int(Double(FondConstants.maxMessageLength) * 0.7)
    }

    private var cooldownProgress: CGFloat {
        guard cooldownRemaining > 0 else { return 0 }
        return CGFloat(cooldownRemaining) / CGFloat(FondConstants.rateLimitSeconds)
    }
}

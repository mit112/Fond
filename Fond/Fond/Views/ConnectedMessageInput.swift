//
//  ConnectedMessageInput.swift
//  Fond
//
//  Extracted from ConnectedView — status pill, message text field, send button
//  with cooldown ring overlay, and the feedback bar (error / char count).
//

import SwiftUI

struct ConnectedMessageInput: View {
    @Binding var messageText: String
    var myStatus: UserStatus = .available
    let isSending: Bool
    let sendSuccess: Bool
    let cooldownRemaining: Int
    let errorMessage: String?
    let onSend: () -> Void
    var onStatusTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            feedbackBar
                .padding(.bottom, 4)
                .animation(.fondQuick, value: errorMessage)
                .animation(.fondQuick, value: charCount)

            HStack(spacing: 8) {
                statusPill
                inputRow
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Status Pill

    private var statusPill: some View {
        Button {
            onStatusTap?()
        } label: {
            HStack(spacing: 4) {
                Text(myStatus.emoji)
                    .font(.system(size: 18))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FondColors.textSecondary.opacity(0.15))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fondGlassInteractive(
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityLabel("Your status: \(myStatus.displayName). Double tap to change.")
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(spacing: 10) {
            TextField("Say something...", text: $messageText)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                    .fill(FondColors.surface.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                    .stroke(
                        FondColors.textSecondary.opacity(0.15),
                        lineWidth: 1
                    )
                )
                .submitLabel(.send)
                .onSubmit { onSend() }

            sendButton
        }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            onSend()
        } label: {
            Group {
                if isSending {
                    ProgressView()
                        .tint(FondColors.text)
                } else if sendSuccess {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 30, height: 30)
            .contentTransition(.symbolEffect(.replace))
        }
        .disabled(trimmedText.isEmpty || isSending)
        .fondGlassInteractive(in: Circle(), tinted: true)
        .overlay {
            if cooldownProgress > 0 {
                Circle()
                    .trim(from: 0, to: cooldownProgress)
                    .stroke(
                        FondColors.amber.opacity(0.5),
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 34, height: 34)
                    .animation(
                        .linear(duration: 1),
                        value: cooldownProgress
                    )
            }
        }
    }

    // MARK: - Feedback Bar

    @ViewBuilder
    private var feedbackBar: some View {
        if let error = errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(FondColors.rose)
                .transition(.opacity)
        } else if charCount > charCountThreshold {
            Text("\(charCount)/\(FondConstants.maxMessageLength)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    charCount >= FondConstants.maxMessageLength
                        ? FondColors.rose
                        : FondColors.textSecondary
                )
                .contentTransition(.numericText())
                .transition(.opacity)
        } else {
            Color.clear.frame(height: 16)
        }
    }

    // MARK: - Helpers

    private var trimmedText: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var charCount: Int {
        trimmedText.count
    }

    private var charCountThreshold: Int {
        Int(Double(FondConstants.maxMessageLength) * 0.7)
    }

    private var cooldownProgress: CGFloat {
        guard cooldownRemaining > 0 else { return 0 }
        return CGFloat(cooldownRemaining)
            / CGFloat(FondConstants.rateLimitSeconds)
    }
}

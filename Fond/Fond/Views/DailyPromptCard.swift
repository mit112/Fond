//
//  DailyPromptCard.swift
//  Fond
//
//  Compact daily prompt card for the ConnectedView hub.
//  Shows today's question + both-answer-reveal mechanic.
//
//  States:
//  1. No answer from either → Prompt text + input field
//  2. I answered, waiting for partner → "Waiting for [name]..."
//  3. Both answered → Side-by-side answers revealed
//
//  Design: Glass card matching the Fond design system. Collapsible —
//  shows prompt text by default, expands on tap to show input/answers.
//

import SwiftUI

struct DailyPromptCard: View {
    let partnerName: String
    let uid: String
    let connectionId: String

    @State private var answerText = ""
    @State private var isExpanded = false

    private var promptManager: DailyPromptManager { .shared }

    var body: some View {
        if let prompt = promptManager.todaysPrompt {
            VStack(alignment: .leading, spacing: 14) {
                // Header — tap to expand/collapse
                Button {
                    withAnimation(.fondSpring) {
                        isExpanded.toggle()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Today's Question")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(FondColors.amber)
                                .tracking(0.3)

                            Spacer()

                            promptStatusIcon
                        }

                        Text(prompt.text)
                            .font(.callout.italic().weight(.medium))
                            .fontDesign(.serif)
                            .foregroundStyle(FondColors.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded content
                if isExpanded {
                    Rectangle()
                        .fill(FondColors.amber.opacity(0.15))
                        .frame(height: 1)

                    if promptManager.isSubmitted && promptManager.partnerAnswer != nil {
                        bothAnswersView
                    } else if promptManager.isSubmitted {
                        waitingView
                    } else {
                        answerInput
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .fondGlass(
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                tinted: true
            )
            .onAppear {
                promptManager.computeTodaysPrompt()
            }
        }
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var promptStatusIcon: some View {
        if promptManager.isSubmitted && promptManager.partnerAnswer != nil {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(FondColors.amber)
        } else if promptManager.isSubmitted {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(FondColors.textSecondary)
        } else {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FondColors.textSecondary.opacity(0.5))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
    }

    // MARK: - Answer Input

    private var answerInput: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("What do you think?", text: $answerText, axis: .vertical)
                    .font(.callout)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(FondColors.surface.opacity(0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(FondColors.amber.opacity(0.12), lineWidth: 1)
                    )
                    .submitLabel(.send)
                    .onSubmit { submitAnswer() }

                Button {
                    submitAnswer()
                } label: {
                    Group {
                        if promptManager.isSubmitting {
                            ProgressView()
                                .tint(FondColors.text)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                }
                .disabled(
                    answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || promptManager.isSubmitting
                )
                .fondGlassInteractive(in: Circle(), tinted: true)
            }

            if let error = promptManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(FondColors.rose)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Waiting View

    private var waitingView: some View {
        VStack(spacing: 10) {
            if let myAnswer = promptManager.myAnswer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FondColors.amber)

                    Text(myAnswer)
                        .font(.callout)
                        .foregroundStyle(FondColors.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(FondColors.bubbleMine)
                        )
                }
            }

            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Waiting for \(partnerName)...")
                    .font(.caption)
                    .foregroundStyle(FondColors.textSecondary)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Both Answers View

    private var bothAnswersView: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("You")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FondColors.amber)
                Text(promptManager.myAnswer ?? "")
                    .font(.callout)
                    .foregroundStyle(FondColors.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(FondColors.bubbleMine)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(partnerName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FondColors.lavender)
                Text(promptManager.partnerAnswer ?? "")
                    .font(.callout)
                    .foregroundStyle(FondColors.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(FondColors.bubblePartner)
                    )
            }
        }
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: - Actions

    private func submitAnswer() {
        let text = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        FondHaptics.messageSent()
        answerText = ""

        Task {
            await promptManager.submitAnswer(
                answer: text,
                uid: uid,
                connectionId: connectionId
            )
        }
    }
}

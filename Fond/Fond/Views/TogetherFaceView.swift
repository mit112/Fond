import SwiftUI

struct TodayRitualState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case unanswered
        case waiting(myAnswer: String)
        case revealed(myAnswer: String, partnerAnswer: String)
    }

    let question: String
    let partnerName: String
    let phase: Phase
    let isSubmitting: Bool
    let errorMessage: String?
}

struct TogetherFaceView: View {
    let state: TodayRitualState
    let moments: [TogetherMoment]
    let hasMore: Bool
    let onAnswer: (String) -> Void
    let onLoadMore: () -> Void

    @State private var answerText = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FondSpacing.six) {
                ritualMasthead

                Rectangle()
                    .fill(FondColors.rule)
                    .frame(height: 1)
                    .accessibilityHidden(true)

                TogetherThreadView(
                    moments: moments,
                    partnerName: state.partnerName,
                    hasMore: hasMore,
                    onLoadMore: onLoadMore
                )
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 34)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(FondColors.ink)
    }

    private var ritualMasthead: some View {
        VStack(alignment: .leading, spacing: FondSpacing.four) {
            Text("TODAY")
                .font(FondType.eyebrow)
                .foregroundStyle(FondColors.inkSecondary)

            Text(state.question)
                .font(FondType.question)
                .foregroundStyle(FondColors.ink)
                .fixedSize(horizontal: false, vertical: true)

            ritualPhase

            if let errorMessage = state.errorMessage {
                errorView(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var ritualPhase: some View {
        switch state.phase {
        case .unanswered:
            answerRow

        case let .waiting(myAnswer):
            VStack(alignment: .leading, spacing: FondSpacing.three) {
                Text("YOU")
                    .font(FondType.eyebrow)
                    .foregroundStyle(FondColors.inkSecondary)
                Text(myAnswer)
                    .font(FondType.voice)
                    .foregroundStyle(FondColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(state.partnerName) hasn't answered yet.")
                    .font(FondType.metadata)
                    .foregroundStyle(FondColors.inkSecondary)
            }

        case let .revealed(myAnswer, partnerAnswer):
            RitualAnswerSpread(
                partnerName: state.partnerName,
                myAnswer: myAnswer,
                partnerAnswer: partnerAnswer
            )
        }
    }

    private var answerRow: some View {
        HStack(spacing: FondSpacing.two) {
            Rectangle()
                .fill(FondColors.amber)
                .frame(width: 1)
                .accessibilityHidden(true)

            TextField("Write your answer", text: $answerText, axis: .vertical)
                .font(FondType.body)
                .foregroundStyle(FondColors.ink)
                .lineLimit(1...2)
                .submitLabel(.send)
                .onSubmit(submitAnswer)

            Button(action: submitAnswer) {
                Group {
                    if state.isSubmitting {
                        ProgressView()
                            .tint(FondColors.inkSecondary)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
                .frame(width: FondGeometry.minimumTarget, height: FondGeometry.minimumTarget)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSubmit ? FondColors.amber : FondColors.inkSecondary)
            .disabled(!canSubmit)
            .accessibilityLabel("Send answer")
        }
        .frame(height: 48)
        .padding(.leading, FondSpacing.three)
        .padding(.trailing, 2)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FondColors.controlPlate)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(FondColors.rule, lineWidth: 1)
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FondSpacing.three) {
            Text(message)
                .font(FondType.metadata)
                .foregroundStyle(FondColors.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: FondSpacing.two)

            Button("Try again") {
                if let retryText { onAnswer(retryText) }
            }
            .buttonStyle(.plain)
            .font(FondType.control)
            .foregroundStyle(FondColors.amber)
            .frame(minHeight: FondGeometry.minimumTarget)
            .disabled(retryText == nil || state.isSubmitting)
        }
    }

    private var canSubmit: Bool {
        !state.isSubmitting
            && !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var retryText: String? {
        switch state.phase {
        case .unanswered:
            let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let .waiting(myAnswer), let .revealed(myAnswer, _):
            return myAnswer
        }
    }

    private func submitAnswer() {
        guard canSubmit else { return }
        onAnswer(answerText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct RitualAnswerSpread: View {
    let partnerName: String
    let myAnswer: String
    let partnerAnswer: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var revealMine = false
    @State private var revealPartner = false

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedSpread
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalSpread.frame(minWidth: 340)
                    stackedSpread
                }
            }
        }
        .onAppear(perform: reveal)
        .onChange(of: myAnswer) { _, _ in reveal() }
        .onChange(of: partnerAnswer) { _, _ in reveal() }
    }

    private var horizontalSpread: some View {
        HStack(alignment: .top, spacing: FondSpacing.four) {
            answerVoice("YOU", answer: myAnswer, revealed: revealMine)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(FondColors.rule)
                .frame(width: 1)
                .accessibilityHidden(true)
            answerVoice(partnerName.uppercased(), answer: partnerAnswer, revealed: revealPartner)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stackedSpread: some View {
        VStack(alignment: .leading, spacing: FondSpacing.four) {
            answerVoice("YOU", answer: myAnswer, revealed: revealMine)
            Rectangle()
                .fill(FondColors.rule)
                .frame(height: 1)
                .accessibilityHidden(true)
            answerVoice(partnerName.uppercased(), answer: partnerAnswer, revealed: revealPartner)
        }
    }

    private func answerVoice(_ speaker: String, answer: String, revealed: Bool) -> some View {
        VStack(alignment: .leading, spacing: FondSpacing.two) {
            Text(speaker)
                .font(FondType.eyebrow)
                .foregroundStyle(FondColors.inkSecondary)
            Text(answer)
                .font(FondType.voice)
                .foregroundStyle(FondColors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (revealed ? 0 : 6))
        .mask {
            Rectangle()
                .scaleEffect(x: reduceMotion || revealed ? 1 : 0, anchor: .center)
        }
    }

    private func reveal() {
        revealMine = false
        revealPartner = false
        if reduceMotion {
            withAnimation(.linear(duration: 0.12)) {
                revealMine = true
                revealPartner = true
            }
        } else {
            let animation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)
            withAnimation(animation) { revealMine = true }
            withAnimation(animation.delay(0.07)) { revealPartner = true }
        }
    }
}

private let togetherPreviewMoments: [TogetherMoment] = {
    let now = Date.now
    return [
        TogetherMoment(
            id: "message",
            timestamp: now.addingTimeInterval(-900),
            kind: .message(text: "I saved you the window seat.", author: .partner)
        ),
        TogetherMoment(
            id: "nudge",
            timestamp: now.addingTimeInterval(-1_800),
            kind: .nudge(author: .me)
        ),
        TogetherMoment(
            id: "status",
            timestamp: now.addingTimeInterval(-3_600),
            kind: .status(status: .sleeping, label: "Sleeping", author: .partner)
        ),
        TogetherMoment(
            id: "question",
            timestamp: now.addingTimeInterval(-90_000),
            kind: .answeredQuestion(
                question: "What ordinary moment would you keep?",
                myAnswer: "The walk home",
                partnerAnswer: "Morning coffee"
            )
        ),
    ]
}()

private func togetherPreviewState(_ phase: TodayRitualState.Phase) -> TodayRitualState {
    TodayRitualState(
        question: "What's one small thing you're looking forward to?",
        partnerName: "Maya",
        phase: phase,
        isSubmitting: false,
        errorMessage: nil
    )
}

#Preview("Together — Unanswered") {
    TogetherFaceView(
        state: togetherPreviewState(.unanswered),
        moments: togetherPreviewMoments,
        hasMore: true,
        onAnswer: { _ in },
        onLoadMore: {}
    )
    .fondKeepsakeCard()
    .padding(20)
    .background(FondColors.field)
}

#Preview("Together — Waiting Dark") {
    TogetherFaceView(
        state: togetherPreviewState(.waiting(myAnswer: "The train pulling in.")),
        moments: togetherPreviewMoments,
        hasMore: false,
        onAnswer: { _ in },
        onLoadMore: {}
    )
    .fondKeepsakeCard()
    .padding(20)
    .background(FondColors.field)
    .preferredColorScheme(.dark)
}

#Preview("Together — Revealed") {
    TogetherFaceView(
        state: togetherPreviewState(.revealed(
            myAnswer: "The train pulling in.",
            partnerAnswer: "Coffee before the city wakes."
        )),
        moments: togetherPreviewMoments,
        hasMore: false,
        onAnswer: { _ in },
        onLoadMore: {}
    )
    .fondKeepsakeCard()
    .padding(20)
    .background(FondColors.field)
}

#Preview("Together — Empty Thread") {
    TogetherFaceView(
        state: togetherPreviewState(.unanswered),
        moments: [],
        hasMore: false,
        onAnswer: { _ in },
        onLoadMore: {}
    )
    .fondKeepsakeCard()
    .padding(20)
    .background(FondColors.field)
}

#Preview("Together — Mixed Thread AX5") {
    TogetherFaceView(
        state: togetherPreviewState(.revealed(
            myAnswer: "The train pulling in.",
            partnerAnswer: "Coffee before the city wakes."
        )),
        moments: togetherPreviewMoments,
        hasMore: true,
        onAnswer: { _ in },
        onLoadMore: {}
    )
    .fondKeepsakeCard()
    .padding(20)
    .background(FondColors.field)
    .dynamicTypeSize(.accessibility5)
}

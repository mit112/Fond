import SwiftUI

struct TogetherThreadView: View {
    let moments: [TogetherMoment]
    let partnerName: String
    let hasMore: Bool
    let onLoadMore: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        LazyVStack(alignment: .leading, spacing: FondSpacing.six) {
            if moments.isEmpty {
                Text("Answer today's question to start your story.")
                    .font(FondType.voice)
                    .foregroundStyle(FondColors.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, FondSpacing.five)
            } else {
                ForEach(TogetherMomentBuilder.groupByDay(moments)) { group in
                    dayGroup(group)
                }
            }

            if hasMore {
                Button("Load earlier moments", action: onLoadMore)
                    .buttonStyle(.plain)
                    .font(FondType.control)
                    .foregroundStyle(FondColors.amber)
                    .frame(minHeight: FondGeometry.minimumTarget)
            }
        }
    }

    private func dayGroup(_ group: TogetherDayGroup) -> some View {
        VStack(alignment: .leading, spacing: FondSpacing.five) {
            HStack(spacing: FondSpacing.three) {
                Text(dayLabel(group.day).uppercased())
                    .font(FondType.eyebrow)
                    .foregroundStyle(FondColors.inkSecondary)
                Rectangle()
                    .fill(FondColors.rule)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }

            ForEach(group.moments) { moment in
                momentView(moment)
            }
        }
    }

    @ViewBuilder
    private func momentView(_ moment: TogetherMoment) -> some View {
        switch moment.kind {
        case let .message(text, author):
            messageMoment(text: text, author: author, timestamp: moment.timestamp)

        case let .status(status, label, author):
            statusMoment(status: status, label: label, author: author, timestamp: moment.timestamp)

        case let .nudge(author):
            nudgeMoment(author: author, timestamp: moment.timestamp)

        case let .heartbeat(bpm, author):
            heartbeatMoment(bpm: bpm, author: author, timestamp: moment.timestamp)

        case let .answeredQuestion(question, myAnswer, partnerAnswer):
            answeredQuestionMoment(
                question: question,
                myAnswer: myAnswer,
                partnerAnswer: partnerAnswer
            )

        case .unavailable:
            Text("This moment is unavailable.")
                .font(FondType.metadata)
                .foregroundStyle(FondColors.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func messageMoment(
        text: String,
        author: TogetherMoment.Author,
        timestamp: Date
    ) -> some View {
        HStack {
            if author == .me { Spacer(minLength: FondSpacing.six) }

            VStack(alignment: author == .me ? .trailing : .leading, spacing: FondSpacing.two) {
                Text("\(speaker(author)) · \(timeLabel(timestamp))")
                    .font(FondType.metadata)
                    .foregroundStyle(FondColors.inkSecondary)

                HStack(alignment: .top, spacing: FondSpacing.three) {
                    if author == .partner { messageRule(FondColors.amber) }
                    Text(text)
                        .font(FondType.voice)
                        .foregroundStyle(FondColors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if author == .me { messageRule(FondColors.rule) }
                }
            }
            .containerRelativeFrame(.horizontal) { length, _ in
                length * (horizontalSizeClass == .regular ? 0.62 : 0.78)
            }

            if author == .partner { Spacer(minLength: FondSpacing.six) }
        }
    }

    private func messageRule(_ color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 2)
            .accessibilityHidden(true)
    }

    private func nudgeMoment(
        author: TogetherMoment.Author,
        timestamp: Date
    ) -> some View {
        HStack(spacing: FondSpacing.two) {
            Text("◉")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(FondColors.amber)
                .accessibilityHidden(true)
            Text("\(nudgeLabel(author)) · \(timeLabel(timestamp))")
                .font(FondType.metadata)
                .foregroundStyle(FondColors.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func statusMoment(
        status: UserStatus?,
        label: String,
        author: TogetherMoment.Author,
        timestamp: Date
    ) -> some View {
        HStack(spacing: FondSpacing.two) {
            Circle()
                .fill(status?.statusColor ?? FondColors.inkSecondary)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text("\(statusSubject(author)) \(label.lowercased()) · \(timeLabel(timestamp))")
                .font(FondType.metadata)
                .foregroundStyle(FondColors.inkSecondary)
        }
    }

    private func heartbeatMoment(
        bpm: Int?,
        author: TogetherMoment.Author,
        timestamp: Date
    ) -> some View {
        HStack(spacing: FondSpacing.two) {
            Image(systemName: "heart")
                .foregroundStyle(FondColors.inkSecondary)
            Text(heartbeatLabel(bpm: bpm, author: author, timestamp: timestamp))
                .font(FondType.metadata)
                .foregroundStyle(FondColors.inkSecondary)
        }
    }

    private func answeredQuestionMoment(
        question: String,
        myAnswer: String?,
        partnerAnswer: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: FondSpacing.four) {
            Rectangle()
                .fill(FondColors.rule)
                .frame(height: 1)
                .accessibilityHidden(true)

            Text(question)
                .font(FondType.momentQuestion)
                .foregroundStyle(FondColors.ink)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: FondSpacing.four) {
                    threadVoice("YOU", answer: myAnswer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(FondColors.rule).frame(width: 1)
                    threadVoice(partnerName.uppercased(), answer: partnerAnswer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 340)

                VStack(alignment: .leading, spacing: FondSpacing.four) {
                    threadVoice("YOU", answer: myAnswer)
                    Rectangle().fill(FondColors.rule).frame(height: 1)
                    threadVoice(partnerName.uppercased(), answer: partnerAnswer)
                }
            }
        }
    }

    private func threadVoice(_ speaker: String, answer: String?) -> some View {
        VStack(alignment: .leading, spacing: FondSpacing.one) {
            Text(speaker)
                .font(FondType.eyebrow)
                .foregroundStyle(FondColors.inkSecondary)
            Text(answer ?? "Answer unavailable")
                .font(FondType.voice)
                .foregroundStyle(answer == nil ? FondColors.inkSecondary : FondColors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func speaker(_ author: TogetherMoment.Author) -> String {
        author == .me ? "You" : partnerName
    }

    private func statusSubject(_ author: TogetherMoment.Author) -> String {
        author == .me ? "You are" : "\(partnerName) is"
    }

    private func nudgeLabel(_ author: TogetherMoment.Author) -> String {
        author == .me ? "You sent a nudge" : "\(partnerName) nudged you"
    }

    private func heartbeatLabel(
        bpm: Int?,
        author: TogetherMoment.Author,
        timestamp: Date
    ) -> String {
        let subject = speaker(author)
        let detail = bpm.map { "\($0) bpm" } ?? "a heartbeat"
        return "\(subject) shared \(detail) · \(timeLabel(timestamp))"
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Earlier today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func timeLabel(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

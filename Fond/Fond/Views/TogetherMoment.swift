import Foundation

struct TogetherMoment: Identifiable, Equatable, Sendable {
    enum Author: Equatable, Sendable {
        case me
        case partner
    }

    enum Kind: Equatable, Sendable {
        case message(text: String, author: Author)
        case status(status: UserStatus?, label: String, author: Author)
        case nudge(author: Author)
        case heartbeat(bpm: Int?, author: Author)
        case answeredQuestion(question: String, myAnswer: String?, partnerAnswer: String?)
        case unavailable
    }

    let id: String
    let timestamp: Date
    let kind: Kind
}

struct TogetherDayGroup: Identifiable, Equatable, Sendable {
    let day: Date
    let moments: [TogetherMoment]

    var id: Date { day }
}

enum TogetherMomentBuilder {
    static func build(
        entries: [FondMessage],
        myUid: String,
        decrypt: (String) -> String?,
        promptText: (String) -> String?
    ) -> [TogetherMoment] {
        var moments: [TogetherMoment] = []
        var answersByPrompt: [String: PromptAnswers] = [:]

        for entry in entries {
            let author: TogetherMoment.Author = entry.authorUid == myUid ? .me : .partner
            guard let plaintext = decrypt(entry.encryptedPayload) else {
                moments.append(unavailable(entry))
                continue
            }

            switch entry.type {
            case .message:
                let text = plaintext.trimmingCharacters(in: .whitespacesAndNewlines)
                moments.append(
                    text.isEmpty
                        ? unavailable(entry)
                        : TogetherMoment(
                            id: entry.id,
                            timestamp: entry.timestamp,
                            kind: .message(text: text, author: author)
                        )
                )

            case .status:
                let rawValue = plaintext.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawValue.isEmpty else {
                    moments.append(unavailable(entry))
                    continue
                }
                let status = UserStatus(rawValue: rawValue)
                let label = UserStatus.displayInfo(forRawValue: rawValue).displayName
                moments.append(TogetherMoment(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    kind: .status(status: status, label: label, author: author)
                ))

            case .nudge:
                moments.append(TogetherMoment(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    kind: .nudge(author: author)
                ))

            case .heartbeat:
                guard let payload = decode(HeartbeatPayload.self, from: plaintext) else {
                    moments.append(unavailable(entry))
                    continue
                }
                moments.append(TogetherMoment(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    kind: .heartbeat(bpm: payload.bpm, author: author)
                ))

            case .promptAnswer:
                guard let payload = decode(PromptAnswerPayload.self, from: plaintext),
                      !payload.promptId.isEmpty,
                      !payload.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    moments.append(unavailable(entry))
                    continue
                }
                let answer = PromptAnswer(
                    id: entry.id,
                    text: payload.answer.trimmingCharacters(in: .whitespacesAndNewlines),
                    timestamp: entry.timestamp
                )
                var pair = answersByPrompt[payload.promptId] ?? PromptAnswers()
                pair.store(answer, for: author)
                answersByPrompt[payload.promptId] = pair
            }
        }

        for (promptID, answers) in answersByPrompt {
            guard let latest = answers.latest else { continue }
            guard let question = promptText(promptID) else {
                moments.append(TogetherMoment(
                    id: latest.id,
                    timestamp: latest.timestamp,
                    kind: .unavailable
                ))
                continue
            }
            moments.append(TogetherMoment(
                id: "prompt-\(promptID)",
                timestamp: latest.timestamp,
                kind: .answeredQuestion(
                    question: question,
                    myAnswer: answers.mine?.text,
                    partnerAnswer: answers.partner?.text
                )
            ))
        }

        return moments.sorted {
            if $0.timestamp == $1.timestamp { return $0.id > $1.id }
            return $0.timestamp > $1.timestamp
        }
    }

    static func groupByDay(
        _ moments: [TogetherMoment],
        calendar: Calendar = .current
    ) -> [TogetherDayGroup] {
        Dictionary(grouping: moments) { calendar.startOfDay(for: $0.timestamp) }
            .map { day, moments in
                TogetherDayGroup(
                    day: day,
                    moments: moments.sorted {
                        if $0.timestamp == $1.timestamp { return $0.id > $1.id }
                        return $0.timestamp > $1.timestamp
                    }
                )
            }
            .sorted { $0.day > $1.day }
    }

    private static func unavailable(_ entry: FondMessage) -> TogetherMoment {
        TogetherMoment(id: entry.id, timestamp: entry.timestamp, kind: .unavailable)
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from plaintext: String
    ) -> Value? {
        guard let data = plaintext.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

private struct HeartbeatPayload: Decodable {
    let bpm: Int?
}

private struct PromptAnswerPayload: Decodable {
    let promptId: String
    let answer: String
}

private struct PromptAnswer {
    let id: String
    let text: String
    let timestamp: Date
}

private struct PromptAnswers {
    var mine: PromptAnswer?
    var partner: PromptAnswer?

    var latest: PromptAnswer? {
        [mine, partner]
            .compactMap { $0 }
            .max { $0.timestamp < $1.timestamp }
    }

    mutating func store(_ answer: PromptAnswer, for author: TogetherMoment.Author) {
        switch author {
        case .me:
            if mine == nil || answer.timestamp >= mine!.timestamp { mine = answer }
        case .partner:
            if partner == nil || answer.timestamp >= partner!.timestamp { partner = answer }
        }
    }
}

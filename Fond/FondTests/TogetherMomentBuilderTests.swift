import Foundation
import Testing
@testable import Fond

@MainActor
struct TogetherMomentBuilderTests {
    @Test func buildsEditorialMomentsAndPairsAnswers() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let fixtures = [
            FondMessage(id: "m1", authorUid: "me", type: .message, encryptedPayload: "Miss you", timestamp: now),
            FondMessage(id: "s1", authorUid: "partner", type: .status, encryptedPayload: "sleeping", timestamp: now.addingTimeInterval(1)),
            FondMessage(id: "n1", authorUid: "me", type: .nudge, encryptedPayload: "💛", timestamp: now.addingTimeInterval(2)),
            FondMessage(id: "h1", authorUid: "partner", type: .heartbeat, encryptedPayload: "{\"bpm\":72}", timestamp: now.addingTimeInterval(3)),
            FondMessage(id: "p1", authorUid: "me", type: .promptAnswer, encryptedPayload: "{\"promptId\":\"p001\",\"answer\":\"The walk home\"}", timestamp: now.addingTimeInterval(4)),
            FondMessage(id: "p2", authorUid: "partner", type: .promptAnswer, encryptedPayload: "{\"promptId\":\"p001\",\"answer\":\"Morning coffee\"}", timestamp: now.addingTimeInterval(5)),
        ]
        let moments = TogetherMomentBuilder.build(
            entries: fixtures,
            myUid: "me",
            decrypt: { $0 },
            promptText: { $0 == "p001" ? "What ordinary moment would you keep?" : nil }
        )
        #expect(moments.contains { $0.kind == .message(text: "Miss you", author: .me) })
        #expect(moments.contains { $0.kind == .status(status: .sleeping, label: "Sleeping", author: .partner) })
        #expect(moments.contains { $0.kind == .nudge(author: .me) })
        #expect(moments.contains { $0.kind == .heartbeat(bpm: 72, author: .partner) })
        #expect(moments.contains { $0.kind == .answeredQuestion(question: "What ordinary moment would you keep?", myAnswer: "The walk home", partnerAnswer: "Morning coffee") })
    }

    @Test func malformedPayloadBecomesUnavailableWithoutCiphertext() {
        let ciphertext = "not-plaintext-or-json"
        let entries = [
            FondMessage(
                id: "bad-heartbeat",
                authorUid: "partner",
                type: .heartbeat,
                encryptedPayload: ciphertext,
                timestamp: Date(timeIntervalSince1970: 1_767_225_600)
            ),
        ]

        let moments = TogetherMomentBuilder.build(
            entries: entries,
            myUid: "me",
            decrypt: { $0 },
            promptText: { _ in nil }
        )

        #expect(moments == [TogetherMoment(
            id: "bad-heartbeat",
            timestamp: entries[0].timestamp,
            kind: .unavailable
        )])
        #expect(!String(describing: moments).contains(ciphertext))
    }

    @Test func preservesUnknownStatusLabel() {
        let entry = FondMessage(
            id: "future-status",
            authorUid: "partner",
            type: .status,
            encryptedPayload: "deepFocus",
            timestamp: Date(timeIntervalSince1970: 1_767_225_600)
        )

        let moments = TogetherMomentBuilder.build(
            entries: [entry],
            myUid: "me",
            decrypt: { $0 },
            promptText: { _ in nil }
        )

        #expect(moments.first?.kind == .status(
            status: nil,
            label: "Deep Focus",
            author: .partner
        ))
    }
}

@MainActor
private final class MockHistoryProvider: HistoryProviding {
    var pages: [HistoryPage]
    private(set) var resetCount = 0

    init(pages: [HistoryPage]) {
        self.pages = pages
    }

    func reset() {
        resetCount += 1
    }

    func nextPage(connectionId: String) async throws -> HistoryPage {
        pages.removeFirst()
    }
}

struct TogetherThreadStoreTests {
    @Test @MainActor func resetsLoadsMoreAndKeepsFirstCopyOfDuplicateIDs() async {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let newest = FondMessage(
            id: "m1",
            authorUid: "me",
            type: .message,
            encryptedPayload: "Newest copy",
            timestamp: now
        )
        let duplicateFromOlderPage = FondMessage(
            id: "m1",
            authorUid: "me",
            type: .message,
            encryptedPayload: "Older duplicate",
            timestamp: now.addingTimeInterval(-100)
        )
        let older = FondMessage(
            id: "m2",
            authorUid: "partner",
            type: .message,
            encryptedPayload: "Earlier moment",
            timestamp: now.addingTimeInterval(-200)
        )
        let provider = MockHistoryProvider(pages: [
            HistoryPage(entries: [newest], hasMore: true),
            HistoryPage(entries: [duplicateFromOlderPage, older], hasMore: false),
        ])
        let store = TogetherThreadStore(
            provider: provider,
            myUid: "me",
            decrypt: { $0 },
            promptText: { _ in nil }
        )

        await store.loadInitial(connectionId: "connection")
        await store.loadMore(connectionId: "connection")

        #expect(provider.resetCount == 1)
        #expect(store.hasMore == false)
        #expect(store.moments.count == 2)
        #expect(store.moments.first?.kind == .message(text: "Newest copy", author: .me))
    }
}

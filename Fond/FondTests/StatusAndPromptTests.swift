import Foundation
import Testing

@testable import Fond

struct StatusAndPromptTests {

  // MARK: - UserStatus

  @Test func unknownStatusDegradesGracefully() {
    let info = UserStatus.displayInfo(forRawValue: "totally-made-up-status")
    #expect(!info.displayName.isEmpty)
    #expect(info.emoji == "💬")
  }

  @Test func knownStatusMapsToItsRealEmojiAndDisplayName() {
    let info = UserStatus.displayInfo(forRawValue: "lovingYou")
    #expect(info.emoji == "🥰")
    #expect(info.displayName == "Loving You")
  }

  @Test func rawValuesStayStableForTheFirestoreContract() {
    // These raw values are stored in Firestore — never rename them.
    #expect(UserStatus.thinkingOfYou.rawValue == "thinkingOfYou")
    #expect(UserStatus.missYou.rawValue == "missYou")
    #expect(UserStatus.lovingYou.rawValue == "lovingYou")
    #expect(UserStatus.allCases.count == 16)
  }

  // MARK: - DailyPromptManager

  @Test func computeTodaysPromptIsIdempotentPerUTCDay() {
    DailyPromptManager.shared.computeTodaysPrompt()
    let first = DailyPromptManager.shared.todaysPrompt
    DailyPromptManager.shared.computeTodaysPrompt()
    let second = DailyPromptManager.shared.todaysPrompt

    #expect(second != nil)
    #expect(first?.id == second?.id)
  }

  @Test func promptTextLookupRoundTripsAndMissesGracefully() throws {
    let prompt = try #require(DailyPromptManager.shared.todaysPrompt)
    #expect(DailyPromptManager.shared.promptText(forID: prompt.id) == prompt.text)
    #expect(DailyPromptManager.shared.promptText(forID: "no-such-id") == nil)
  }

  // MARK: - FondMessage

  @Test func entryTypeRawValuesStayStableForTheHistoryContract() {
    // These raw values are stored in history documents — never rename them.
    #expect(FondMessage.EntryType.status.rawValue == "status")
    #expect(FondMessage.EntryType.message.rawValue == "message")
    #expect(FondMessage.EntryType.nudge.rawValue == "nudge")
    #expect(FondMessage.EntryType.heartbeat.rawValue == "heartbeat")
    #expect(FondMessage.EntryType.promptAnswer.rawValue == "promptAnswer")
  }

  // FondMessage's synthesized Codable conformance is main-actor isolated
  // (the Fond target builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor),
  // so encode/decode calls must happen on the main actor.
  @Test @MainActor func codableRoundTripsAllFields() throws {
    let original = FondMessage(
      id: "msg-1",
      authorUid: "uid-abc",
      type: .nudge,
      encryptedPayload: "base64ciphertext==",
      timestamp: Date(timeIntervalSince1970: 1_767_225_600)
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(FondMessage.self, from: data)

    #expect(decoded.id == original.id)
    #expect(decoded.authorUid == original.authorUid)
    #expect(decoded.type == original.type)
    #expect(decoded.encryptedPayload == original.encryptedPayload)
    #expect(abs(decoded.timestamp.timeIntervalSince(original.timestamp)) < 0.001)
  }

  @Test @MainActor func decodesRawTypeStringIntoTheMatchingCase() throws {
    let json = Data(
      """
      {"id":"m1","authorUid":"u1","type":"nudge","encryptedPayload":"cipher","timestamp":790000000}
      """.utf8)

    let decoded = try JSONDecoder().decode(FondMessage.self, from: json)
    #expect(decoded.type == .nudge)
  }
}

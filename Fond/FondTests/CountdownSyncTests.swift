import CryptoKit
import Foundation
import Testing

@testable import Fond

// Mutates the shared App Group + Keychain singletons, so serialize.
@Suite(.serialized) struct CountdownSyncTests {

  private func seedKey() throws {
    try? KeychainManager.shared.deleteAllKeys()
    let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    try KeychainManager.shared.saveSymmetricKey(key)
  }

  private func appGroup() -> UserDefaults? {
    UserDefaults(suiteName: FondConstants.appGroupID)
  }

  private func clearCountdownKeys() {
    let defaults = appGroup()
    defaults?.removeObject(forKey: FondConstants.countdownDateKey)
    defaults?.removeObject(forKey: FondConstants.countdownLabelKey)
  }

  @Test @MainActor func writesAndClearsCountdownInAppGroup() async throws {
    try seedKey()
    defer { try? KeychainManager.shared.deleteAllKeys() }
    clearCountdownKeys()

    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let enc = try EncryptionManager.shared.encrypt("Our trip ✈️")

    // Second device receives its own doc's countdown fields and decrypts them.
    await FirebaseManager.shared.writeOwnCountdownToAppGroup(
      countdownDate: date,
      encryptedLabel: enc
    )

    let defaults = appGroup()
    #expect(defaults?.object(forKey: FondConstants.countdownDateKey) as? Date == date)
    #expect(defaults?.string(forKey: FondConstants.countdownLabelKey) == "Our trip ✈️")

    // Countdown cleared upstream → both keys are removed locally.
    await FirebaseManager.shared.writeOwnCountdownToAppGroup(
      countdownDate: nil,
      encryptedLabel: nil
    )

    #expect(defaults?.object(forKey: FondConstants.countdownDateKey) == nil)
    #expect(defaults?.object(forKey: FondConstants.countdownLabelKey) == nil)

    clearCountdownKeys()
  }
}

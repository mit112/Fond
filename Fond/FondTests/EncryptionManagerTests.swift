import CryptoKit
import Foundation
import Testing

@testable import Fond

@Suite(.serialized) struct EncryptionManagerTests {
  private func seedKey() throws {
    try? KeychainManager.shared.deleteAllKeys()
    let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    try KeychainManager.shared.saveSymmetricKey(key)
  }

  @Test func roundTripsThroughStoredKey() throws {
    try seedKey()
    let cipher = try EncryptionManager.shared.encrypt("hello 💛")
    #expect(try EncryptionManager.shared.decrypt(cipher) == "hello 💛")
    try KeychainManager.shared.deleteAllKeys()
  }

  @Test func missingKeyThrows() throws {
    try? KeychainManager.shared.deleteAllKeys()
    #expect(throws: EncryptionError.missingKey) {
      _ = try EncryptionManager.shared.encrypt("x")
    }
  }

  @Test func invalidCiphertextThrows() throws {
    try seedKey()
    #expect(throws: EncryptionError.invalidCiphertext) {
      _ = try EncryptionManager.shared.decrypt("not-base64-@@@")
    }
    try KeychainManager.shared.deleteAllKeys()
  }

  @Test func decryptOrNilReturnsNilOnFailure() throws {
    try? KeychainManager.shared.deleteAllKeys()
    #expect(EncryptionManager.shared.decryptOrNil("anything") == nil)
    #expect(EncryptionManager.shared.decryptOrNil(nil) == nil)
  }
}

import Foundation
import Testing

@testable import Fond

@Suite(.serialized) struct KeyExchangeManagerTests {
  @Test func generatesStoresAndReportsAvailability() throws {
    try? KeychainManager.shared.deleteAllKeys()
    let pub = try KeyExchangeManager.shared.generateAndStoreKeyPair()
    #expect(!pub.isEmpty)
    #expect(Data(base64Encoded: pub) != nil)
    #expect(KeyExchangeManager.shared.hasPrivateKey)
    try KeychainManager.shared.deleteAllKeys()
  }

  @Test func invalidPartnerKeyThrows() throws {
    try? KeychainManager.shared.deleteAllKeys()
    _ = try KeyExchangeManager.shared.generateAndStoreKeyPair()
    #expect(throws: (any Error).self) {
      try KeyExchangeManager.shared.deriveAndStoreSymmetricKey(partnerPublicKeyBase64: "!!!")
    }
    try KeychainManager.shared.deleteAllKeys()
  }

  @Test func missingPrivateKeyThrows() throws {
    try? KeychainManager.shared.deleteAllKeys()
    let throwaway = try KeyExchangeManager.shared.generateAndStoreKeyPair()  // valid public key
    try KeychainManager.shared.deleteAllKeys()  // remove the private key
    #expect(throws: KeyExchangeError.missingPrivateKey) {
      try KeyExchangeManager.shared.deriveAndStoreSymmetricKey(partnerPublicKeyBase64: throwaway)
    }
  }
}

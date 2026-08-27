import Foundation
import Testing

@testable import Fond

@Suite(.serialized) struct KeychainManagerTests {
  @Test func savesLoadsAndDeletesSymmetricKey() throws {
    try? KeychainManager.shared.deleteAllKeys()
    let key = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
    try KeychainManager.shared.saveSymmetricKey(key)
    #expect(KeychainManager.shared.loadSymmetricKey() == key)
    try KeychainManager.shared.deleteAllKeys()
    #expect(KeychainManager.shared.loadSymmetricKey() == nil)
  }

  @Test func saveOverwritesExisting() throws {
    try? KeychainManager.shared.deleteAllKeys()
    try KeychainManager.shared.savePrivateKey(Data([0x01]))
    try KeychainManager.shared.savePrivateKey(Data([0x02]))
    #expect(KeychainManager.shared.loadPrivateKey() == Data([0x02]))
    try KeychainManager.shared.deleteAllKeys()
  }
}

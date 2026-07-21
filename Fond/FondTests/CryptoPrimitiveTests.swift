import CryptoKit
import Foundation
import Testing

struct CryptoPrimitiveTests {
  // AES-256-GCM round-trip with the combined nonce+ct+tag layout Fond stores.
  @Test func aesGcmRoundTripCombined() throws {
    let key = SymmetricKey(size: .bits256)
    let plaintext = Data("made coffee, thinking about our trip".utf8)
    let sealed = try AES.GCM.seal(plaintext, using: key)
    let combined = try #require(sealed.combined)
    let reopened = try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key)
    #expect(reopened == plaintext)
  }

  // Tamper detection: flipping any ciphertext byte must fail authentication.
  @Test func aesGcmTamperIsRejected() throws {
    let key = SymmetricKey(size: .bits256)
    let sealed = try AES.GCM.seal(Data("miss you".utf8), using: key)
    var combined = try #require(sealed.combined)
    combined[combined.count - 1] ^= 0x01  // corrupt the tag
    #expect(throws: (any Error).self) {
      _ = try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key)
    }
  }

  // Both partners derive the identical symmetric key (the E2E promise).
  @Test func x25519BothSidesDeriveIdenticalKey() throws {
    let a = Curve25519.KeyAgreement.PrivateKey()
    let b = Curve25519.KeyAgreement.PrivateKey()
    let keyA = try deriveKey(myPrivate: a, theirPublic: b.publicKey)
    let keyB = try deriveKey(myPrivate: b, theirPublic: a.publicKey)
    #expect(keyA == keyB)
  }

  // Domain separation: the "Fond-E2E-v1" sharedInfo must change the derived key.
  @Test func hkdfSharedInfoProvidesDomainSeparation() throws {
    let a = Curve25519.KeyAgreement.PrivateKey()
    let b = Curve25519.KeyAgreement.PrivateKey()
    let secretA = try a.sharedSecretFromKeyAgreement(with: b.publicKey)
    let v1 = secretA.hkdfDerivedSymmetricKey(
      using: SHA256.self, salt: Data("Fond-v1".utf8), sharedInfo: Data("Fond-E2E-v1".utf8),
      outputByteCount: 32)
    let other = secretA.hkdfDerivedSymmetricKey(
      using: SHA256.self, salt: Data("Fond-v1".utf8), sharedInfo: Data("Fond-E2E-v2".utf8),
      outputByteCount: 32)
    #expect(v1 != other)
  }

  private func deriveKey(
    myPrivate: Curve25519.KeyAgreement.PrivateKey,
    theirPublic: Curve25519.KeyAgreement.PublicKey
  ) throws -> SymmetricKey {
    try myPrivate.sharedSecretFromKeyAgreement(with: theirPublic)
      .hkdfDerivedSymmetricKey(
        using: SHA256.self,
        salt: Data("Fond-v1".utf8),
        sharedInfo: Data("Fond-E2E-v1".utf8),
        outputByteCount: 32)
  }
}

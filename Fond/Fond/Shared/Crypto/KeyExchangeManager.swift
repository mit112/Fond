//
//  KeyExchangeManager.swift
//  Fond
//
//  X25519 Diffie-Hellman key exchange using CryptoKit.
//  Generates key pairs, derives shared secret, produces AES-256-GCM key via HKDF.
//

import Foundation
import CryptoKit

final class KeyExchangeManager: Sendable {
    static let shared = KeyExchangeManager()
    private init() {}

    // MARK: - Key Pair Generation

    /// Generates a new X25519 key pair.
    /// Private key is stored in Keychain. Public key (Base64) is returned for Firestore.
    func generateAndStoreKeyPair() throws -> String {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        // Store private key in Keychain (syncs via iCloud Keychain)
        try KeychainManager.shared.savePrivateKey(privateKey.rawRepresentation)

        // Return public key as Base64 for Firestore
        return privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    // MARK: - Shared Secret Derivation

    /// Derives a symmetric AES-256 key from our private key + partner's public key.
    /// Stores the derived symmetric key in Keychain.
    func deriveAndStoreSymmetricKey(partnerPublicKeyBase64: String) throws {
        // Load our private key from Keychain
        guard let privateKeyData = KeychainManager.shared.loadPrivateKey() else {
            throw KeyExchangeError.missingPrivateKey
        }

        guard let partnerPublicKeyData = Data(base64Encoded: partnerPublicKeyBase64) else {
            throw KeyExchangeError.invalidPublicKey
        }

        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        let partnerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: partnerPublicKeyData)

        // Diffie-Hellman shared secret
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: partnerPublicKey)

        // HKDF to derive a 256-bit symmetric key
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "Fond-v1".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )

        // Store the symmetric key in Keychain
        let keyData = symmetricKey.withUnsafeBytes { Data($0) }
        try KeychainManager.shared.saveSymmetricKey(keyData)
    }

    // MARK: - Key Availability

    /// Returns true if a symmetric key exists in Keychain (ready to encrypt/decrypt).
    var hasSymmetricKey: Bool {
        KeychainManager.shared.loadSymmetricKey() != nil
    }

    /// Returns true if a private key exists in Keychain.
    var hasPrivateKey: Bool {
        KeychainManager.shared.loadPrivateKey() != nil
    }
}

// MARK: - Errors

enum KeyExchangeError: LocalizedError {
    case missingPrivateKey
    case invalidPublicKey

    var errorDescription: String? {
        switch self {
        case .missingPrivateKey:
            return "Encryption key not found. Waiting for iCloud Keychain sync."
        case .invalidPublicKey:
            return "Partner's public key is invalid."
        }
    }
}

//
//  EncryptionManager.swift
//  Fond
//
//  AES-256-GCM encryption and decryption using CryptoKit.
//  Each encryption produces a unique nonce. Output is nonce + ciphertext + tag,
//  all combined and Base64-encoded for Firestore storage.
//

import Foundation
import CryptoKit

final class EncryptionManager: Sendable {
    static let shared = EncryptionManager()
    private init() {}

    // MARK: - Encrypt

    /// Encrypts a plaintext string using AES-256-GCM with the stored symmetric key.
    /// Returns Base64-encoded ciphertext (nonce + ciphertext + tag).
    func encrypt(_ plaintext: String) throws -> String {
        guard let keyData = KeychainManager.shared.loadSymmetricKey() else {
            throw EncryptionError.missingKey
        }

        let key = SymmetricKey(data: keyData)
        let plaintextData = Data(plaintext.utf8)

        let sealedBox = try AES.GCM.seal(plaintextData, using: key)

        // combined = nonce (12 bytes) + ciphertext + tag (16 bytes)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        return combined.base64EncodedString()
    }

    // MARK: - Decrypt

    /// Decrypts a Base64-encoded ciphertext using AES-256-GCM with the stored symmetric key.
    /// Returns the plaintext string, or nil if decryption fails.
    func decrypt(_ base64Ciphertext: String) throws -> String {
        guard let keyData = KeychainManager.shared.loadSymmetricKey() else {
            throw EncryptionError.missingKey
        }

        guard let combined = Data(base64Encoded: base64Ciphertext) else {
            throw EncryptionError.invalidCiphertext
        }

        let key = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }

        return plaintext
    }

    // MARK: - Convenience

    /// Tries to decrypt, returns nil on any failure (for widget fallback).
    func decryptOrNil(_ base64Ciphertext: String?) -> String? {
        guard let ciphertext = base64Ciphertext else { return nil }
        return try? decrypt(ciphertext)
    }
}

// MARK: - Errors

enum EncryptionError: LocalizedError {
    case missingKey
    case encryptionFailed
    case invalidCiphertext
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Encryption key not available. Waiting for sync."
        case .encryptionFailed:
            return "Failed to encrypt data."
        case .invalidCiphertext:
            return "Invalid encrypted data."
        case .decryptionFailed:
            return "Failed to decrypt data."
        }
    }
}

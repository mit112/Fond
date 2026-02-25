//
//  KeychainManager.swift
//  Fond
//
//  Keychain CRUD for encryption keys.
//  Keys are stored with kSecAttrSynchronizable = true for iCloud Keychain sync
//  across the user's own devices. Shared App Group keychain so widget can access.
//

import Foundation
import Security

final class KeychainManager: Sendable {
    static let shared = KeychainManager()
    private init() {}

    // MARK: - Key Tags

    private enum Tag {
        static let privateKey = "com.mitsheth.Fond.privateKey"
        static let symmetricKey = "com.mitsheth.Fond.symmetricKey"
    }

    // MARK: - Save

    func savePrivateKey(_ keyData: Data) throws {
        try save(data: keyData, tag: Tag.privateKey)
    }

    func saveSymmetricKey(_ keyData: Data) throws {
        try save(data: keyData, tag: Tag.symmetricKey)
    }

    // MARK: - Load

    func loadPrivateKey() -> Data? {
        load(tag: Tag.privateKey)
    }

    func loadSymmetricKey() -> Data? {
        load(tag: Tag.symmetricKey)
    }

    // MARK: - Delete

    func deletePrivateKey() throws {
        try delete(tag: Tag.privateKey)
    }

    func deleteSymmetricKey() throws {
        try delete(tag: Tag.symmetricKey)
    }

    /// Deletes all Fond keys from keychain (used on unlink).
    func deleteAllKeys() throws {
        try? delete(tag: Tag.privateKey)
        try? delete(tag: Tag.symmetricKey)
    }

    // MARK: - Generic Keychain Operations

    private func save(data: Data, tag: String) throws {
        // Delete existing first to avoid errSecDuplicateItem
        try? delete(tag: tag)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: FondConstants.keychainServiceName,
            kSecAttrAccount as String: tag,
            kSecAttrAccessGroup as String: FondConstants.keychainAccessGroup,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func load(tag: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: FondConstants.keychainServiceName,
            kSecAttrAccount as String: tag,
            kSecAttrAccessGroup as String: FondConstants.keychainAccessGroup,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func delete(tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: FondConstants.keychainServiceName,
            kSecAttrAccount as String: tag,
            kSecAttrAccessGroup as String: FondConstants.keychainAccessGroup,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed (status: \(status))"
        case .deleteFailed(let status):
            return "Keychain delete failed (status: \(status))"
        }
    }
}

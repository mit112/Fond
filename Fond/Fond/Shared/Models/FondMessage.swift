//
//  FondMessage.swift
//  Fond
//
//  Matches the Firestore `connections/{id}/history/{entryId}` schema.
//  Represents a single history entry (status change, message, nudge, heartbeat, etc.).
//
//  BACKWARD COMPATIBILITY: New EntryType cases are raw-value strings.
//  Old clients that don't recognize a type will fall into the default
//  branch of any switch — always handle unknown types gracefully.
//

import Foundation

struct FondMessage: Codable, Identifiable, Sendable {
    /// Firestore document ID.
    var id: String

    /// UID of the person who sent this entry.
    var authorUid: String

    /// Entry type — plaintext, needed for filtering.
    var type: EntryType

    /// AES-256-GCM ciphertext (Base64) of the actual content.
    var encryptedPayload: String

    /// Server timestamp — plaintext, needed for ordering.
    var timestamp: Date

    enum EntryType: String, Codable, Sendable {
        case status
        case message
        case nudge          // "thinking of you" tap from watch or phone
        case heartbeat      // heart rate snapshot from watch
        case promptAnswer   // daily prompt response
    }
}

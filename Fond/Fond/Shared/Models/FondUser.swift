//
//  FondUser.swift
//  Fond
//
//  Matches the Firestore `users/{uid}` document schema exactly.
//  All encrypted fields are stored as Base64 strings.
//

import Foundation

struct FondUser: Codable, Identifiable, Sendable {
    /// Firebase UID — serves as the document ID.
    var id: String

    /// X25519 public key (Base64). Plaintext — public by design.
    var publicKey: String?

    /// AES-256-GCM ciphertext (Base64) of the user's display name.
    var encryptedName: String?

    /// AES-256-GCM ciphertext (Base64) of the user's current status.
    var encryptedStatus: String?

    /// AES-256-GCM ciphertext (Base64) of the user's current message.
    var encryptedMessage: String?

    /// AES-256-GCM ciphertext (Base64) of heartbeat JSON: {"bpm": Int}
    var encryptedHeartbeat: String?

    /// AES-256-GCM ciphertext (Base64) of location JSON: {"lat": Double, "lon": Double}
    var encryptedLocation: String?

    /// AES-256-GCM ciphertext (Base64) of prompt answer JSON: {"promptId": String, "answer": String}
    var encryptedPromptAnswer: String?

    /// Server timestamp of last update. Plaintext — needed for ordering.
    var lastUpdatedAt: Date?

    /// ID of the active connection document. Plaintext — needed for queries.
    var connectionId: String?

    /// Partner's Firebase UID. Plaintext — needed for push routing.
    var partnerUid: String?

    /// Account creation timestamp.
    var createdAt: Date?

    /// Plaintext anniversary date (not sensitive, needed for widget date math).
    var anniversaryDate: Date?

    /// Plaintext countdown target date.
    var countdownDate: Date?

    /// AES-256-GCM ciphertext of the countdown label.
    var countdownLabel: String?
}

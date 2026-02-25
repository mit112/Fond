//
//  ConnectionState.swift
//  Fond
//
//  Represents the app's high-level connection state for UI and widget rendering.
//

import Foundation

enum ConnectionState: String, Codable, Sendable {
    /// User is not signed in.
    case signedOut

    /// Signed in but not paired with anyone.
    case unpaired

    /// Pairing code generated, waiting for partner to enter it.
    case waitingForPartner

    /// Fully connected to a partner.
    case connected

    /// Encryption keys are syncing via iCloud Keychain (new device).
    case syncingKeys
}

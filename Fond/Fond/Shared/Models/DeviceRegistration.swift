//
//  DeviceRegistration.swift
//  Fond
//
//  Matches the Firestore `users/{uid}/devices/{deviceId}` schema.
//  One document per physical device.
//

import Foundation

struct DeviceRegistration: Codable, Identifiable, Sendable {
    /// Unique device identifier.
    var id: String

    /// Platform this device runs on.
    var platform: DevicePlatform

    /// FCM registration token for push notifications.
    var fcmToken: String?

    /// WidgetKit push token for widget updates.
    var widgetPushToken: String?

    /// Last time this device checked in.
    var lastSeen: Date?

    /// App version running on this device.
    var appVersion: String?

    enum DevicePlatform: String, Codable, Sendable {
        case ios
        case ipados
        case macos
        case watchos
    }
}

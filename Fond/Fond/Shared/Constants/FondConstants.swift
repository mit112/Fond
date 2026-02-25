//
//  FondConstants.swift
//  Fond
//
//  Single source of truth for all app-wide constants.
//

import Foundation

enum FondConstants {

    // MARK: - App Configuration

    static let appGroupID = "group.com.mitsheth.Fond"
    static let keychainAccessGroup = "3P89U4WZAB.com.mitsheth.Fond"
    static let keychainServiceName = "com.mitsheth.Fond.keys"

    // MARK: - Firestore Collections

    static let usersCollection = "users"
    static let connectionsCollection = "connections"
    static let codesCollection = "codes"
    static let devicesSubcollection = "devices"
    static let historySubcollection = "history"

    // MARK: - Limits

    static let codeLength = 6
    static let codeExpirationMinutes = 10
    static let maxMessageLength = 100
    static let rateLimitSeconds = 5

    // MARK: - Cloud Function Names

    static let linkUsersFunction = "linkUsers"
    static let notifyPartnerFunction = "notifyPartner"
    static let unlinkConnectionFunction = "unlinkConnection"

    // MARK: - App Group UserDefaults Keys

    static let partnerNameKey = "partnerName"
    static let partnerStatusKey = "partnerStatus"
    static let partnerMessageKey = "partnerMessage"
    static let partnerLastUpdatedKey = "partnerLastUpdated"
    static let connectionStateKey = "connectionState"
    static let widgetPushTokenKey = "widgetPushToken"

    // MARK: - App Group Keys: Dates

    static let anniversaryDateKey = "anniversaryDate"
    static let countdownDateKey = "countdownDate"
    static let countdownLabelKey = "countdownLabel"

    // MARK: - App Group Keys: Distance

    static let distanceMilesKey = "distanceMiles"
    static let partnerCityKey = "partnerCity"

    // MARK: - App Group Keys: Heartbeat

    static let partnerHeartbeatKey = "partnerHeartbeat"
    static let partnerHeartbeatTimeKey = "partnerHeartbeatTime"

    // MARK: - App Group Keys: Daily Prompt

    static let dailyPromptIdKey = "dailyPromptId"
    static let dailyPromptTextKey = "dailyPromptText"
    static let myPromptAnswerKey = "myPromptAnswer"
    static let partnerPromptAnswerKey = "partnerPromptAnswer"

    // MARK: - App Group Keys: Nudge

    static let lastNudgeTimeKey = "lastNudgeTime"
}

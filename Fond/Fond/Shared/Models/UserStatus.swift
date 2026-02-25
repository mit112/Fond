//
//  UserStatus.swift
//  Fond
//
//  Core status enum — the primary state each person shares.
//  Grouped by category for the picker UI.
//
//  BACKWARD COMPATIBILITY: Raw values are the Firestore-stored strings.
//  Old clients that don't recognize a new value get nil from init(rawValue:)
//  and fall back to displaying the emoji directly. Never rename a raw value.
//

import Foundation
import SwiftUI

enum UserStatus: String, Codable, CaseIterable, Sendable {

    // ── Availability ──
    case available
    case busy
    case away
    case sleeping

    // ── Mood ──
    case happy
    case stressed
    case sad
    case excited
    case calm

    // ── Activity ──
    case working
    case driving
    case eating
    case exercising

    // ── Love ── (the differentiator)
    case thinkingOfYou
    case missYou
    case lovingYou

    // MARK: - Category

    enum Category: String, CaseIterable, Sendable {
        case availability = "Availability"
        case mood = "Mood"
        case activity = "Activity"
        case love = "Love"

        var emoji: String {
            switch self {
            case .availability: return "📡"
            case .mood:         return "🫧"
            case .activity:     return "🏃"
            case .love:         return "💛"
            }
        }

        /// All statuses belonging to this category, in display order.
        var statuses: [UserStatus] {
            switch self {
            case .availability: return [.available, .busy, .away, .sleeping]
            case .mood:         return [.happy, .stressed, .sad, .excited, .calm]
            case .activity:     return [.working, .driving, .eating, .exercising]
            case .love:         return [.thinkingOfYou, .missYou, .lovingYou]
            }
        }
    }

    var category: Category {
        switch self {
        case .available, .busy, .away, .sleeping:
            return .availability
        case .happy, .stressed, .sad, .excited, .calm:
            return .mood
        case .working, .driving, .eating, .exercising:
            return .activity
        case .thinkingOfYou, .missYou, .lovingYou:
            return .love
        }
    }

    // MARK: - Display

    var emoji: String {
        switch self {
        // Availability
        case .available:     return "💚"
        case .busy:          return "🔴"
        case .away:          return "🌙"
        case .sleeping:      return "😴"
        // Mood
        case .happy:         return "😊"
        case .stressed:      return "😤"
        case .sad:           return "😔"
        case .excited:       return "🤩"
        case .calm:          return "😌"
        // Activity
        case .working:       return "💻"
        case .driving:       return "🚗"
        case .eating:        return "🍽️"
        case .exercising:    return "💪"
        // Love
        case .thinkingOfYou: return "💭"
        case .missYou:       return "🥺"
        case .lovingYou:     return "🥰"
        }
    }

    var displayName: String {
        switch self {
        // Availability
        case .available:     return "Available"
        case .busy:          return "Busy"
        case .away:          return "Away"
        case .sleeping:      return "Sleeping"
        // Mood
        case .happy:         return "Happy"
        case .stressed:      return "Stressed"
        case .sad:           return "Sad"
        case .excited:       return "Excited"
        case .calm:          return "Calm"
        // Activity
        case .working:       return "Working"
        case .driving:       return "Driving"
        case .eating:        return "Eating"
        case .exercising:    return "Exercising"
        // Love
        case .thinkingOfYou: return "Thinking of You"
        case .missYou:       return "Miss You"
        case .lovingYou:     return "Loving You"
        }
    }

    // MARK: - Accent Color

    var accentColor: Color {
        switch self {
        // Availability
        case .available:     return .green
        case .busy:          return .red
        case .away:          return .orange
        case .sleeping:      return .indigo
        // Mood
        case .happy:         return .yellow
        case .stressed:      return .red.opacity(0.8)
        case .sad:           return .blue
        case .excited:       return .pink
        case .calm:          return .teal
        // Activity
        case .working:       return .blue
        case .driving:       return .orange
        case .eating:        return .brown
        case .exercising:    return .green
        // Love
        case .thinkingOfYou: return FondColors.amber
        case .missYou:       return FondColors.lavender
        case .lovingYou:     return FondColors.rose
        }
    }

    // MARK: - Backward Compatibility

    /// Safe initializer for unknown raw values from partner's device.
    /// Returns a display tuple even for values this client doesn't recognize.
    static func displayInfo(forRawValue raw: String) -> (emoji: String, displayName: String) {
        if let known = UserStatus(rawValue: raw) {
            return (known.emoji, known.displayName)
        }
        // Unknown status from a newer client version — show raw value capitalized
        let name = raw
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .capitalized
        return ("💬", name)
    }
}

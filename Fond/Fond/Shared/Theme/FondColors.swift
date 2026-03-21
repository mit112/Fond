//
//  FondColors.swift
//  Fond
//
//  Single source of truth for all colors in the design system.
//  Uses adaptive light/dark variants via dynamic UIColor → Color bridging.
//
//  Target membership: Fond (iOS/Mac), watchOS, Widget — all targets need colors.
//
//  Design reference: docs/02-design-direction.md
//

import SwiftUI

// MARK: - Core Palette

/// All Fond colors. Access via `FondColors.amber`, `FondColors.background`, etc.
/// Each color adapts to light/dark mode automatically.
enum FondColors {

    // MARK: Brand

    /// Primary accent — warm amber/gold. Used for CTAs, active states, brand moments.
    static let amber = adaptive(
        light: (0.91, 0.66, 0.22),  // #E8A838
        dark: (0.94, 0.72, 0.29)   // #F0B84A
    )

    /// Secondary accent — soft lavender. Subtle highlights, partner-side elements.
    static let lavender = adaptive(
        light: (0.72, 0.63, 0.82),  // #B8A0D2
        dark: (0.77, 0.69, 0.87)   // #C4B0DE
    )

    /// Tertiary accent — muted rose. Sparingly — reactions, special moments only.
    static let rose = adaptive(
        light: (0.83, 0.63, 0.63),  // #D4A0A0
        dark: (0.87, 0.69, 0.69)   // #DEB0B0
    )

    // MARK: Backgrounds

    /// App background — warm cream (light) / warm charcoal (dark).
    static let background = adaptive(
        light: (0.98, 0.97, 0.96),  // #FAF8F5
        dark: (0.10, 0.10, 0.12)   // #1A1A1E
    )

    /// Elevated surface — cards, containers.
    static let surface = adaptive(
        light: (1.0, 1.0, 1.0),     // #FFFFFF
        dark: (0.16, 0.16, 0.18)   // #2A2A2E
    )

    // MARK: Text

    /// Primary text — headlines, partner name.
    static let text = adaptive(
        light: (0.10, 0.10, 0.12),  // #1A1A1E
        dark: (0.96, 0.95, 0.94)   // #F5F3F0
    )

    /// Secondary text — timestamps, labels, captions.
    static let textSecondary = adaptive(
        light: (0.42, 0.42, 0.44),  // #6B6B70
        dark: (0.63, 0.63, 0.65)   // #A0A0A5
    )

    // MARK: Status

    static let statusAvailable = adaptive(
        light: (0.30, 0.75, 0.45),
        dark: (0.35, 0.80, 0.50)
    )

    static let statusBusy = adaptive(
        light: (0.85, 0.40, 0.40),
        dark: (0.90, 0.45, 0.45)
    )

    static let statusAway = adaptive(
        light: (0.65, 0.58, 0.82),
        dark: (0.70, 0.63, 0.87)
    )

    static let statusSleeping = adaptive(
        light: (0.35, 0.30, 0.55),
        dark: (0.40, 0.35, 0.60)
    )

    // Mood
    static let statusHappy = adaptive(
        light: (0.95, 0.75, 0.20),  // Warm gold
        dark: (0.98, 0.80, 0.25)
    )
    static let statusStressed = adaptive(
        light: (0.85, 0.50, 0.30),  // Burnt orange
        dark: (0.90, 0.55, 0.35)
    )
    static let statusSad = adaptive(
        light: (0.50, 0.55, 0.75),  // Muted blue
        dark: (0.55, 0.60, 0.80)
    )
    static let statusExcited = adaptive(
        light: (0.90, 0.55, 0.65),  // Warm pink
        dark: (0.95, 0.60, 0.70)
    )
    static let statusCalm = adaptive(
        light: (0.55, 0.75, 0.72),  // Sage green
        dark: (0.60, 0.80, 0.77)
    )

    // Activity
    static let statusWorking = adaptive(
        light: (0.45, 0.55, 0.70),  // Steel blue
        dark: (0.50, 0.60, 0.75)
    )
    static let statusDriving = adaptive(
        light: (0.60, 0.60, 0.60),  // Neutral gray
        dark: (0.65, 0.65, 0.65)
    )
    static let statusEating = adaptive(
        light: (0.85, 0.65, 0.40),  // Warm tan
        dark: (0.90, 0.70, 0.45)
    )
    static let statusExercising = adaptive(
        light: (0.40, 0.70, 0.55),  // Teal green
        dark: (0.45, 0.75, 0.60)
    )

    // Love
    static let statusLove = adaptive(
        light: (0.88, 0.55, 0.55),  // Soft red / warm rose
        dark: (0.93, 0.60, 0.60)
    )

    // MARK: Chat Bubbles

    /// My message bubble background.
    static let bubbleMine = amber.opacity(0.12)

    /// Partner's message bubble background.
    static let bubblePartner = lavender.opacity(0.12)

    // MARK: Glass Tint

    /// Tint color for Liquid Glass surfaces (iOS 26).
    static let glassTint = amber.opacity(0.18)
}

// MARK: - Mesh Gradient Colors

extension FondColors {
    /// Colors for the animated mesh gradient background.
    /// Warm amber/gold/lavender/cream — slow-shifting, breathing feel.
    enum Mesh {
        static let topLeft = adaptive(
            light: (0.96, 0.91, 0.82),
            dark: (0.14, 0.12, 0.10)
        )
        static let topRight = adaptive(
            light: (0.94, 0.85, 0.72),
            dark: (0.18, 0.14, 0.08)
        )
        static let center = adaptive(
            light: (0.95, 0.88, 0.78),
            dark: (0.16, 0.12, 0.10)
        )
        static let bottomLeft = adaptive(
            light: (0.88, 0.82, 0.90),
            dark: (0.12, 0.10, 0.16)
        )
        static let bottomRight = adaptive(
            light: (0.96, 0.89, 0.80),
            dark: (0.15, 0.12, 0.08)
        )

        /// Alternate colors the mesh gradient animates toward.
        static let centerAlt = adaptive(
            light: (0.92, 0.80, 0.68),
            dark: (0.20, 0.15, 0.08)
        )
        static let bottomLeftAlt = adaptive(
            light: (0.85, 0.78, 0.88),
            dark: (0.14, 0.10, 0.20)
        )
    }
}

// MARK: - Status → Color Mapping

extension UserStatus {
    /// The color associated with this status for UI reinforcement.
    var statusColor: Color {
        switch self {
        // Availability
        case .available: return FondColors.statusAvailable
        case .busy: return FondColors.statusBusy
        case .away: return FondColors.statusAway
        case .sleeping: return FondColors.statusSleeping
        // Mood
        case .happy: return FondColors.statusHappy
        case .stressed: return FondColors.statusStressed
        case .sad: return FondColors.statusSad
        case .excited: return FondColors.statusExcited
        case .calm: return FondColors.statusCalm
        // Activity
        case .working: return FondColors.statusWorking
        case .driving: return FondColors.statusDriving
        case .eating: return FondColors.statusEating
        case .exercising: return FondColors.statusExercising
        // Love
        case .thinkingOfYou: return FondColors.statusLove
        case .missYou: return FondColors.statusLove
        case .lovingYou: return FondColors.statusLove
        }
    }
}

// MARK: - Adaptive Color Factory

private extension FondColors {
    /// Creates an adaptive Color from light/dark RGB tuples.
    /// iOS/iPadOS: UIColor dynamic provider resolves per-trait.
    /// macOS: NSColor appearance-based provider.
    /// watchOS: Always uses dark variant (watch is always dark).
    static func adaptive(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        #if os(watchOS)
        // watchOS is always dark — no dynamic provider needed.
        Color(red: dark.0, green: dark.1, blue: dark.2)
        #elseif canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1.0)
        })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1.0)
        })
        #else
        Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }
}

import SwiftUI

struct FondRGB: Sendable, Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    init(hex: UInt32) {
        red = CGFloat((hex >> 16) & 0xFF) / 255
        green = CGFloat((hex >> 8) & 0xFF) / 255
        blue = CGFloat(hex & 0xFF) / 255
    }

    var hex: UInt32 {
        UInt32((red * 255).rounded()) << 16
            | UInt32((green * 255).rounded()) << 8
            | UInt32((blue * 255).rounded())
    }

    static func contrast(_ first: Self, _ second: Self) -> Double {
        func luminance(_ color: Self) -> Double {
            func channel(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045
                    ? value / 12.92
                    : pow((value + 0.055) / 1.055, 2.4)
            }

            return 0.2126 * channel(color.red)
                + 0.7152 * channel(color.green)
                + 0.0722 * channel(color.blue)
        }

        let values = [luminance(first), luminance(second)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }
}

enum FondPalette {
    static let fieldLight = FondRGB(hex: 0xEEE7DC)
    static let fieldDark = FondRGB(hex: 0x191715)
    static let keepsakeLight = FondRGB(hex: 0xFFF9EE)
    static let keepsakeDark = FondRGB(hex: 0x24201C)
    static let inkLight = FondRGB(hex: 0x26211C)
    static let inkDark = FondRGB(hex: 0xF7EFE3)
    static let inkSecondaryLight = FondRGB(hex: 0x665C52)
    static let inkSecondaryDark = FondRGB(hex: 0xBDB2A5)
    static let amberLight = FondRGB(hex: 0xA85F00)
    static let amberDark = FondRGB(hex: 0xD68A1F)
    static let controlPlateLight = keepsakeLight
    static let controlPlateDark = FondRGB(hex: 0x312B24)
    static let controlFallbackLight = keepsakeLight
    static let controlFallbackDark = FondRGB(hex: 0x342F29)
    static let sendForegroundLight = keepsakeLight
    static let sendForegroundDark = FondRGB(hex: 0x211B14)

    static let ruleLight = FondRGB(hex: 0x807367)
    static let ruleDark = FondRGB(hex: 0x6F665D)
    static let shadowLight = FondRGB(hex: 0x2A2119)
    static let shadowDark = FondRGB(hex: 0x000000)

    static let statusAvailableLight = FondRGB(hex: 0x267347)
    static let statusAvailableDark = FondRGB(hex: 0x63B77E)
    static let statusBusyLight = FondRGB(hex: 0xA44337)
    static let statusBusyDark = FondRGB(hex: 0xD77A65)
    static let statusAwayLight = FondRGB(hex: 0x66539A)
    static let statusAwayDark = FondRGB(hex: 0xA08AC7)
    static let statusSleepingLight = FondRGB(hex: 0x49618E)
    static let statusSleepingDark = FondRGB(hex: 0x7E95C7)
}

enum FondColors {
    static let field = adaptive(light: FondPalette.fieldLight, dark: FondPalette.fieldDark)
    static let keepsake = adaptive(light: FondPalette.keepsakeLight, dark: FondPalette.keepsakeDark)
    static let ink = adaptive(light: FondPalette.inkLight, dark: FondPalette.inkDark)
    static let inkSecondary = adaptive(
        light: FondPalette.inkSecondaryLight,
        dark: FondPalette.inkSecondaryDark
    )
    static let rule = adaptive(light: FondPalette.ruleLight, dark: FondPalette.ruleDark)
        .opacity(0.38)
    static let amber = adaptive(light: FondPalette.amberLight, dark: FondPalette.amberDark)
    static let controlPlate = adaptive(
        light: FondPalette.controlPlateLight,
        dark: FondPalette.controlPlateDark
    )
    static let controlFallback = adaptive(
        light: FondPalette.controlFallbackLight,
        dark: FondPalette.controlFallbackDark
    )
    static let sendForeground = adaptive(
        light: FondPalette.sendForegroundLight,
        dark: FondPalette.sendForegroundDark
    )
    static let shadow = adaptive(light: FondPalette.shadowLight, dark: FondPalette.shadowDark)

    static let statusAvailable = adaptive(
        light: FondPalette.statusAvailableLight,
        dark: FondPalette.statusAvailableDark
    )
    static let statusBusy = adaptive(
        light: FondPalette.statusBusyLight,
        dark: FondPalette.statusBusyDark
    )
    static let statusAway = adaptive(
        light: FondPalette.statusAwayLight,
        dark: FondPalette.statusAwayDark
    )
    static let statusSleeping = adaptive(
        light: FondPalette.statusSleepingLight,
        dark: FondPalette.statusSleepingDark
    )

    // Temporary compatibility aliases. Connected-experience call sites migrate by Task 9.
    static let background = field
    static let surface = keepsake
    static let text = ink
    static let textSecondary = inkSecondary
    static let lavender = statusAway
    static let rose = statusBusy
    static let statusHappy = statusAvailable
    static let statusStressed = statusBusy
    static let statusSad = statusAway
    static let statusExcited = statusBusy
    static let statusCalm = statusAvailable
    static let statusWorking = statusAway
    static let statusDriving = statusAway
    static let statusEating = amber
    static let statusExercising = statusAvailable
    static let statusLove = amber
    static let bubbleMine = amber.opacity(0.12)
    static let bubblePartner = statusAway.opacity(0.12)
    static let glassTint = amber.opacity(0.18)

    enum Mesh {
        static let topLeft = keepsake
        static let topRight = field
        static let center = keepsake
        static let bottomLeft = field
        static let bottomRight = keepsake
        static let centerAlt = field
        static let bottomLeftAlt = keepsake
    }

    private static func adaptive(light: FondRGB, dark: FondRGB) -> Color {
        #if os(watchOS)
        Color(red: dark.red, green: dark.green, blue: dark.blue)
        #elseif canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let color = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color = isDark ? dark : light
            return NSColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        })
        #else
        Color(red: light.red, green: light.green, blue: light.blue)
        #endif
    }
}

extension UserStatus {
    var statusColor: Color {
        switch self {
        case .available, .happy, .calm, .exercising:
            FondColors.statusAvailable
        case .busy, .stressed, .excited:
            FondColors.statusBusy
        case .away, .sad, .working, .driving:
            FondColors.statusAway
        case .sleeping:
            FondColors.statusSleeping
        case .eating, .thinkingOfYou, .missYou, .lovingYou:
            FondColors.amber
        }
    }
}

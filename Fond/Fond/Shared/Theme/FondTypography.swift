import SwiftUI
import CoreText

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum FondVariableFont {
    static func make(
        name: String,
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        axes: [String: CGFloat]
    ) -> Font {
        #if canImport(UIKit)
        let descriptor = UIFontDescriptor(name: name, size: size)
            .addingAttributes([
                UIFontDescriptor.AttributeName(
                    rawValue: kCTFontVariationAttribute as String
                ): variationDictionary(axes)
            ])
        let font = UIFont(descriptor: descriptor, size: size)
        return Font(UIFontMetrics(forTextStyle: uiTextStyle(textStyle)).scaledFont(for: font))
        #elseif canImport(AppKit)
        let descriptor = NSFontDescriptor(name: name, size: size)
            .addingAttributes([
                NSFontDescriptor.AttributeName(
                    rawValue: kCTFontVariationAttribute as String
                ): variationDictionary(axes)
            ])
        if let font = NSFont(descriptor: descriptor, size: size) {
            return Font(font)
        }
        return .system(size: size, design: .serif)
        #else
        return .system(size: size, design: .serif)
        #endif
    }

    private static func variationDictionary(_ axes: [String: CGFloat]) -> [NSNumber: NSNumber] {
        Dictionary(uniqueKeysWithValues: axes.map { key, value in
            (NSNumber(value: axisIdentifier(key)), NSNumber(value: Double(value)))
        })
    }

    private static func axisIdentifier(_ tag: String) -> UInt32 {
        tag.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    #if canImport(UIKit)
    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .caption: .caption1
        case .caption2: .caption2
        case .footnote: .footnote
        default: .body
        }
    }
    #endif
}

enum FondType {
    static var partnerName: Font {
        FondVariableFont.make(
            name: "Fraunces",
            size: 58,
            relativeTo: .largeTitle,
            axes: ["opsz": 72, "SOFT": 35, "WONK": 1, "wght": 550]
        )
    }

    static var question: Font {
        FondVariableFont.make(
            name: "Fraunces",
            size: 34,
            relativeTo: .title,
            axes: ["opsz": 48, "SOFT": 28, "WONK": 1, "wght": 520]
        )
    }

    static var momentQuestion: Font {
        FondVariableFont.make(
            name: "Fraunces",
            size: 21,
            relativeTo: .title3,
            axes: ["opsz": 28, "SOFT": 22, "wght": 500]
        )
    }

    static var pullQuote: Font {
        FondVariableFont.make(
            name: "Newsreader",
            size: 25,
            relativeTo: .title2,
            axes: ["opsz": 30, "wght": 400]
        )
    }

    static var voice: Font {
        FondVariableFont.make(
            name: "Newsreader",
            size: 18,
            relativeTo: .body,
            axes: ["opsz": 20, "wght": 400]
        )
    }

    static let body = Font.body
    static let control = Font.body.weight(.semibold)
    static let metadata = Font.caption.weight(.medium).monospacedDigit()
    static let eyebrow = Font.caption2.weight(.semibold)
}

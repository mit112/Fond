//
//  FondWidgetIntent.swift
//  widgets
//
//  Minimal AppIntent structs for widget configuration.
//  These replace StaticConfiguration with AppIntentConfiguration
//  as required by iOS 26 / WidgetKit.
//

import AppIntents
import WidgetKit

struct FondWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Fond"
    static var description: IntentDescription = "Shows your partner's status and messages."
}

struct FondDateWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Fond Date"
    static var description: IntentDescription = "Shows days together or countdown."
}

struct FondDistanceWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Fond Distance"
    static var description: IntentDescription = "Shows distance from your partner."
}

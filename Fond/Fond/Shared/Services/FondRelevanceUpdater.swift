//
//  FondRelevanceUpdater.swift
//  Fond
//
//  Updates watchOS Smart Stack relevance whenever partner data arrives.
//  Called alongside WidgetCenter.shared.reloadAllTimelines() to keep
//  relevance entries in sync with the latest App Group data.
//

#if canImport(AppIntents)

import AppIntents
import Foundation
import os

private let logger = Logger(subsystem: "com.mitsheth.Fond", category: "Relevance")

struct FondRelevanceUpdater {

    /// Re-computes and pushes relevance entries for all three Fond widgets.
    /// Safe to call from any target that links AppIntents.
    static func update() async {
        let defaults = UserDefaults(suiteName: FondConstants.appGroupID)
        let calendar = Calendar.current

        // If not connected (signed out, unpaired, etc.), clear all relevance entries
        let stateRaw = defaults?.string(forKey: FondConstants.connectionStateKey)
        let connectionState = stateRaw.flatMap { ConnectionState(rawValue: $0) }
        if connectionState != .connected {
            try? await RelevantIntentManager.shared.updateRelevantIntents([])
            logger.debug("Cleared relevance entries (state: \(stateRaw ?? "nil"))")
            return
        }

        var relevantIntents: [RelevantIntent] = []

        appendFondWidgetEntries(
            to: &relevantIntents,
            defaults: defaults,
            calendar: calendar
        )
        appendDateWidgetEntries(
            to: &relevantIntents,
            defaults: defaults,
            calendar: calendar
        )
        appendDistanceWidgetEntries(
            to: &relevantIntents,
            calendar: calendar
        )

        do {
            try await RelevantIntentManager.shared.updateRelevantIntents(relevantIntents)
            logger.debug("Updated \(relevantIntents.count) relevance entries")
        } catch {
            logger.error("Failed to update relevance: \(error.localizedDescription)")
        }
    }

    // MARK: - FondWidget relevance

    private static func appendFondWidgetEntries(
        to intents: inout [RelevantIntent],
        defaults: UserDefaults?,
        calendar: Calendar
    ) {
        let config = FondWidgetConfigIntent()

        // Boost after partner's last update
        if let lastUpdated = defaults?.object(
            forKey: FondConstants.partnerLastUpdatedKey
        ) as? Date {
            let boostMinutes = FondConstants.relevancePartnerBoostMinutes
            let boostEnd = lastUpdated.addingTimeInterval(Double(boostMinutes) * 60)
            if boostEnd > .now {
                intents.append(RelevantIntent(
                    config,
                    widgetKind: "FondWidget",
                    relevance: .date(
                        range: lastUpdated...boostEnd,
                        kind: .scheduled
                    )
                ))
            }
        }

        // Morning check-in
        if let window = timeWindow(
            calendar: calendar,
            hour: FondConstants.relevanceMorningHour
        ) {
            intents.append(RelevantIntent(
                config,
                widgetKind: "FondWidget",
                relevance: .date(range: window, kind: .scheduled)
            ))
        }

        // Evening check-in
        if let window = timeWindow(
            calendar: calendar,
            hour: FondConstants.relevanceEveningHour
        ) {
            intents.append(RelevantIntent(
                config,
                widgetKind: "FondWidget",
                relevance: .date(range: window, kind: .scheduled)
            ))
        }
    }

    // MARK: - FondDateWidget relevance

    private static func appendDateWidgetEntries(
        to intents: inout [RelevantIntent],
        defaults: UserDefaults?,
        calendar: Calendar
    ) {
        let config = FondDateWidgetConfigIntent()

        // Midnight -- day count changes
        let tomorrow = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now)
                ?? .now.addingTimeInterval(86400)
        )
        let windowMinutes = FondConstants.relevanceMidnightWindowMinutes
        let midnightStart = tomorrow.addingTimeInterval(Double(-windowMinutes) * 60)
        let midnightEnd = tomorrow.addingTimeInterval(Double(windowMinutes) * 60)
        intents.append(RelevantIntent(
            config,
            widgetKind: "FondDateWidget",
            relevance: .date(
                range: midnightStart...midnightEnd,
                kind: .scheduled
            )
        ))

        // Countdown date -- boost all day
        if let countdownDate = defaults?.object(
            forKey: FondConstants.countdownDateKey
        ) as? Date {
            let countdownStart = calendar.startOfDay(for: countdownDate)
            let countdownEnd = countdownStart.addingTimeInterval(24 * 60 * 60)
            if countdownEnd > .now {
                intents.append(RelevantIntent(
                    config,
                    widgetKind: "FondDateWidget",
                    relevance: .date(
                        range: countdownStart...countdownEnd,
                        kind: .scheduled
                    )
                ))
            }
        }
    }

    // MARK: - FondDistanceWidget relevance

    private static func appendDistanceWidgetEntries(
        to intents: inout [RelevantIntent],
        calendar: Calendar
    ) {
        let config = FondDistanceWidgetConfigIntent()

        // Morning commute
        if let window = timeWindow(
            calendar: calendar,
            hour: FondConstants.relevanceCommuteAMHour
        ) {
            intents.append(RelevantIntent(
                config,
                widgetKind: "FondDistanceWidget",
                relevance: .date(range: window, kind: .scheduled)
            ))
        }

        // Evening commute
        if let window = timeWindow(
            calendar: calendar,
            hour: FondConstants.relevanceCommutePMHour
        ) {
            intents.append(RelevantIntent(
                config,
                widgetKind: "FondDistanceWidget",
                relevance: .date(range: window, kind: .scheduled)
            ))
        }
    }

    // MARK: - Helpers

    /// Computes a relevance time window around the given hour,
    /// returning `nil` if the window has already passed.
    private static func timeWindow(
        calendar: Calendar,
        hour: Int
    ) -> ClosedRange<Date>? {
        let leadMinutes = FondConstants.relevanceWindowLeadMinutes
        let trailMinutes = FondConstants.relevanceWindowTrailMinutes
        guard let start = calendar.date(
            bySettingHour: hour - 1,
            minute: 60 - leadMinutes,
            second: 0,
            of: .now
        ),
        let end = calendar.date(
            bySettingHour: hour,
            minute: trailMinutes,
            second: 0,
            of: .now
        ),
        end > .now else {
            return nil
        }
        return start...end
    }
}

#endif

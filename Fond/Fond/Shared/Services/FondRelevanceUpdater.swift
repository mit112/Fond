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

        var relevantIntents: [RelevantIntent] = []

        // MARK: - FondWidget relevance

        let fondConfig = FondWidgetConfigIntent()

        // Boost for 30 minutes after partner's last update
        if let lastUpdated = defaults?.object(forKey: FondConstants.partnerLastUpdatedKey) as? Date {
            let boostEnd = lastUpdated.addingTimeInterval(30 * 60)
            if boostEnd > .now {
                relevantIntents.append(RelevantIntent(
                    fondConfig,
                    widgetKind: "FondWidget",
                    relevance: .date(range: lastUpdated...boostEnd, kind: .scheduled)
                ))
            }
        }

        // Morning check-in (8 AM)
        if let morningStart = calendar.date(bySettingHour: 7, minute: 45, second: 0, of: .now),
           let morningEnd = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: .now) {
            relevantIntents.append(RelevantIntent(
                fondConfig,
                widgetKind: "FondWidget",
                relevance: .date(range: morningStart...morningEnd, kind: .scheduled)
            ))
        }

        // Evening check-in (8 PM)
        if let eveningStart = calendar.date(bySettingHour: 19, minute: 45, second: 0, of: .now),
           let eveningEnd = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: .now) {
            relevantIntents.append(RelevantIntent(
                fondConfig,
                widgetKind: "FondWidget",
                relevance: .date(range: eveningStart...eveningEnd, kind: .scheduled)
            ))
        }

        // MARK: - FondDateWidget relevance

        let dateConfig = FondDateWidgetConfigIntent()

        // Midnight -- day count changes
        let tomorrow = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now)!
        )
        let midnightStart = tomorrow.addingTimeInterval(-15 * 60)
        let midnightEnd = tomorrow.addingTimeInterval(15 * 60)
        relevantIntents.append(RelevantIntent(
            dateConfig,
            widgetKind: "FondDateWidget",
            relevance: .date(range: midnightStart...midnightEnd, kind: .scheduled)
        ))

        // Countdown date -- boost all day
        if let countdownDate = defaults?.object(forKey: FondConstants.countdownDateKey) as? Date {
            let countdownStart = calendar.startOfDay(for: countdownDate)
            let countdownEnd = countdownStart.addingTimeInterval(24 * 60 * 60)
            if countdownEnd > .now {
                relevantIntents.append(RelevantIntent(
                    dateConfig,
                    widgetKind: "FondDateWidget",
                    relevance: .date(range: countdownStart...countdownEnd, kind: .scheduled)
                ))
            }
        }

        // MARK: - FondDistanceWidget relevance

        let distanceConfig = FondDistanceWidgetConfigIntent()

        // Morning commute (8 AM)
        if let morningStart = calendar.date(bySettingHour: 7, minute: 45, second: 0, of: .now),
           let morningEnd = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: .now) {
            relevantIntents.append(RelevantIntent(
                distanceConfig,
                widgetKind: "FondDistanceWidget",
                relevance: .date(range: morningStart...morningEnd, kind: .scheduled)
            ))
        }

        // Evening commute (6 PM)
        if let eveningStart = calendar.date(bySettingHour: 17, minute: 45, second: 0, of: .now),
           let eveningEnd = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: .now) {
            relevantIntents.append(RelevantIntent(
                distanceConfig,
                widgetKind: "FondDistanceWidget",
                relevance: .date(range: eveningStart...eveningEnd, kind: .scheduled)
            ))
        }

        do {
            try await RelevantIntentManager.shared.updateRelevantIntents(relevantIntents)
            logger.debug("Updated \(relevantIntents.count) relevance entries")
        } catch {
            logger.error("Failed to update relevance: \(error.localizedDescription)")
        }
    }
}

#endif

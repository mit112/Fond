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

        // MARK: - FondWidget relevance

        let fondConfig = FondWidgetConfigIntent()

        // Boost after partner's last update
        if let lastUpdated = defaults?.object(forKey: FondConstants.partnerLastUpdatedKey) as? Date {
            let boostEnd = lastUpdated.addingTimeInterval(Double(FondConstants.relevancePartnerBoostMinutes) * 60)
            if boostEnd > .now {
                relevantIntents.append(RelevantIntent(
                    fondConfig,
                    widgetKind: "FondWidget",
                    relevance: .date(range: lastUpdated...boostEnd, kind: .scheduled)
                ))
            }
        }

        // Morning check-in
        if let morningStart = calendar.date(bySettingHour: FondConstants.relevanceMorningHour - 1, minute: 60 - FondConstants.relevanceWindowLeadMinutes, second: 0, of: .now),
           let morningEnd = calendar.date(bySettingHour: FondConstants.relevanceMorningHour, minute: FondConstants.relevanceWindowTrailMinutes, second: 0, of: .now),
           morningEnd > .now {
            relevantIntents.append(RelevantIntent(
                fondConfig,
                widgetKind: "FondWidget",
                relevance: .date(range: morningStart...morningEnd, kind: .scheduled)
            ))
        }

        // Evening check-in
        if let eveningStart = calendar.date(bySettingHour: FondConstants.relevanceEveningHour - 1, minute: 60 - FondConstants.relevanceWindowLeadMinutes, second: 0, of: .now),
           let eveningEnd = calendar.date(bySettingHour: FondConstants.relevanceEveningHour, minute: FondConstants.relevanceWindowTrailMinutes, second: 0, of: .now),
           eveningEnd > .now {
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
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now.addingTimeInterval(86400)
        )
        let midnightStart = tomorrow.addingTimeInterval(Double(-FondConstants.relevanceMidnightWindowMinutes) * 60)
        let midnightEnd = tomorrow.addingTimeInterval(Double(FondConstants.relevanceMidnightWindowMinutes) * 60)
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

        // Morning commute
        if let morningStart = calendar.date(bySettingHour: FondConstants.relevanceCommuteAMHour - 1, minute: 60 - FondConstants.relevanceWindowLeadMinutes, second: 0, of: .now),
           let morningEnd = calendar.date(bySettingHour: FondConstants.relevanceCommuteAMHour, minute: FondConstants.relevanceWindowTrailMinutes, second: 0, of: .now),
           morningEnd > .now {
            relevantIntents.append(RelevantIntent(
                distanceConfig,
                widgetKind: "FondDistanceWidget",
                relevance: .date(range: morningStart...morningEnd, kind: .scheduled)
            ))
        }

        // Evening commute
        if let eveningStart = calendar.date(bySettingHour: FondConstants.relevanceCommutePMHour - 1, minute: 60 - FondConstants.relevanceWindowLeadMinutes, second: 0, of: .now),
           let eveningEnd = calendar.date(bySettingHour: FondConstants.relevanceCommutePMHour, minute: FondConstants.relevanceWindowTrailMinutes, second: 0, of: .now),
           eveningEnd > .now {
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

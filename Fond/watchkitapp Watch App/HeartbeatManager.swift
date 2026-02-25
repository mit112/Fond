//
//  HeartbeatManager.swift
//  watchkitapp Watch App
//
//  Wraps HealthKit heart rate queries for the watchOS app.
//
//  Authorization is requested lazily — only when the user first taps
//  "Send Heartbeat," not on app launch. This is the correct UX pattern
//  and avoids App Review issues with premature permission prompts.
//
//  Reads the most recent heart rate sample (within 10 minutes).
//  Does NOT trigger a manual measurement — uses passively-recorded data.
//
//  Target membership: watchOS ONLY.
//

import HealthKit

@Observable
final class HeartbeatManager {

    static let shared = HeartbeatManager()

    // MARK: - State

    /// Whether HealthKit authorization has been requested (not necessarily granted).
    private(set) var authorizationRequested = false

    /// Whether the user has granted heart rate read permission.
    private(set) var isAuthorized = false

    /// True while a HealthKit query is in flight.
    private(set) var isQuerying = false

    /// The last queried BPM, if any.
    private(set) var lastBpm: Int?

    /// Non-nil if the last query failed or returned no data.
    private(set) var errorMessage: String?

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private let heartRateType = HKQuantityType(.heartRate)

    private init() {}

    // MARK: - Authorization

    /// Requests HealthKit authorization for heart rate data.
    /// Call this before the first query. Safe to call multiple times.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data not available"
            return
        }

        guard !authorizationRequested else { return }

        do {
            try await healthStore.requestAuthorization(
                toShare: [],  // We never write health data
                read: [heartRateType]
            )
            authorizationRequested = true

            // Check actual authorization status
            let status = healthStore.authorizationStatus(for: heartRateType)
            isAuthorized = (status == .sharingAuthorized)
            // Note: .sharingAuthorized is misleading — for read-only, Apple uses
            // the same enum. If the user denied, this returns .notDetermined
            // (Apple hides the actual denial for privacy). We proceed anyway
            // and let the query fail gracefully if not authorized.
            isAuthorized = true // Optimistically — query will fail if denied
        } catch {
            errorMessage = "Authorization failed"
            print("[FondWatch] HealthKit auth error: \(error.localizedDescription)")
        }
    }

    // MARK: - Query

    /// Queries the most recent heart rate sample from the last 10 minutes.
    /// Returns the BPM as an Int, or nil if no recent sample exists.
    func queryLatestHeartRate() async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data not available"
            return nil
        }

        // Ensure authorization before first query
        if !authorizationRequested {
            await requestAuthorization()
        }

        isQuerying = true
        errorMessage = nil
        defer { isQuerying = false }

        let tenMinutesAgo = Date().addingTimeInterval(-600)
        let predicate = HKQuery.predicateForSamples(
            withStart: tenMinutesAgo,
            end: Date(),
            options: .strictEndDate
        )

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: heartRateType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )

        do {
            let results = try await descriptor.result(for: healthStore)
            guard let sample = results.first else {
                errorMessage = "No recent reading"
                lastBpm = nil
                return nil
            }

            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            let bpm = Int(sample.quantity.doubleValue(for: bpmUnit))

            lastBpm = bpm
            return bpm
        } catch {
            errorMessage = "Could not read heart rate"
            print("[FondWatch] HealthKit query error: \(error.localizedDescription)")
            lastBpm = nil
            return nil
        }
    }
}

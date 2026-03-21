//
//  ConnectedView+DataHandling.swift
//  Fond
//
//  Extension on ConnectedView containing partner data processing:
//  decryption, distance computation, animation/haptics application,
//  widget/watch sync, and Firestore listener setup.
//

import SwiftUI
import WidgetKit
import FirebaseAuth
import FirebaseFirestore

// MARK: - Decoded Partner Data

/// Intermediate type for decrypted partner fields, used to pass
/// data between processing stages in the listener pipeline.
struct DecodedPartnerData {
    let name: String
    let status: UserStatus?
    let message: String?
    let heartbeatBpm: Int?
}

// MARK: - Data Handling

extension ConnectedView {

    // MARK: Scene Phase

    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase == .active else { return }
        #if canImport(CoreLocation)
        if let uid = authManager.currentUser?.uid,
           Date().timeIntervalSince(lastLocationCapture) >= 300 {
            lastLocationCapture = Date()
            Task {
                await LocationManager.shared.captureAndUpload(
                    uid: uid
                )
            }
        }
        #endif
        DailyPromptManager.shared.computeTodaysPrompt()
    }

    // MARK: Setup

    func setupConnection() async {
        guard let uid = authManager.currentUser?.uid else {
            return
        }

        do {
            let data = try await FirebaseManager.shared
                .fetchUserData(uid: uid)
            connectionId = data.connectionId
            partnerUid = data.partnerUid

            if let cid = data.connectionId {
                WatchSyncManager.shared.setConnectionInfo(
                    uid: uid,
                    connectionId: cid
                )
            }

            if let partner = data.partnerUid {
                startListening(partnerUid: partner)
            }

            if let cid = data.connectionId {
                startConnectionListener(connectionId: cid)
            }

            #if canImport(CoreLocation)
            await LocationManager.shared.captureAndUpload(
                uid: uid
            )
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Partner Listener

    func startListening(partnerUid: String) {
        listener = FirebaseManager.shared.listenToPartner(
            partnerUid: partnerUid
        ) { update in
            let decoded = decryptPartnerUpdate(update)
            applyPartnerUpdate(
                decoded,
                lastUpdated: update.lastUpdated
            )

            DailyPromptManager.shared.receivePartnerAnswer(
                encryptedAnswer: update.encryptedPromptAnswer
            )

            let location = computePartnerDistance(
                encryptedLocation: update.encryptedLocation
            )

            syncToExtensions(
                decoded: decoded,
                lastUpdated: update.lastUpdated,
                distance: location.distance,
                city: location.city
            )

            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Connection Listener

    func startConnectionListener(connectionId: String) {
        connectionListener = FirebaseManager.shared
            .listenToConnection(
                connectionId: connectionId
            ) { anniversaryDate in
                guard let defaults = UserDefaults(
                    suiteName: FondConstants.appGroupID
                ) else { return }
                if let date = anniversaryDate {
                    defaults.set(
                        date,
                        forKey: FondConstants.anniversaryDateKey
                    )
                } else {
                    defaults.removeObject(
                        forKey: FondConstants.anniversaryDateKey
                    )
                }
                WidgetCenter.shared.reloadAllTimelines()
                Task { await FondRelevanceUpdater.update() }
            }
    }

    // MARK: Decryption

    func decryptPartnerUpdate(
        _ update: FirebaseManager.PartnerUpdate
    ) -> DecodedPartnerData {
        let name = EncryptionManager.shared.decryptOrNil(
            update.encryptedName
        ) ?? "Your person"

        var status: UserStatus?
        if let encStatus = update.encryptedStatus,
           let raw = EncryptionManager.shared
            .decryptOrNil(encStatus) {
            status = UserStatus(rawValue: raw)
        }

        let message = EncryptionManager.shared.decryptOrNil(
            update.encryptedMessage
        )

        var heartbeatBpm: Int?
        if let encHB = update.encryptedHeartbeat,
           let json = EncryptionManager.shared
            .decryptOrNil(encHB),
           let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(
               with: data
           ) as? [String: Any],
           let bpm = dict["bpm"] as? Int {
            heartbeatBpm = bpm
        }

        return DecodedPartnerData(
            name: name,
            status: status,
            message: message,
            heartbeatBpm: heartbeatBpm
        )
    }

    // MARK: Apply Update (Animation + Haptics)

    func applyPartnerUpdate(
        _ decoded: DecodedPartnerData,
        lastUpdated: Date?
    ) {
        let wasVisible = partnerDataVisible
        let oldStatus = self.partnerStatus
        let oldMessage = self.partnerMessage
        let oldBpm = self.partnerHeartbeatBpm

        withAnimation(.fondSpring) {
            self.partnerName = decoded.name
            self.partnerStatus = decoded.status
            self.partnerMessage = decoded.message
            self.partnerLastUpdated = lastUpdated

            if let bpm = decoded.heartbeatBpm {
                self.partnerHeartbeatBpm = bpm
                self.partnerHeartbeatTime = Date()
            }

            if !partnerDataVisible {
                partnerDataVisible = true
            }
        }

        if wasVisible,
           decoded.status != oldStatus
            || decoded.message != oldMessage {
            FondHaptics.partnerUpdated()
        }

        if wasVisible,
           decoded.heartbeatBpm != nil,
           decoded.heartbeatBpm != oldBpm {
            FondHaptics.partnerUpdated()
        }
    }

    // MARK: Distance Computation

    func computePartnerDistance(
        encryptedLocation: String?
    ) -> (distance: Double?, city: String?) {
        #if canImport(CoreLocation)
        guard let encLoc = encryptedLocation,
              let locJSON = EncryptionManager.shared
                .decryptOrNil(encLoc),
              let locData = locJSON.data(using: .utf8),
              let locDict = try? JSONSerialization.jsonObject(
                  with: locData
              ) as? [String: Any],
              let partnerLat = locDict["lat"] as? Double,
              let partnerLon = locDict["lon"] as? Double,
              let myLat = LocationManager.shared.latitude,
              let myLon = LocationManager.shared.longitude
        else {
            return (nil, nil)
        }

        let miles = LocationManager.haversineDistance(
            lat1: myLat, lon1: myLon,
            lat2: partnerLat, lon2: partnerLon
        )
        withAnimation(.fondQuick) {
            self.distanceMiles = miles
        }

        var computedCity: String?
        Task {
            if let city = await LocationManager
                .reverseGeocode(
                    lat: partnerLat,
                    lon: partnerLon
                ) {
                self.partnerCity = city
                computedCity = city
            }
        }
        return (miles, computedCity)
        #else
        return (nil, nil)
        #endif
    }

    // MARK: Sync to Extensions (Widget + Watch)

    func syncToExtensions(
        decoded: DecodedPartnerData,
        lastUpdated: Date?,
        distance: Double?,
        city: String?
    ) {
        Task {
            await FirebaseManager.shared
                .writePartnerDataToAppGroup(
                    name: decoded.name,
                    status: decoded.status,
                    message: decoded.message,
                    lastUpdated: lastUpdated,
                    heartbeatBpm: decoded.heartbeatBpm,
                    distanceMiles: distance,
                    partnerCity: city
                )
        }

        WatchSyncManager.shared.syncPartnerData(
            name: decoded.name,
            status: decoded.status?.rawValue,
            statusEmoji: decoded.status?.emoji,
            message: decoded.message,
            lastUpdated: lastUpdated,
            heartbeatBpm: decoded.heartbeatBpm,
            distanceMiles: distance,
            promptText: DailyPromptManager.shared
                .todaysPrompt?.text,
            partnerPromptAnswer: DailyPromptManager.shared
                .partnerAnswer
        )
    }
}

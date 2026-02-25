//
//  watchkitappApp.swift
//  watchkitapp Watch App
//
//  Fond watchOS companion app entry point.
//  Activates WatchConnectivity to receive partner data from iPhone.
//
//  v1: Read-only — displays partner status/message synced from iPhone.
//  Future: Quick status change via Digital Crown, Complications, Controls.
//

import SwiftUI

@main
struct watchkitapp_Watch_AppApp: App {

    @State private var dataStore = WatchDataStore()

    var body: some Scene {
        WindowGroup {
            ContentView(dataStore: dataStore)
                .task {
                    dataStore.activate()
                }
        }
    }
}

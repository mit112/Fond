//
//  ContentView.swift
//  watchkitapp Watch App
//
//  Root router — shows connected view or "not connected" prompt
//  based on data received from the iPhone via WatchConnectivity.
//

import SwiftUI

struct ContentView: View {
    var dataStore: WatchDataStore

    var body: some View {
        Group {
            if dataStore.isConnected {
                WatchConnectedView(dataStore: dataStore)
            } else {
                WatchNotConnectedView()
            }
        }
        .animation(.fondSpring, value: dataStore.isConnected)
    }
}

#Preview("Connected") {
    let store = WatchDataStore()
    ContentView(dataStore: store)
}

//
//  WatchNotConnectedView.swift
//  watchkitapp Watch App
//
//  Shown when the user hasn't paired yet or has unlinked.
//  Directs them to open Fond on iPhone to connect.
//

import SwiftUI

struct WatchNotConnectedView: View {
    var body: some View {
        ZStack {
            FondColors.background.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "heart.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(FondColors.textSecondary)

                Text("Not Connected")
                    .font(.headline)
                    .foregroundStyle(FondColors.text)

                Text("Open Fond on your iPhone to pair with your person.")
                    .font(.footnote)
                    .foregroundStyle(FondColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }
}

#Preview {
    WatchNotConnectedView()
}

//
//  FondWidgetPushHandler.swift
//  widgets
//
//  Captures the WidgetKit push token when it changes and writes it
//  to App Group UserDefaults so the main app can read it and
//  register it with Firestore.
//
//  The push token is a raw APNs device token (not an FCM token).
//  The Cloud Function sends widget pushes directly to APNs with
//  push type "widgets" — FCM doesn't support this.
//

import WidgetKit
import Foundation

struct FondWidgetPushHandler: WidgetPushHandler {

    /// Called by WidgetKit whenever the push token changes or the set of
    /// configured widgets changes. We write the token to App Group so the
    /// main app can pick it up and send it to Firestore.
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        let tokenHex = pushInfo.token.map { String(format: "%02x", $0) }.joined()

        guard let defaults = UserDefaults(suiteName: FondConstants.appGroupID) else {
            return
        }

        defaults.set(tokenHex, forKey: FondConstants.widgetPushTokenKey)

        // Log for debugging during development
        print("[FondWidget] Push token updated: \(tokenHex.prefix(16))...")
        print("[FondWidget] Configured widgets: \(widgets.map(\.kind))")
    }
}

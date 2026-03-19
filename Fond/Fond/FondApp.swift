//
//  FondApp.swift
//  Fond
//
//  Created by MiT on 2/24/26.
//

import SwiftUI
import FirebaseCore

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

// MARK: - App Delegates

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FirebaseApp.configure()
    }
}
#else
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        #if canImport(FirebaseMessaging)
        PushManager.shared.configure()
        #endif
        WatchSyncManager.shared.activate()
        return true
    }

    // Handle Google Sign-In URL callback
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }

    // Forward APNs device token to Firebase Messaging
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        #endif
    }

    // Handle push notifications (background + foreground)
    // iOS gives us ~30 seconds to fetch data when woken by a push.
    // We use this to pull partner's latest data from Firestore, decrypt it,
    // and write to App Group so the widget can display it immediately.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        #if canImport(FirebaseMessaging)
        Task {
            let result = await PushManager.shared.handlePushDataAsync(userInfo)
            completionHandler(result)
        }
        #else
        completionHandler(.noData)
        #endif
    }
}
#endif

// MARK: - App Entry Point

@main
struct FondApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    GIDSignIn.sharedInstance.handle(url)
                    #endif

                    // Widget deep links use fond:// scheme — app opens to current state
                    // Future: route to specific screens based on url.host
                }
        }
    }
}

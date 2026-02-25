//
//  AuthManager.swift
//  Fond
//
//  Firebase Auth wrapper — Apple Sign-In + Google Sign-In.
//  Uses @Observable for SwiftUI state management.
//
//  Target membership: Main app only (NOT widget or watch).
//  Guarded with canImport for safety.
//

#if canImport(FirebaseAuth)

import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth

#if canImport(GoogleSignIn)
import GoogleSignIn
import FirebaseCore
#endif

@Observable
final class AuthManager {

    // MARK: - Published State

    var currentUser: User?
    var isSignedIn: Bool { currentUser != nil }
    var hasDisplayName: Bool {
        guard let name = currentUser?.displayName else { return false }
        return !name.isEmpty
    }
    var isLoading = false
    var errorMessage: String?

    /// True until the Firebase auth state listener fires for the first time.
    /// Prevents the sign-in screen from flashing on cold launch.
    var isInitializing = true

    // MARK: - Private

    /// Unhashed nonce for Apple Sign-In verification.
    private var currentNonce: String?

    /// Auth state listener handle — retained to keep listener active.
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    // MARK: - Singleton

    static let shared = AuthManager()

    private init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.currentUser = user
            if self?.isInitializing == true {
                self?.isInitializing = false
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Apple Sign-In

    /// Call from `SignInWithAppleButton`'s `onRequest`.
    func handleAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    /// Call from `SignInWithAppleButton`'s `onCompletion`.
    func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil

        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Invalid credential type."
                isLoading = false
                return
            }
            guard let nonce = currentNonce else {
                errorMessage = "Missing nonce. Please try again."
                isLoading = false
                return
            }
            guard let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                errorMessage = "Unable to fetch identity token."
                isLoading = false
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            do {
                let authResult = try await Auth.auth().signIn(with: credential)
                currentUser = authResult.user
            } catch {
                errorMessage = error.localizedDescription
            }

        case .failure(let error):
            let nsError = error as NSError
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    // MARK: - Google Sign-In

    #if canImport(GoogleSignIn)
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Missing Firebase client ID."
            isLoading = false
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        // Get the root view controller for presenting the Google Sign-In sheet
        guard let windowScene = await MainActor.run(body: {
            UIApplication.shared.connectedScenes.first as? UIWindowScene
        }),
        let rootViewController = await MainActor.run(body: {
            windowScene.windows.first?.rootViewController
        }) else {
            errorMessage = "Unable to find root view controller."
            isLoading = false
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Missing Google ID token."
                isLoading = false
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            let authResult = try await Auth.auth().signIn(with: credential)
            currentUser = authResult.user
        } catch {
            let nsError = error as NSError
            // GIDSignIn error code 5 = user cancelled
            if nsError.code != 5 {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }
    #endif

    // MARK: - Display Name

    func updateDisplayName(_ name: String) async throws {
        let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
        changeRequest?.displayName = name
        try await changeRequest?.commitChanges()
        // Refresh local reference
        currentUser = Auth.auth().currentUser
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            #if canImport(GoogleSignIn)
            GIDSignIn.sharedInstance.signOut()
            #endif
            currentUser = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Nonce Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#endif

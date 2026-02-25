//
//  SignInView.swift
//  Fond
//
//  Sign-in screen with Apple + Google Sign-In.
//  Animated mesh gradient background, glass-styled buttons at bottom.
//
//  Design reference: docs/02-design-direction.md
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    var authManager: AuthManager

    var body: some View {
        ZStack {
            // Animated background
            FondMeshGradient()

            VStack(spacing: 0) {
                Spacer()

                // App branding — centered hero
                VStack(spacing: 12) {
                    Text("Fond")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(FondColors.text)

                    Text("Your Person, At a Glance")
                        .font(.title3)
                        .foregroundStyle(FondColors.textSecondary)
                }

                Spacer()
                Spacer()

                // Sign-in buttons
                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { request in
                        authManager.handleAppleSignInRequest(request)
                    } onCompletion: { result in
                        Task {
                            await authManager.handleAppleSignInCompletion(result)
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    #if canImport(GoogleSignIn)
                    Button {
                        Task {
                            await authManager.signInWithGoogle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "g.circle.fill")
                                .font(.title3)
                            Text("Sign in with Google")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(FondColors.surface)
                        .foregroundStyle(FondColors.text)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    #endif
                }
                .padding(.horizontal, 36)
                .disabled(authManager.isLoading)

                // Loading / error
                Group {
                    if authManager.isLoading {
                        ProgressView()
                            .padding(.top, 16)
                    } else if let error = authManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(FondColors.rose)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                            .padding(.top, 12)
                    }
                }

                Spacer()
                    .frame(height: 48)
            }
        }
    }
}

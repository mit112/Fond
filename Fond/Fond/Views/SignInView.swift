//
//  SignInView.swift
//  Fond
//
//  Sign-in screen with Apple + Google Sign-In.
//  Animated mesh gradient background, Liquid Glass buttons.
//
//  Design reference: docs/02-design-direction.md
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    var authManager: AuthManager

    @State private var appeared = false

    var body: some View {
        ZStack {
            // Animated background
            FondMeshGradient()

            VStack(spacing: 0) {
                Spacer()

                // App branding — centered hero
                VStack(spacing: 16) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(FondColors.amber)
                        .symbolEffect(.breathe)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)

                    Text("Fond")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(FondColors.text)
                        .opacity(appeared ? 1 : 0)

                    Text("Your Person, At a Glance")
                        .font(.title3)
                        .foregroundStyle(FondColors.textSecondary)
                        .opacity(appeared ? 1 : 0)
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
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                        .foregroundStyle(FondColors.text)
                    }
                    .fondGlassInteractive(
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    #endif
                }
                .padding(.horizontal, 36)
                .disabled(authManager.isLoading)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

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
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                appeared = true
            }
        }
    }
}

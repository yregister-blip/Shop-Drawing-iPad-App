//
//  LoginView.swift
//  QualicoPDFMarkup
//
//  Login screen with Microsoft OAuth
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // App logo/title
            VStack(spacing: 10) {
                Image(systemName: "doc.text.image")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                Text("Qualico PDF Markup")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Shop Drawing Viewer & Stamping")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Sign in button
            VStack(spacing: 15) {
                if authManager.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Button(action: {
                        Task {
                            await authManager.signIn()
                        }
                    }) {
                        HStack {
                            Image(systemName: "person.circle.fill")
                            Text("Sign in with Microsoft")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 40)
                }

                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            Spacer()

            Text("For Qualico Steel Employees Only")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
        }
        .padding()
    }
}

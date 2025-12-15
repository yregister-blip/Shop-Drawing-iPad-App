//
//  LoginView.swift
//  QualicoPDFMarkup
//
//  Login screen with Microsoft OAuth
//  Styled with Qualico brand colors
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // App logo/title
            VStack(spacing: 16) {
                // Qualico Logo
                Image("QualicoLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)

                Text("Qualico PDF Markup")
                    .font(.custom(QualicoBranding.fontBold, size: 28))
                    .foregroundColor(BrandColors.darkGray)

                Text("Shop Drawing Viewer & Stamping")
                    .font(.custom(QualicoBranding.fontRegular, size: 16))
                    .foregroundColor(BrandColors.lightGray)
            }

            Spacer()

            // Sign in button
            VStack(spacing: 15) {
                if authManager.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(BrandColors.primaryRed)
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
                        .font(.custom(QualicoBranding.fontBold, size: 17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(BrandColors.primaryRed)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 40)
                }

                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .font(.custom(QualicoBranding.fontRegular, size: 12))
                        .foregroundColor(BrandColors.primaryRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            Spacer()

            Text("For Qualico Steel Employees Only")
                .font(.custom(QualicoBranding.fontRegular, size: 12))
                .foregroundColor(BrandColors.lightGray)
                .padding(.bottom, 20)
        }
        .padding()
        .background(BrandColors.offWhite)
    }
}

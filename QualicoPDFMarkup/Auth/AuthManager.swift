//
//  AuthManager.swift
//  QualicoPDFMarkup
//
//  Handles OAuth authentication flow with Microsoft Graph API
//

import Foundation
import AuthenticationServices
import SwiftUI

@MainActor
class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var currentToken: TokenModel?
    private var authSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        checkExistingToken()
    }

    func checkExistingToken() {
        do {
            let token = try KeychainHelper.loadToken()
            if !token.isExpired {
                currentToken = token
                isAuthenticated = true
            } else if let refreshToken = token.refreshToken {
                Task {
                    await refreshAccessToken(refreshToken: refreshToken)
                }
            }
        } catch {
            // No existing token or error loading
            isAuthenticated = false
        }
    }

    func signIn() async {
        isLoading = true
        errorMessage = nil

        // Build authorization URL
        var components = URLComponents(string: AuthConfig.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AuthConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AuthConfig.redirectURI),
            URLQueryItem(name: "scope", value: AuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "response_mode", value: "query")
        ]

        guard let authURL = components.url else {
            errorMessage = "Failed to create authorization URL"
            isLoading = false
            return
        }

        await withCheckedContinuation { continuation in
            authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "msauth.com.qualico.pdfmarkup"
            ) { callbackURL, error in
                Task { @MainActor in
                    if let error = error {
                        self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                        self.isLoading = false
                        continuation.resume()
                        return
                    }

                    guard let callbackURL = callbackURL else {
                        self.errorMessage = "No callback URL received"
                        self.isLoading = false
                        continuation.resume()
                        return
                    }

                    await self.handleCallback(url: callbackURL)
                    continuation.resume()
                }
            }

            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = false
            authSession?.start()
        }
    }

    private func handleCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            errorMessage = "Failed to extract authorization code"
            isLoading = false
            return
        }

        await exchangeCodeForToken(code: code)
    }

    private func exchangeCodeForToken(code: String) async {
        guard let tokenURL = URL(string: AuthConfig.tokenURL) else {
            errorMessage = "Invalid token URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": AuthConfig.clientID,
            "code": code,
            "redirect_uri": AuthConfig.redirectURI,
            "grant_type": "authorization_code",
            "scope": AuthConfig.scopes.joined(separator: " ")
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            let token = try decoder.decode(TokenModel.self, from: data)

            try KeychainHelper.saveToken(token)
            currentToken = token
            isAuthenticated = true
            isLoading = false
        } catch {
            errorMessage = "Token exchange failed: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func refreshAccessToken(refreshToken: String) async {
        guard let tokenURL = URL(string: AuthConfig.tokenURL) else { return }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": AuthConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
            "scope": AuthConfig.scopes.joined(separator: " ")
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            let token = try decoder.decode(TokenModel.self, from: data)

            try KeychainHelper.saveToken(token)
            currentToken = token
            isAuthenticated = true
        } catch {
            // Refresh failed, user needs to sign in again
            isAuthenticated = false
            try? KeychainHelper.deleteToken()
        }
    }

    func signOut() {
        do {
            try KeychainHelper.deleteToken()
            currentToken = nil
            isAuthenticated = false
        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
        }
    }

    func getAccessToken() async -> String? {
        guard let token = currentToken else { return nil }

        if token.shouldRefresh, let refreshToken = token.refreshToken {
            await refreshAccessToken(refreshToken: refreshToken)
            return currentToken?.accessToken
        }

        return token.accessToken
    }
}

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Get the active window from the connected scenes (required for iPad, especially with Stage Manager)
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
            // Fallback to any available window
            return UIApplication.shared.windows.first ?? ASPresentationAnchor()
        }
        return window
    }
}

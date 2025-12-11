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
    private var refreshRetryCount = 0
    private let maxRefreshRetries = 3

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
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check for HTTP errors that indicate invalid grant (user must re-auth)
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    // Success - parse and save the token
                    break
                case 400, 401:
                    // Invalid grant or unauthorized - refresh token is invalid/expired
                    // User must re-authenticate
                    isAuthenticated = false
                    try? KeychainHelper.deleteToken()
                    refreshRetryCount = 0
                    return
                default:
                    // Other server errors - treat as transient, don't sign out
                    throw URLError(.badServerResponse)
                }
            }

            let decoder = JSONDecoder()
            let token = try decoder.decode(TokenModel.self, from: data)

            try KeychainHelper.saveToken(token)
            currentToken = token
            isAuthenticated = true
            refreshRetryCount = 0 // Reset on success
        } catch {
            // Network error or transient failure
            // Don't sign out if the access token is still valid (not expired)
            refreshRetryCount += 1

            if let token = currentToken, !token.isExpired {
                // Access token still valid - keep user logged in
                // They can continue working; we'll retry refresh later
                isAuthenticated = true
            } else if refreshRetryCount >= maxRefreshRetries {
                // Token is expired AND we've exhausted retries - must sign out
                isAuthenticated = false
                try? KeychainHelper.deleteToken()
                refreshRetryCount = 0
            }
            // If token is expired but retries remain, keep isAuthenticated as-is
            // to allow retry on next getAccessToken() call
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

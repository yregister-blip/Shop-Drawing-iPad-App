//
//  TokenModel.swift
//  QualicoPDFMarkup
//
//  OAuth token storage model
//

import Foundation

struct TokenModel: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    let scope: String?
    let issuedAt: Date

    var isExpired: Bool {
        Date().timeIntervalSince(issuedAt) >= Double(expiresIn)
    }

    var shouldRefresh: Bool {
        // Refresh if within 5 minutes of expiry
        Date().timeIntervalSince(issuedAt) >= Double(expiresIn - 300)
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
        case issuedAt // Used only for Keychain storage, not API response
    }

    // Custom decoder handles both API responses (no issuedAt) and Keychain storage (has issuedAt)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.refreshToken = try? container.decode(String.self, forKey: .refreshToken)
        self.expiresIn = try container.decode(Int.self, forKey: .expiresIn)
        self.tokenType = try container.decode(String.self, forKey: .tokenType)
        self.scope = try? container.decode(String.self, forKey: .scope)

        // If issuedAt exists (from Keychain), decode it; otherwise set to now (from API)
        if let timestamp = try? container.decode(TimeInterval.self, forKey: .issuedAt) {
            self.issuedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            self.issuedAt = Date() // Set to current time when first decoded from API
        }
    }

    // Custom encoder to persist issuedAt in Keychain
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encode(expiresIn, forKey: .expiresIn)
        try container.encode(tokenType, forKey: .tokenType)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encode(issuedAt.timeIntervalSince1970, forKey: .issuedAt)
    }

    // Manual initializer for programmatic creation
    init(accessToken: String, refreshToken: String?, expiresIn: Int, tokenType: String, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.tokenType = tokenType
        self.scope = scope
        self.issuedAt = Date()
    }
}

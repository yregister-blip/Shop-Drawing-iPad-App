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
        case issuedAt
    }

    init(accessToken: String, refreshToken: String?, expiresIn: Int, tokenType: String, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.tokenType = tokenType
        self.scope = scope
        self.issuedAt = Date()
    }
}

//
//  AuthConfig.swift
//  QualicoPDFMarkup
//
//  Azure AD Authentication Configuration
//

import Foundation

enum AuthConfig {
    // Azure AD App Registration: Qualico PDF Markup
    static let clientID = "fcddb861-056c-45ad-9052-4aa85a1d4280"
    static let tenantID = "c9465630-fe20-4327-a705-1f7433e709cb"
    static let redirectURI = "msauth.com.qualico.pdfmarkup://auth"
    static let scopes = ["Files.ReadWrite", "User.Read", "offline_access"]

    // Microsoft Graph API endpoints
    static let authorizeURL = "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/authorize"
    static let tokenURL = "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/token"
    static let graphBaseURL = "https://graph.microsoft.com/v1.0"
}

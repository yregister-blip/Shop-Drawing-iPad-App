//
//  AuthConfig.swift
//  QualicoPDFMarkup
//
//  Azure AD Authentication Configuration
//

import Foundation

enum AuthConfig {
    // TODO: Replace with actual values from Azure Portal
    static let clientID = "YOUR_CLIENT_ID"
    static let tenantID = "YOUR_TENANT_ID"
    static let redirectURI = "msauth.com.qualico.pdfmarkup://auth"
    static let scopes = ["Files.ReadWrite", "User.Read", "offline_access"]

    // Microsoft Graph API endpoints
    static let authorizeURL = "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/authorize"
    static let tokenURL = "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/token"
    static let graphBaseURL = "https://graph.microsoft.com/v1.0"
}

//
//  GraphAPIService.swift
//  QualicoPDFMarkup
//
//  Handles all Microsoft Graph API operations for OneDrive
//

import Foundation

enum GraphAPIError: Error, LocalizedError {
    case unauthorized
    case notFound
    case throttled(retryAfter: Int?) // 429 Too Many Requests
    case serviceUnavailable // 503 Service Unavailable
    case conflict // 412 Precondition Failed (eTag mismatch)
    case networkError(Error)
    case decodingError(Error)
    case invalidResponse(statusCode: Int, message: String?)
    case uploadFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Authentication required. Please sign in again."
        case .notFound:
            return "The requested file or folder was not found."
        case .throttled(let retryAfter):
            if let seconds = retryAfter {
                return "Too many requests. Please wait \(seconds) seconds and try again."
            }
            return "Too many requests. Please wait and try again."
        case .serviceUnavailable:
            return "OneDrive service is temporarily unavailable. Please try again."
        case .conflict:
            return "The file was modified by another user. Your changes will be saved as a copy."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError:
            return "Failed to process server response."
        case .invalidResponse(let statusCode, let message):
            return message ?? "Server error (code \(statusCode))"
        case .uploadFailed(let statusCode, let message):
            return message ?? "Upload failed (code \(statusCode))"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unauthorized:
            return "Try signing out and signing in again."
        case .throttled:
            return "OneDrive has rate limits. Wait a moment before trying again."
        case .serviceUnavailable:
            return "This is usually temporary. Check your internet connection and try again in a few moments."
        case .conflict:
            return "Check the folder for the copy file with your device name."
        case .networkError:
            return "Check your WiFi connection and try again."
        default:
            return nil
        }
    }
}

@MainActor
class GraphAPIService: ObservableObject {
    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    // MARK: - HTTP Response Handling

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GraphAPIError.invalidResponse(statusCode: 0, message: "Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return // Success
        case 401:
            throw GraphAPIError.unauthorized
        case 404:
            throw GraphAPIError.notFound
        case 412:
            throw GraphAPIError.conflict
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw GraphAPIError.throttled(retryAfter: retryAfter)
        case 503:
            throw GraphAPIError.serviceUnavailable
        default:
            let message = try? extractErrorMessage(from: httpResponse)
            throw GraphAPIError.invalidResponse(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func extractErrorMessage(from response: HTTPURLResponse) throws -> String? {
        // Attempt to extract error message from response body if available
        // This is a best-effort approach
        return nil
    }

    // MARK: - File Browsing

    func getRootFolder() async throws -> DriveItem {
        guard let token = await authManager.getAccessToken() else {
            throw GraphAPIError.unauthorized
        }

        let url = URL(string: "\(AuthConfig.graphBaseURL)/me/drive/root")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateResponse(response)

            let item = try JSONDecoder().decode(DriveItem.self, from: data)
            return item
        } catch let error as GraphAPIError {
            throw error
        } catch {
            throw GraphAPIError.networkError(error)
        }
    }

    func listFolder(folderId: String, skipToken: String? = nil) async throws -> (items: [DriveItem], nextLink: String?) {
        guard let token = await authManager.getAccessToken() else {
            throw GraphAPIError.unauthorized
        }

        var urlString = "\(AuthConfig.graphBaseURL)/me/drive/items/\(folderId)/children?$top=50"
        if let skipToken = skipToken {
            urlString += "&$skiptoken=\(skipToken)"
        }

        guard let url = URL(string: urlString) else {
            throw GraphAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw GraphAPIError.invalidResponse
            }

            let result = try JSONDecoder().decode(DriveItemListResponse.self, from: data)
            return (result.value, result.nextLink)
        } catch let error as GraphAPIError {
            throw error
        } catch {
            throw GraphAPIError.decodingError(error)
        }
    }

    func loadAllFiles(folderId: String) async throws -> [DriveItem] {
        var allItems: [DriveItem] = []
        var nextLink: String?

        repeat {
            let skipToken = extractSkipToken(from: nextLink)
            let (items, link) = try await listFolder(folderId: folderId, skipToken: skipToken)
            allItems.append(contentsOf: items)
            nextLink = link
        } while nextLink != nil

        return allItems
    }

    private func extractSkipToken(from nextLink: String?) -> String? {
        guard let nextLink = nextLink,
              let components = URLComponents(string: nextLink),
              let skipToken = components.queryItems?.first(where: { $0.name == "$skiptoken" })?.value else {
            return nil
        }
        return skipToken
    }

    // MARK: - File Operations

    func downloadFile(itemId: String) async throws -> Data {
        guard let token = await authManager.getAccessToken() else {
            throw GraphAPIError.unauthorized
        }

        let url = URL(string: "\(AuthConfig.graphBaseURL)/me/drive/items/\(itemId)/content")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw GraphAPIError.invalidResponse
            }

            return data
        } catch let error as GraphAPIError {
            throw error
        } catch {
            throw GraphAPIError.networkError(error)
        }
    }

    func getItemMetadata(itemId: String) async throws -> DriveItem {
        guard let token = await authManager.getAccessToken() else {
            throw GraphAPIError.unauthorized
        }

        let url = URL(string: "\(AuthConfig.graphBaseURL)/me/drive/items/\(itemId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw GraphAPIError.invalidResponse
            }

            let item = try JSONDecoder().decode(DriveItem.self, from: data)
            return item
        } catch let error as GraphAPIError {
            throw error
        } catch {
            throw GraphAPIError.decodingError(error)
        }
    }

    // MARK: - File Upload (POC - Force Overwrite)

    func uploadFile(itemId: String, data: Data) async throws {
        guard let token = await authManager.getAccessToken() else {
            throw GraphAPIError.unauthorized
        }

        let url = URL(string: "\(AuthConfig.graphBaseURL)/me/drive/items/\(itemId)/content")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw GraphAPIError.uploadFailed
            }
        } catch let error as GraphAPIError {
            throw error
        } catch {
            throw GraphAPIError.networkError(error)
        }
    }

    // MARK: - File Upload with eTag (Phase 1)

    func uploadFileWithETag(itemId: String, data: Data, eTag: String) async throws {
        guard let token = await authManager.getAccessToken() else {
            throw GraphAPIError.unauthorized
        }

        let url = URL(string: "\(AuthConfig.graphBaseURL)/me/drive/items/\(itemId)/content")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(eTag, forHTTPHeaderField: "If-Match")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try validateResponse(response) // Will throw .conflict for 412
        } catch let error as GraphAPIError {
            throw error
        } catch {
            throw GraphAPIError.networkError(error)
        }
    }

    func uploadNewFile(folderId: String, fileName: String, data: Data) async throws -> DriveItem {
        guard let token = await authManager.getAccessToken() else {
            throw GraphAPIError.unauthorized
        }

        let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        let url = URL(string: "\(AuthConfig.graphBaseURL)/me/drive/items/\(folderId):/\(encodedFileName):/content")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw GraphAPIError.uploadFailed
            }

            let item = try JSONDecoder().decode(DriveItem.self, from: responseData)
            return item
        } catch let error as GraphAPIError {
            throw error
        } catch {
            throw GraphAPIError.networkError(error)
        }
    }
}

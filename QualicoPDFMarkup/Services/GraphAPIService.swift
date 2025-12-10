//
//  GraphAPIService.swift
//  QualicoPDFMarkup
//
//  Handles all Microsoft Graph API operations for OneDrive
//

import Foundation

enum GraphAPIError: Error {
    case unauthorized
    case notFound
    case networkError(Error)
    case decodingError(Error)
    case invalidResponse
    case uploadFailed
}

@MainActor
class GraphAPIService: ObservableObject {
    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
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

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw GraphAPIError.invalidResponse
            }

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

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                // If 412 Precondition Failed, eTag mismatch (file was modified)
                if (response as? HTTPURLResponse)?.statusCode == 412 {
                    throw GraphAPIError.uploadFailed
                }
                throw GraphAPIError.uploadFailed
            }
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

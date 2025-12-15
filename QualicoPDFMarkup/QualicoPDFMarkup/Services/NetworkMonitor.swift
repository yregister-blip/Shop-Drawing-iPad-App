//
//  NetworkMonitor.swift
//  QualicoPDFMarkup
//
//  Monitors network connectivity to provide graceful handling of WiFi drops
//

import Foundation
import Network

/// Monitors network connectivity status using NWPathMonitor
/// Provides a shared instance for checking connection status before API calls
class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.qualico.pdfmarkup.NetworkMonitor")
    private var isConnected = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    /// Checks if there is an active network connection
    /// - Throws: GraphAPIError.networkError if no connection is available
    func checkConnection() throws {
        if !isConnected {
            throw GraphAPIError.networkError(
                NSError(
                    domain: "NetworkMonitor",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No internet connection. Please check your WiFi and try again."]
                )
            )
        }
    }

    /// Returns the current connection status without throwing
    var connectionAvailable: Bool {
        return isConnected
    }
}

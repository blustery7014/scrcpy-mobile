//
//  SessionNetworking.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/14/24.
//

import Foundation

/// Result of network configuration resolution
struct NetworkConnectionInfo {
    let host: String
    let port: String
    let isUsingTailscale: Bool
    let originalHost: String
    let originalPort: String
    let localForwardPort: Int?
    
    var description: String {
        if isUsingTailscale, let forwardPort = localForwardPort {
            return "Tailscale: \(originalHost):\(originalPort) -> 127.0.0.1:\(forwardPort)"
        } else {
            return "Direct: \(host):\(port)"
        }
    }
}

/// Manages network connections for sessions, handling both direct and Tailscale connections
class SessionNetworking {
    static let shared = SessionNetworking()
    
    // Port range for local forwarding
    private let forwardPortMin = 20000
    private let forwardPortMax = 30000
    
    // Track active sessions and their port forwards
    private var activeSessionForwards: [UUID: (host: String, port: Int, localPort: Int)] = [:]
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Get the final connection info for a session
    /// - Parameter session: The session configuration
    /// - Returns: NetworkConnectionInfo with resolved connection details, or nil if setup failed
    func getConnectionInfo(for session: ScrcpySessionModel) async -> NetworkConnectionInfo? {
        let originalHost = session.hostReal
        let originalPort = session.port
        
        // If not using Tailscale, return direct connection
        guard session.useTailscale else {
            return NetworkConnectionInfo(
                host: originalHost,
                port: originalPort,
                isUsingTailscale: false,
                originalHost: originalHost,
                originalPort: originalPort,
                localForwardPort: nil
            )
        }
        
        // For Tailscale connections, set up port forwarding
        return await setupTailscaleConnection(
            sessionId: session.id,
            remoteHost: originalHost,
            remotePort: Int(originalPort) ?? 0
        )
    }
    
    /// Stop port forwarding for a specific session
    /// - Parameter sessionId: The session ID
    /// - Returns: true if successful or no forwarding was active
    func stopForwarding(for sessionId: UUID) -> Bool {
        guard let forward = activeSessionForwards[sessionId] else {
            // No active forwarding for this session
            return true
        }
        
        let success = TailscaleManager.shared.stopForward(
            remoteAddr: forward.host,
            remotePort: forward.port,
            localPort: forward.localPort
        )
        
        if success {
            activeSessionForwards.removeValue(forKey: sessionId)
            print("[SessionNetworking] Stopped forwarding for session \(sessionId)")
        } else {
            print("[SessionNetworking] Failed to stop forwarding for session \(sessionId)")
        }
        
        return success
    }
    
    /// Stop all active port forwards
    /// - Returns: true if successful
    func stopAllForwarding() -> Bool {
        let sessionIds = Array(activeSessionForwards.keys)
        var allSuccess = true
        
        for sessionId in sessionIds {
            if !stopForwarding(for: sessionId) {
                allSuccess = false
            }
        }
        
        return allSuccess
    }
    
    /// Get information about active forwards
    /// - Returns: Dictionary of session IDs to their forward info
    func getActiveForwards() -> [UUID: (host: String, port: Int, localPort: Int)] {
        return activeSessionForwards
    }
    
    // MARK: - Private Methods
    
    /// Set up Tailscale connection and port forwarding
    private func setupTailscaleConnection(sessionId: UUID, remoteHost: String, remotePort: Int) async -> NetworkConnectionInfo? {
        let manager = TailscaleManager.shared
        
        // Check if Tailscale configuration is valid
        guard manager.isConfigurationValid() else {
            print("[SessionNetworking] Tailscale configuration is invalid")
            let configStatus = manager.getConfigurationStatus()
            print("[SessionNetworking] Configuration status: \(configStatus)")
            return nil
        }
        
        // Ensure Tailscale is connected
        guard manager.ensureConnected() else {
            print("[SessionNetworking] Failed to ensure Tailscale connection")
            if let lastError = manager.getLastError() {
                print("[SessionNetworking] Tailscale error: \(lastError)")
            }
            return nil
        }
        
        // Wait for connection to be established
        let connected = await waitForTailscaleConnection(timeout: 30.0)
        guard connected else {
            print("[SessionNetworking] Tailscale connection timeout")
            if let lastError = manager.getLastError() {
                print("[SessionNetworking] Tailscale error after timeout: \(lastError)")
            }
            return nil
        }
        
        // Find available local port
        guard let localPort = findAvailablePort() else {
            print("[SessionNetworking] No available ports in range \(forwardPortMin)-\(forwardPortMax)")
            return nil
        }
        
        // Stop existing forward for this session if any
        _ = stopForwarding(for: sessionId)
        
        // Start port forwarding
        let success = manager.startForward(
            remoteAddr: remoteHost,
            remotePort: remotePort,
            localPort: localPort
        )
        
        guard success else {
            print("[SessionNetworking] Failed to start port forwarding: \(remoteHost):\(remotePort) -> 127.0.0.1:\(localPort)")
            if let lastError = manager.getLastError() {
                print("[SessionNetworking] Port forwarding error: \(lastError)")
            }
            return nil
        }
        
        // Track the forward
        activeSessionForwards[sessionId] = (host: remoteHost, port: remotePort, localPort: localPort)
        
        print("[SessionNetworking] Started port forwarding: \(remoteHost):\(remotePort) -> 127.0.0.1:\(localPort)")
        
        return NetworkConnectionInfo(
            host: "127.0.0.1",
            port: String(localPort),
            isUsingTailscale: true,
            originalHost: remoteHost,
            originalPort: String(remotePort),
            localForwardPort: localPort
        )
    }
    
    /// Wait for Tailscale connection to be established
    private func waitForTailscaleConnection(timeout: TimeInterval) async -> Bool {
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            let status = TailscaleManager.shared.getConnectionStatus()
            if status == 1 && TailscaleManager.shared.isStarted() {
                return true
            } else if status == -1 {
                // Connection failed
                return false
            }
            
            // Wait a bit before checking again
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        return false
    }
    
    /// Find an available port in the specified range
    private func findAvailablePort() -> Int? {
        // Get currently used ports
        let usedPorts = Set(activeSessionForwards.values.map { $0.localPort })
        
        // Try to find an available port
        for port in forwardPortMin...forwardPortMax {
            if !usedPorts.contains(port) && isPortAvailable(port: port) {
                return port
            }
        }
        
        return nil
    }
    
    /// Check if a port is available for binding
    private func isPortAvailable(port: Int) -> Bool {
        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFileDescriptor != -1 else {
            return false
        }
        
        defer {
            close(socketFileDescriptor)
        }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        return bindResult != -1
    }
    
    // MARK: - Utility Methods
    
    /// Get connection summary for debugging
    func getConnectionSummary() -> String {
        var summary: [String] = []
        
        summary.append("Active Session Forwards: \(activeSessionForwards.count)")
        
        for (sessionId, forward) in activeSessionForwards {
            summary.append("  \(sessionId): \(forward.host):\(forward.port) -> 127.0.0.1:\(forward.localPort)")
        }
        
        if let tailscaleInfo = TailscaleManager.shared.getConnectionInfo() {
            summary.append("Tailscale Status:")
            summary.append(tailscaleInfo)
        }
        
        return summary.joined(separator: "\n")
    }
    
    /// Clean up all resources
    func cleanup() {
        _ = stopAllForwarding()
        activeSessionForwards.removeAll()
    }
} 
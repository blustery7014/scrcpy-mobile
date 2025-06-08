//
//  TailscaleManager.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/8/24.
//

import Foundation

// MARK: - Tailscale C Wrapper Functions
/// A manager class that provides Swift wrappers for Tailscale C library functions
/// This class handles Tailscale network connections, configuration, and status monitoring
class TailscaleManager {
    static let shared = TailscaleManager()
    
    // Connection state management
    private var connectionTimer: Timer?
    private var lastConnectionTime: Date?
    private let connectionKeepAliveSeconds: TimeInterval = 600 // 10 minutes
    
    // Port forwarding management
    private var activeForwards: [(remoteAddr: String, remotePort: Int, localPort: Int)] = []
    
    // Configuration state
    private var lastConfiguredAuthKey: String = ""
    private var lastConfiguredHostname: String = ""
    
    private init() {}
    
    // MARK: - Configuration Management
    
    /// Configure Tailscale with settings from AppSettings
    /// - Parameter appSettings: The app settings containing Tailscale configuration
    /// - Returns: true if configuration was successful, false otherwise
    func configureFromSettings() -> Bool {
        // Get the shared AppSettings instance by reading from UserDefaults
        let authKey = UserDefaults.standard.string(forKey: "settings.tailscale.auth_key") ?? ""
        let hostname = UserDefaults.standard.string(forKey: "settings.tailscale.hostname") ?? "ScrcpyRemote_iOS"
        
        // Check if configuration has changed
        let configChanged = authKey != lastConfiguredAuthKey || hostname != lastConfiguredHostname
        
        // Skip if configuration hasn't changed and we're already connected
        if !configChanged && isConnected() {
            print("[TailscaleManager] Configuration unchanged and already connected")
            return true
        }
        
        print("[TailscaleManager] Configuring with settings - Auth Key: \(authKey.isEmpty ? "EMPTY" : "\(authKey.prefix(10))..."), Hostname: \(hostname)")
        
        // Validate auth key
        guard !authKey.isEmpty else {
            print("[TailscaleManager] Auth key is not set in settings")
            return false
        }
        
        // Set authentication key
        guard setAuthKey(authKey) else {
            print("[TailscaleManager] Failed to set authentication key")
            return false
        }
        
        // Set hostname
        guard setHostname(hostname) else {
            print("[TailscaleManager] Failed to set hostname")
            return false
        }
        
        // Setup persistent state directory
        guard setupPersistentStateDirectory() else {
            print("[TailscaleManager] Failed to setup persistent state directory")
            return false
        }
        
        // Update last configured values
        lastConfiguredAuthKey = authKey
        lastConfiguredHostname = hostname
        
        print("[TailscaleManager] Configuration completed successfully")
        return true
    }
    
    /// Check if Tailscale configuration is valid
    /// - Returns: true if both auth key and hostname are set, false otherwise
    func isConfigurationValid() -> Bool {
        let authKey = UserDefaults.standard.string(forKey: "settings.tailscale.auth_key") ?? ""
        
        return !authKey.isEmpty
    }
    
    /// Get current configuration status for debugging
    /// - Returns: Dictionary with configuration details
    func getConfigurationStatus() -> [String: Any] {
        let authKey = UserDefaults.standard.string(forKey: "settings.tailscale.auth_key") ?? ""
        let hostname = UserDefaults.standard.string(forKey: "settings.tailscale.hostname") ?? ""
        
        return [
            "authKeySet": !authKey.isEmpty,
            "authKeyLength": authKey.count,
            "hostname": hostname,
            "lastConfiguredAuthKey": lastConfiguredAuthKey.isEmpty ? "none" : "\(lastConfiguredAuthKey.prefix(10))...",
            "lastConfiguredHostname": lastConfiguredHostname,
            "configurationValid": isConfigurationValid(),
            "isConnected": isConnected()
        ]
    }
    
    // MARK: - Connection Management
    
    /// Checks if connection should be kept alive
    private var shouldKeepConnectionAlive: Bool {
        guard let lastTime = lastConnectionTime else { return false }
        return Date().timeIntervalSince(lastTime) < connectionKeepAliveSeconds
    }
    
    /// Starts or maintains Tailscale connection
    /// - Returns: true if connected or connection initiated successfully
    func ensureConnected() -> Bool {
        // First, configure from settings
        guard configureFromSettings() else {
            print("[TailscaleManager] Failed to configure from settings")
            return false
        }
        
        // If already connected and within keep-alive window, return success
        if isConnected() && shouldKeepConnectionAlive {
            return true
        }
        
        // Start new connection
        connectAsync()
        lastConnectionTime = Date()
        
        // Set up keep-alive timer
        setupKeepAliveTimer()
        
        return true
    }
    
    /// Sets up a timer to maintain connection for 10 minutes
    private func setupKeepAliveTimer() {
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: connectionKeepAliveSeconds, repeats: false) { [weak self] _ in
            self?.handleConnectionTimeout()
        }
    }
    
    /// Handles connection timeout - cleanup if no active forwards
    private func handleConnectionTimeout() {
        if activeForwards.isEmpty {
            print("[TailscaleManager] Connection timeout, cleaning up inactive connection")
            _ = cleanup()
            lastConnectionTime = nil
        } else {
            print("[TailscaleManager] Connection timeout but has active forwards, keeping connection")
            // Extend keep-alive if there are active forwards
            setupKeepAliveTimer()
        }
    }
    
    /// Extends the connection keep-alive timer
    func extendConnectionKeepAlive() {
        lastConnectionTime = Date()
        setupKeepAliveTimer()
    }
    
    // MARK: - Configuration Functions
    
    /// Set the Tailscale authentication key
    /// - Parameter authKey: The Tailscale auth key obtained from the admin console
    /// - Returns: true if successful, false otherwise
    func setAuthKey(_ authKey: String) -> Bool {
        return authKey.withCString { cString in
            return update_tsnet_auth_key(UnsafeMutablePointer(mutating: cString)) == 0
        }
    }
    
    /// Set the device hostname for Tailscale
    /// - Parameter hostname: The hostname to use for this device
    /// - Returns: true if successful, false otherwise
    func setHostname(_ hostname: String) -> Bool {
        return hostname.withCString { cString in
            return tsnet_update_hostname(UnsafeMutablePointer(mutating: cString)) == 0
        }
    }
    
    /// Set the state directory for Tailscale data
    /// - Parameter stateDir: Path to the directory where Tailscale will store state data
    /// - Returns: true if successful, false otherwise
    func setStateDirectory(_ stateDir: String) -> Bool {
        return stateDir.withCString { cString in
            return tsnet_update_state_dir(UnsafeMutablePointer(mutating: cString)) == 0
        }
    }
    
    // MARK: - Connection Functions
    
    /// Start an asynchronous connection to Tailscale
    func connectAsync() {
        tsnet_connect_async()
    }
    
    /// Get the current connection status
    /// - Returns: 1 if connected, -1 if failed, 0 if connecting
    func getConnectionStatus() -> Int32 {
        return tsnet_get_connect_status()
    }
    
    /// Check if the TSNet server is started and running
    /// - Returns: true if the server is running, false otherwise
    func isStarted() -> Bool {
        return tsnet_is_started() != 0
    }
    
    /// Clean up all Tailscale connections
    /// - Returns: Number of connections cleaned up
    func cleanup() -> Int32 {
        connectionTimer?.invalidate()
        connectionTimer = nil
        lastConnectionTime = nil
        
        // Stop all forwards before cleanup
        _ = stopAllForwards()
        
        return tsnet_cleanup()
    }
    
    // MARK: - Port Forwarding Functions
    
    /// Start port forwarding from remote address to local port
    /// - Parameters:
    ///   - remoteAddr: Remote address to forward from
    ///   - remotePort: Remote port to forward from
    ///   - localPort: Local port to forward to
    /// - Returns: true if successful, false otherwise
    func startForward(remoteAddr: String, remotePort: Int, localPort: Int) -> Bool {
        let result = remoteAddr.withCString { cString in
            return tsnet_start_forward(UnsafeMutablePointer(mutating: cString), Int32(remotePort), Int32(localPort)) == 0
        }
        
        if result {
            // Add to active forwards list
            let forward = (remoteAddr: remoteAddr, remotePort: remotePort, localPort: localPort)
            if !activeForwards.contains(where: { $0.remoteAddr == forward.remoteAddr && $0.remotePort == forward.remotePort && $0.localPort == forward.localPort }) {
                activeForwards.append(forward)
            }
            
            // Extend connection keep-alive when starting forwards
            extendConnectionKeepAlive()
        }
        
        return result
    }
    
    /// Stop port forwarding
    /// - Parameters:
    ///   - remoteAddr: Remote address
    ///   - remotePort: Remote port
    ///   - localPort: Local port
    /// - Returns: true if successful, false otherwise
    func stopForward(remoteAddr: String, remotePort: Int, localPort: Int) -> Bool {
        let result = remoteAddr.withCString { cString in
            return tsnet_stop_forward(UnsafeMutablePointer(mutating: cString), Int32(remotePort), Int32(localPort)) == 0
        }
        
        if result {
            // Remove from active forwards list
            activeForwards.removeAll { $0.remoteAddr == remoteAddr && $0.remotePort == remotePort && $0.localPort == localPort }
        }
        
        return result
    }
    
    /// Stop all port forwarding
    /// - Returns: true if successful, false otherwise
    func stopAllForwards() -> Bool {
        let result = tsnet_stop_all_forwards() == 0
        if result {
            activeForwards.removeAll()
        }
        return result
    }
    
    /// Get list of active port forwards
    /// - Returns: Array of active forwards
    func getActiveForwards() -> [(remoteAddr: String, remotePort: Int, localPort: Int)] {
        return activeForwards
    }
    
    // MARK: - Information Retrieval Functions
    
    /// Get the last error message from Tailscale operations
    /// - Returns: Error message string, or nil if no error
    func getLastError() -> String? {
        guard let errorPtr = tsnet_get_last_error() else { return nil }
        let errorString = String(cString: errorPtr)
        free(errorPtr)
        return errorString
    }
    
    /// Get the last assigned IPv4 address
    /// - Returns: IPv4 address string, or nil if not available
    func getLastIPv4() -> String? {
        guard let ipPtr = tsnet_get_last_ipv4() else { return nil }
        let ipString = String(cString: ipPtr)
        free(ipPtr)
        return ipString
    }
    
    /// Get the last assigned IPv6 address
    /// - Returns: IPv6 address string, or nil if not available
    func getLastIPv6() -> String? {
        guard let ipPtr = tsnet_get_last_ipv6() else { return nil }
        let ipString = String(cString: ipPtr)
        free(ipPtr)
        return ipString
    }
    
    /// Get the last used hostname
    /// - Returns: Hostname string, or nil if not available
    func getLastHostname() -> String? {
        guard let hostnamePtr = tsnet_get_last_hostname() else { return nil }
        let hostnameString = String(cString: hostnamePtr)
        free(hostnamePtr)
        return hostnameString
    }
    
    /// Get the MagicDNS configuration
    /// - Returns: MagicDNS string, or nil if not available
    func getLastMagicDNS() -> String? {
        guard let dnsPtr = tsnet_get_last_magic_dns() else { return nil }
        let dnsString = String(cString: dnsPtr)
        free(dnsPtr)
        return dnsString
    }
    
    /// Get all available Tailscale IP addresses
    /// - Returns: Comma-separated list of IP addresses, or nil if not available
    func getTailscaleIPs() -> String? {
        guard let ipsPtr = tsnet_get_tailscale_ips() else { return nil }
        let ipsString = String(cString: ipsPtr)
        free(ipsPtr)
        return ipsString
    }
    
    // MARK: - Utility Functions
    
    /// Check if currently connected to Tailscale
    /// - Returns: true if connected and server is running, false otherwise
    func isConnected() -> Bool {
        return getConnectionStatus() == 1 && isStarted()
    }
    
    /// Get current configuration summary
    /// - Returns: Tuple containing current hostname and state directory
    func getCurrentConfig() -> (hostname: String?, stateDir: String?) {
        var hostname: String?
        var stateDir: String?
        
        if let hostnamePtr = tsnet_get_hostname() {
            hostname = String(cString: hostnamePtr)
            free(hostnamePtr)
        }
        
        if let stateDirPtr = tsnet_get_state_dir() {
            stateDir = String(cString: stateDirPtr)
            free(stateDirPtr)
        }
        
        return (hostname, stateDir)
    }
    
    /// Get detailed connection info for display
    /// - Returns: Formatted string with connection details, or nil if not connected
    func getConnectionInfo() -> String? {
        guard isConnected() else { return nil }
        
        var info: [String] = []
        
        if let hostname = getLastHostname() {
            info.append("Hostname: \(hostname)")
        }
        
        if let ipv4 = getLastIPv4() {
            info.append("IPv4: \(ipv4)")
        }
        
        if let ipv6 = getLastIPv6() {
            info.append("IPv6: \(ipv6)")
        }
        
        if let magicDNS = getLastMagicDNS() {
            info.append("MagicDNS: \(magicDNS)")
        }
        
        if let allIPs = getTailscaleIPs() {
            info.append("All IPs: \(allIPs)")
        }
        
        if !activeForwards.isEmpty {
            let forwardInfo = activeForwards.map { "Forward: \($0.remoteAddr):\($0.remotePort) -> 127.0.0.1:\($0.localPort)" }
            info.append(contentsOf: forwardInfo)
        }
        
        return info.isEmpty ? nil : info.joined(separator: "\n")
    }
    
    /// Get the primary IP address (IPv4 preferred, fallback to IPv6)
    /// - Returns: Primary IP address string, or nil if not available
    func getPrimaryIP() -> String? {
        if let ipv4 = getLastIPv4(), !ipv4.isEmpty {
            return ipv4
        } else if let ipv6 = getLastIPv6(), !ipv6.isEmpty {
            return ipv6
        }
        return nil
    }
    
    // MARK: - Private Helper Functions
    
    /// Get the persistent state directory path for Tailscale data
    /// - Returns: Path to the persistent state directory in app's Library folder
    private func getPersistentStateDirectory() -> String {
        let libraryPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first!
        let tailscaleDir = libraryPath + "/TailscaleState"
        return tailscaleDir
    }
    
    /// Ensure the state directory exists
    /// - Parameter path: Directory path to create
    /// - Returns: true if directory exists or was created successfully
    private func ensureDirectoryExists(_ path: String) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            print("[TailscaleManager] Failed to create directory at \(path): \(error)")
            return false
        }
    }
    
    /// Setup persistent state directory with proper configuration
    /// - Returns: true if setup was successful, false otherwise
    func setupPersistentStateDirectory() -> Bool {
        let stateDir = getPersistentStateDirectory()
        
        // Ensure the directory exists
        guard ensureDirectoryExists(stateDir) else {
            return false
        }
        
        // Set the state directory in Tailscale
        return setStateDirectory(stateDir)
    }
    
    /// Get the current persistent state directory path
    /// - Returns: Path to the persistent state directory
    func getStateDirectoryPath() -> String {
        return getPersistentStateDirectory()
    }
    
    /// Clear all persistent state data
    /// - Returns: true if successful, false otherwise
    func clearPersistentState() -> Bool {
        let stateDir = getPersistentStateDirectory()
        
        do {
            // Remove the entire Tailscale directory
            if FileManager.default.fileExists(atPath: stateDir) {
                try FileManager.default.removeItem(atPath: stateDir)
                print("[TailscaleManager] Persistent state directory cleared: \(stateDir)")
            }
            return true
        } catch {
            print("[TailscaleManager] Failed to clear persistent state: \(error)")
            return false
        }
    }
    
    /// Check if persistent state exists
    /// - Returns: true if state directory exists and contains data
    func hasPersistentState() -> Bool {
        let stateDir = getPersistentStateDirectory()
        return FileManager.default.fileExists(atPath: stateDir)
    }
    
    deinit {
        connectionTimer?.invalidate()
    }
} 

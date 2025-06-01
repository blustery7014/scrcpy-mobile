//
//  SettingView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/8/24.
//

import SwiftUI

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"

    var id: String { self.rawValue }
}

class AppSettings: ObservableObject {
    @AppStorage("settings.appearance")
    var apperance: Appearance = .system {
        didSet {
            print("Current apperance:", apperance)
            applyTheme()
        }
    }
    
    init() {
        applyTheme()
        
        // 监听系统外观变化通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: NSNotification.Name("UITraitCollectionDidChangeNotification"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAppearanceChange() {
        // 当系统外观变化时，如果用户设置为system模式，则应用相应主题
        if apperance == .system {
            applyTheme()
        }
    }
    
    var apperanceMode: ColorScheme {
        switch apperance {
        case .dark:
            return .dark
        case .light:
            return .light
        case .system:
            var window: UIWindow?
            
            // 先尝试iOS 14+的方式获取窗口
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                window = windowScene.windows.first
            }
            
            // 如果上面的方式不可用（iOS 13），尝试使用旧方法
            if window == nil {
                window = UIApplication.shared.windows.first
            }
            
            if let window = window {
                return window.traitCollection.userInterfaceStyle == .dark ? .dark : .light
            }
            
            return .dark // 仅作为fallback返回dark
        }
    }
    
    func applyTheme() {
        var window: UIWindow?
        
        // 先尝试iOS 14+的方式获取窗口
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window = windowScene.windows.first
        }
        
        // 如果上面的方式不可用（iOS 13），尝试使用旧方法
        if window == nil {
            window = UIApplication.shared.windows.first
        }
        
        guard let window = window else {
            return
        }

        switch apperance {
        case .system:
            window.overrideUserInterfaceStyle = .unspecified
        case .light:
            window.overrideUserInterfaceStyle = .light
        case .dark:
            window.overrideUserInterfaceStyle = .dark
        }
    }
    
    @AppStorage("settings.socks_proxy.enable")
    var enableSocksProxy: Bool = false
    
    @AppStorage("settings.socks_proxy.address")
    var socksProxyAddress: String = ""
    
    @AppStorage("settings.socks_proxy.port")
    var socksProxyPort: String = ""
    
    @AppStorage("settings.socks_proxy.auth.enable")
    var enableSocksAuth: Bool = false
    
    @AppStorage("settings.socks_proxy.auth.username")
    var socksAuthUsername: String = ""
    
    @AppStorage("settings.socks_proxy.auth.password")
    var socksAuthPassword: String = ""
    
    @AppStorage("settings.tailscale.hostname")
    var tailscaleHostname: String = "ScrcpyRemote_iOS"
    
    @AppStorage("settings.tailscale.auth_key")
    var tailscaleAuthKey: String = ""
}

struct SettingsView: View {
    @State private var showingClearLogsAlert = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("General")) {
                    NavigationLink(destination: AppearanceSettingsView()) {
                        Text("Appearance")
                    }
                    NavigationLink(destination: AboutView()) {
                        Text("About")
                    }
                }
                Section(header: Text("Networking")) {
                    // NavigationLink(destination: ProxySettingsView()) {
                    //    Text("Use Socks Proxy")
                    // }
                    NavigationLink(destination: TailscaleAuthSettingsView()) {
                        Text("Tailscale Auth Setting")
                    }
                }
                Section(header: Text("ADB Keys Managements")) {
                    NavigationLink(destination: Text("Coming Soon")) {
                        Text("Manage ADB Keys")
                    }
                }
                Section(header: Text("Scrcpy Verbose Logs")) {
                    NavigationLink(destination: DetailedLogsView()) {
                        Text("Show Logs")
                    }
                    Button(action: {
                        // Show confirm alert to clear logs
                        showingClearLogsAlert = true
                    }) {
                        Text("Clear Logs")
                            .foregroundColor(.red)
                    }
                    .alert(isPresented: $showingClearLogsAlert) {
                        Alert(
                            title: Text("Clear Logs"),
                            message: Text("Are you sure you want to clear all logs?"),
                            primaryButton: .destructive(Text("Clear")) {
                                // Add your clear logs action here
                                print("Clear logs")
                            },
                            secondaryButton: .cancel()
                        )
                    }
                }
                Section(header: Text("Please Submit Issue For Bugs or Requests")) {
                    Link("Submit an Issue", destination: URL(string: "https://github.com/wsvn53/scrcpy-mobile/issues")!)
                        .foregroundColor(.blue)
                }
            }
            .navigationBarTitle("Settings", displayMode: .inline)
        }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        List {
            ForEach(Appearance.allCases) { mode in
                Button(action: {
                    appSettings.apperance = mode
                }) {
                    HStack {
                        Text(mode.rawValue)
                        if mode == appSettings.apperance {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundColor(.primary)
            }
        }
        .navigationBarTitle("Appearance", displayMode: .inline)
    }
}

struct ProxySettingsView: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        Form {
            Toggle("Enable Proxy", isOn: $appSettings.enableSocksProxy)
            TextField("SOCKS Proxy Host", text: $appSettings.socksProxyAddress)
                .textContentType(.URL)
            TextField("SOCKS Proxy Port", text: $appSettings.socksProxyPort)
                .keyboardType(.numberPad)
            Toggle("Enable SOCKS Authentication", isOn: $appSettings.enableSocksAuth)
            if $appSettings.enableSocksAuth.wrappedValue {
                TextField("User", text: $appSettings.socksAuthUsername)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled(true)
                SecureField("Password", text: $appSettings.socksAuthPassword)
                    .textContentType(.password)
            }
        }
        .navigationBarTitle("Socks Proxy", displayMode: .inline)
    }
}

struct TailscaleAuthSettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @State private var isConnecting: Bool = false
    @State private var connectionResult: String = ""
    @State private var isConnected: Bool = false
    @State private var tailscaleIPv4: String = ""
    @State private var tailscaleIPv6: String = ""
    @State private var tailscaleMagicDNS: String = ""

    var body: some View {
        Form {
            Section(header: Text("Tailscale Configuration")) {
                TextField("Hostname", text: $appSettings.tailscaleHostname)
                    .textContentType(.name)
                    .autocapitalization(.none)
                    .autocorrectionDisabled(true)
                
                TextField("Auth Key", text: $appSettings.tailscaleAuthKey)
                    .textContentType(.password)
                    .autocapitalization(.none)
                    .autocorrectionDisabled(true)
            }
            
            Section(header: Text("How to Get Auth Key")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("To get your Tailscale Auth Key:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("1. Visit https://login.tailscale.com/admin/settings/keys")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .textSelection(.enabled)
                    
                    Text("2. Create a new Auth Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("3. Copy the key and paste it above")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Section {
                Button(action: {
                    connectAndTestTailscale()
                }) {
                    HStack {
                        if isConnecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        Text(isConnecting ? "Connecting..." : "Connect & Test Tailscale")
                    }
                }
                .disabled(isConnecting || appSettings.tailscaleAuthKey.isEmpty)
                
                if isConnected || !connectionResult.isEmpty {
                    Button(action: {
                        cleanupTailscale()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Disconnect & Cleanup")
                        }
                    }
                    .foregroundColor(.red)
                    
                    Button(action: {
                        clearPersistentState()
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Clear Persistent State")
                        }
                    }
                    .foregroundColor(.orange)
                }
            }
            
            if !connectionResult.isEmpty {
                Section(header: Text("Connection Status")) {
                    if isConnected {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Connected Successfully")
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                            
                            if !tailscaleIPv4.isEmpty || !tailscaleIPv6.isEmpty || !tailscaleMagicDNS.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Network Addresses")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text("Long press to copy")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if !tailscaleIPv4.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Tailscale IPv4:")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.secondary)
                                            Text(tailscaleIPv4)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.blue)
                                                .textSelection(.enabled)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color(.systemGray6))
                                                .cornerRadius(6)
                                        }
                                    }
                                    
                                    if !tailscaleIPv6.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Tailscale IPv6:")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.secondary)
                                            Text(tailscaleIPv6)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.blue)
                                                .textSelection(.enabled)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color(.systemGray6))
                                                .cornerRadius(6)
                                        }
                                    }
                                    
                                    if !tailscaleMagicDNS.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("MagicDNS:")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.secondary)
                                            Text(tailscaleMagicDNS)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.purple)
                                                .textSelection(.enabled)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color(.systemGray6))
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                            
                            Text(connectionResult)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("Connection Failed")
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                            }
                            
                            Text(connectionResult)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationBarTitle("Tailscale Auth", displayMode: .inline)
        .onAppear {
            checkCurrentStatus()
        }
        .onDisappear {
            // Do not cleanup on disappear
            // TailscaleManager will close connections automatically if not active
        }
    }
    
    private func checkCurrentStatus() {
        let manager = TailscaleManager.shared
        
        if manager.isConnected() {
            isConnected = true
            
            // Get current IPs and MagicDNS separately
            tailscaleIPv4 = manager.getLastIPv4() ?? ""
            tailscaleIPv6 = manager.getLastIPv6() ?? ""
            tailscaleMagicDNS = manager.getLastMagicDNS() ?? ""
            
            // Get detailed connection info
            if let info = manager.getConnectionInfo() {
                connectionResult = "Already connected to Tailscale network!\n\(info)"
            } else {
                connectionResult = "Already connected to Tailscale network!"
            }
        } else if manager.hasPersistentState() {
            // Show that persistent state exists but not currently connected
            connectionResult = "Persistent Tailscale state found at: \(manager.getStateDirectoryPath())\nTap 'Connect & Test Tailscale' to restore connection."
        }
    }
    
    private func cleanupTailscale() {
        DispatchQueue.global(qos: .userInitiated).async {
            let cleanedCount = TailscaleManager.shared.cleanup()
            
            DispatchQueue.main.async {
                self.isConnected = false
                self.connectionResult = "Cleaned up \(cleanedCount) connections. Tailscale disconnected."
                self.tailscaleIPv4 = ""
                self.tailscaleIPv6 = ""
                self.tailscaleMagicDNS = ""
            }
        }
    }
    
    private func clearPersistentState() {
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = TailscaleManager.shared
            
            // First cleanup any active connections
            let cleanedCount = manager.cleanup()
            
            // Then clear persistent state
            let success = manager.clearPersistentState()
            
            DispatchQueue.main.async {
                self.isConnected = false
                self.tailscaleIPv4 = ""
                self.tailscaleIPv6 = ""
                self.tailscaleMagicDNS = ""
                
                if success {
                    self.connectionResult = "Persistent state cleared successfully. Cleaned up \(cleanedCount) connections."
                } else {
                    self.connectionResult = "Failed to clear persistent state. Cleaned up \(cleanedCount) connections."
                }
            }
        }
    }
    
    private func connectAndTestTailscale() {
        guard !appSettings.tailscaleAuthKey.isEmpty else {
            return
        }
        
        isConnecting = true
        connectionResult = ""
        isConnected = false
        tailscaleIPv4 = ""
        tailscaleIPv6 = ""
        tailscaleMagicDNS = ""
        
        // Execute Tailscale connection in background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = TailscaleManager.shared
            
            print("[Tailscale] Starting connection test...")
            print("[Tailscale] Auth Key: \(self.appSettings.tailscaleAuthKey.prefix(10))...")
            print("[Tailscale] Hostname: \(self.appSettings.tailscaleHostname)")
            
            // Step 1: Set authentication key
            print("[Tailscale] Setting authentication key...")
            guard manager.setAuthKey(self.appSettings.tailscaleAuthKey) else {
                print("[Tailscale] ERROR: Failed to set authentication key")
                DispatchQueue.main.async {
                    self.isConnecting = false
                    self.isConnected = false
                    self.connectionResult = "Failed to set authentication key. Please check if the key format is correct."
                }
                return
            }
            print("[Tailscale] Authentication key set successfully")
            
            // Step 2: Set hostname
            print("[Tailscale] Setting hostname...")
            guard manager.setHostname(self.appSettings.tailscaleHostname) else {
                print("[Tailscale] ERROR: Failed to set hostname")
                DispatchQueue.main.async {
                    self.isConnecting = false
                    self.isConnected = false
                    self.connectionResult = "Failed to set hostname '\(self.appSettings.tailscaleHostname)'. Please check the hostname format."
                }
                return
            }
            print("[Tailscale] Hostname set successfully")
            
            // Step 3: Set state directory (use persistent directory in Library)
            print("[Tailscale] Setting up persistent state directory...")
            guard manager.setupPersistentStateDirectory() else {
                print("[Tailscale] ERROR: Failed to setup persistent state directory")
                DispatchQueue.main.async {
                    self.isConnecting = false
                    self.isConnected = false
                    self.connectionResult = "Failed to setup persistent state directory. Check app permissions."
                }
                return
            }
            print("[Tailscale] Persistent state directory set successfully: \(manager.getStateDirectoryPath())")
            
            // Step 4: Show current configuration
            let config = manager.getCurrentConfig()
            print("[Tailscale] Current config - Hostname: \(config.hostname ?? "N/A"), StateDir: \(config.stateDir ?? "N/A")")
            
            // Step 5: Start async connection
            print("[Tailscale] Starting async connection...")
            manager.connectAsync()
            
            // Step 6: Wait for connection with timeout
            let timeoutSeconds = 60
            var elapsed = 0
            
            print("[Tailscale] Waiting for connection (timeout: \(timeoutSeconds)s)...")
            
            while elapsed < timeoutSeconds {
                let status = manager.getConnectionStatus()
                
                if elapsed % 10 == 0 {
                    print("[Tailscale] Status check at \(elapsed)s: \(status)")
                }
                
                if status == 1 {
                    // Connection successful
                    print("[Tailscale] Connection successful!")
                    DispatchQueue.main.async {
                        self.isConnecting = false
                        self.isConnected = true
                        
                        // Get connection information
                        let ipv4 = manager.getLastIPv4()
                        let ipv6 = manager.getLastIPv6()
                        let hostname = manager.getLastHostname()
                        let magicDNS = manager.getLastMagicDNS()
                        
                        print("[Tailscale] Connection info - IPv4: \(ipv4 ?? "N/A"), IPv6: \(ipv6 ?? "N/A")")
                        print("[Tailscale] Hostname: \(hostname ?? "N/A"), MagicDNS: \(magicDNS ?? "N/A")")
                        
                        // Store connection information
                        self.tailscaleIPv4 = ipv4 ?? ""
                        self.tailscaleIPv6 = ipv6 ?? ""
                        self.tailscaleMagicDNS = magicDNS ?? ""
                        
                        var resultComponents: [String] = []
                        resultComponents.append("Successfully connected to Tailscale network!")
                        
                        if let hostname = hostname, !hostname.isEmpty {
                            resultComponents.append("Hostname: \(hostname)")
                        }
                        
                        if let magicDNS = magicDNS, !magicDNS.isEmpty {
                            resultComponents.append("MagicDNS: \(magicDNS)")
                        }
                        
                        if manager.isStarted() {
                            resultComponents.append("TSNet server is running")
                            print("[Tailscale] TSNet server is confirmed running")
                            
                            if let allIPs = manager.getTailscaleIPs(), !allIPs.isEmpty {
                                resultComponents.append("Available IPs: \(allIPs)")
                                print("[Tailscale] All available IPs: \(allIPs)")
                            }
                        } else {
                            print("[Tailscale] WARNING: TSNet server is not running")
                        }
                        
                        self.connectionResult = resultComponents.joined(separator: "\n")
                    }
                    return
                    
                } else if status == -1 {
                    // Connection failed
                    print("[Tailscale] Connection failed!")
                    DispatchQueue.main.async {
                        self.isConnecting = false
                        self.isConnected = false
                        
                        let errorMessage = manager.getLastError() ?? "Unknown error"
                        print("[Tailscale] Error message: \(errorMessage)")
                        self.connectionResult = "Connection failed: \(errorMessage)\n\nTroubleshooting:\n• Check if Auth Key is valid and not expired\n• Ensure network connectivity\n• Verify Tailscale account permissions"
                    }
                    return
                }
                
                // Still connecting, wait a bit more
                Thread.sleep(forTimeInterval: 1.0)
                elapsed += 1
            }
            
            // Timeout reached
            print("[Tailscale] Connection timeout after \(timeoutSeconds) seconds")
            DispatchQueue.main.async {
                self.isConnecting = false
                self.isConnected = false
                self.connectionResult = "Connection timeout after \(timeoutSeconds) seconds.\n\nPossible causes:\n• Auth Key is invalid or expired\n• Network connectivity issues\n• Tailscale service unavailable\n• Firewall blocking connection\n\nPlease check your Auth Key and network connection."
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack {
                Text("Scrcpy Remote v3.0")
                    .font(.title3)
                    .bold()
                    .padding(.bottom, 2)
                Text("Scrcpy Remote is a mobile application based on scrcpy v3.2, mainly used for connecting remote screen devices.")
                    .padding()
                Text("This application is open source software licensed under the Apache License 2.0, you view our code from:")
                    .padding()
                
                // Link Source Code
                Link("→ Scrcpy Remote Source Code", destination: URL(string: "https://github.com/wsvn53/scrcpy-mobile")!)
                
                Text("Scrcpy Remote connects through the VNC Port or ADB TCPIP Port, typically only able to connect to local network devices. The software itself does not provide any VPN or network tunneling services.")
                    .padding()
                
                Text("If you encounter problems and need help while using, you can also join our Telegram Channel.")
                    .padding()
                
                // Link Telegram Channel
                Link("→ Join Out Telegram Channel", destination: URL(string: "https://telegram.org")!)
                
                Spacer()
            }
            .padding(.top, 15)
        }
        .navigationBarTitle("About", displayMode: .inline)
    }
}

struct DetailedLogsView: View {
    @State private var logs: String = "Detailed logs will be shown here."

    var body: some View {
        VStack {
            ScrollView {
                Text(logs)
                    .padding()
            }
            .navigationBarTitle("Detailed Logs", displayMode: .inline)
            .navigationBarItems(trailing: Button(action: {
                // Add your share logs action here
            }) {
                Image(systemName: "square.and.arrow.up")
            })
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}

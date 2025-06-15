//
//  SettingView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/8/24.
//

import SwiftUI
import UniformTypeIdentifiers

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
    
    // 日志相关设置
    @AppStorage("settings.logging.enabled")
    var loggingEnabled: Bool = true {
        didSet {
            // 只有在值真正改变时才调用 AppLogManager
            if loggingEnabled != AppLogManager.shared.isLoggingEnabled {
                AppLogManager.shared.toggleLogging(loggingEnabled)
            }
        }
    }
    
    init() {
        applyTheme()
        
        // 初始化日志设置，同步状态但不触发 didSet
        let savedLoggingEnabled = UserDefaults.standard.bool(forKey: "settings.logging.enabled")
        AppLogManager.shared.isLoggingEnabled = savedLoggingEnabled
        
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
    
    @AppStorage("settings.live_activity.enabled")
    var liveActivityEnabled: Bool = true
}

struct SettingsView: View {
    @State private var showingClearAllLogsAlert = false
    @EnvironmentObject var appSettings: AppSettings
    @StateObject private var logManager = AppLogManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("General")) {
                    NavigationLink(destination: AppearanceSettingsView()) {
                        Text("Appearance")
                    }
                    
                    if #available(iOS 16.1, *) {
                        Toggle("Live Activity in Dynamic Island", isOn: $appSettings.liveActivityEnabled)
                        
                        NavigationLink(destination: LiveActivityDebugView()) {
                            HStack {
                                Text("Debug Live Activity")
                                Spacer()
                                Image(systemName: "ladybug")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    NavigationLink(destination: AboutView()) {
                        Text("About Scrcpy Remote")
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
                    NavigationLink(destination: ADBKeysManagementView()) {
                        Text("Manage ADB Keys")
                    }
                }
                Section(header: Text("Application Logs")) {
                    Toggle("Enable Log Recording", isOn: $appSettings.loggingEnabled)
                    
                    NavigationLink(destination: LogsManagementView()) {
                        HStack {
                            Text("Logs Management")
                            Spacer()
                            if logManager.logFilesCount > 0 {
                                Text("(\(logManager.logFilesCount) files)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    NavigationLink(destination: DetailedLogsView()) {
                        Text("View Current Logs")
                    }
                    
                    Button(action: {
                        showingClearAllLogsAlert = true
                    }) {
                        Text("Clear All Logs")
                            .foregroundColor(.red)
                    }
                    .alert(isPresented: $showingClearAllLogsAlert) {
                        Alert(
                            title: Text("Clear All Logs"),
                            message: Text("This will permanently delete all log files. This action cannot be undone!"),
                            primaryButton: .destructive(Text("Clear All")) {
                                logManager.clearAllLogs()
                            },
                            secondaryButton: .cancel()
                        )
                    }
                    
                    if logManager.totalLogFilesSize > 0 {
                        HStack {
                            Text("Total logs size:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: logManager.totalLogFilesSize, countStyle: .file))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Section(header: Text("Request & Support")) {
                    Link("Submit an Issue", destination: URL(string: "https://github.com/wsvn53/scrcpy-mobile/issues")!)
                        .foregroundColor(.blue)
                }
            }
            .navigationBarTitle("Settings", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .onAppear {
            // 初始化日志管理器状态
            appSettings.loggingEnabled = logManager.isLoggingEnabled
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
    @State private var appVersion: String = "Unknown"
    @State private var scrcpyVersion: String = "Unknown"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .center, spacing: 8) {
                    Text("Scrcpy Remote v\(appVersion)")
                        .font(.title3)
                        .bold()
                    Text("Based on Scrcpy \(scrcpyVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 15)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scrcpy Remote is a remote desktop tool based on VNC/ADB protocols, typically used for connecting to services with public IP addresses or services within the same local network.")
                        .font(.body)
                    
                    Text("If you cannot connect to your service normally, please first check whether the network connection is working properly.")
                        .font(.body)
                        .foregroundColor(.orange)
                    
                    Text("Additionally, this app has built-in Tailscale tsnet module, which allows you to establish a virtual network between the app and your target service through Tailscale, then connect to it.")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For detailed usage help, please check:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        // Link Tailscale README
                        Link("→ Tailscale Usage Guide", destination: URL(string: "https://github.com/wsvn53/scrcpy-mobile/blob/main/Tailscale_README.md")!)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Text("If you encounter problems and need help while using, you can also join our Telegram Channel.")
                        .font(.body)
                    
                    // Link Telegram Channel
                    Link("→ Join Our Telegram Channel", destination: URL(string: "https://telegram.org")!)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .navigationBarTitle("About Scrcpy Remote", displayMode: .inline)
        .onAppear {
            loadVersionInfo()
        }
    }
    
    private func loadVersionInfo() {
        // Get app version from bundle
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            appVersion = version
        }
        
        // Get Scrcpy core version
        let coreVersionCString = ScrcpyCoreVersion()
        if let coreVersionCString = coreVersionCString {
            scrcpyVersion = String(cString: coreVersionCString)
        }
    }
}

struct LogsManagementView: View {
    @StateObject private var logManager = AppLogManager.shared
    @State private var logFiles: [LogFileInfo] = []
    @State private var showingDeleteAlert = false
    @State private var selectedLogFile: LogFileInfo?
    @State private var showingClearOldLogsAlert = false
    
    var body: some View {
        List {
            Section(header: Text("Log Files Statistics")) {
                HStack {
                    Text("Total files:")
                    Spacer()
                    Text("\(logManager.logFilesCount)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Total size:")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: logManager.totalLogFilesSize, countStyle: .file))
                        .foregroundColor(.secondary)
                }
                
                if logManager.currentLogFileSize > 0 {
                    HStack {
                        Text("Current log size:")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: logManager.currentLogFileSize, countStyle: .file))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("Quick Actions")) {
                Button(action: {
                    showingClearOldLogsAlert = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Old Logs")
                        Spacer()
                        Text("Keep Current Only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.orange)
                .alert(isPresented: $showingClearOldLogsAlert) {
                    Alert(
                        title: Text("Clear Old Logs"),
                        message: Text("This will delete all log files except the current one. Are you sure?"),
                        primaryButton: .destructive(Text("Clear Old Logs")) {
                            logManager.clearOldLogs()
                            refreshLogFiles()
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            
            if !logFiles.isEmpty {
                Section(header: Text("Log Files")) {
                    ForEach(logFiles) { logFile in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(logFile.fileName)
                                        .font(.subheadline)
                                        .fontWeight(logFile.isCurrentLog ? .medium : .regular)
                                    
                                    Text(logFile.formattedDate)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text(logFile.formattedFileSize)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if logFile.isCurrentLog {
                                        Text("Current")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                    }
                                }
                            }
                            
                            HStack(spacing: 16) {
                                NavigationLink(destination: LogFileDetailView(logFile: logFile)) {
                                    Label("View", systemImage: "doc.text")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Spacer()
                                
                                Button(action: {
                                    selectedLogFile = logFile
                                    showingDeleteAlert = true
                                }) {
                                    Label("Delete", systemImage: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                Section {
                    VStack(alignment: .center, spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No log files found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Enable logging in settings to start recording logs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationBarTitle("Logs Management", displayMode: .inline)
        .navigationBarItems(trailing: Button("Refresh") {
            refreshLogFiles()
        })
        .onAppear {
            refreshLogFiles()
        }
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("Delete Log File"),
                message: Text("Are you sure you want to delete \(selectedLogFile?.fileName ?? "this log file")?"),
                primaryButton: .destructive(Text("Delete")) {
                    if let logFile = selectedLogFile {
                        logManager.deleteLogFile(logFile.filePath)
                        refreshLogFiles()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func refreshLogFiles() {
        logFiles = logManager.getLogFilesList()
    }
}

struct LogFileDetailView: View {
    let logFile: LogFileInfo
    @State private var logContent: String = "Loading..."
    @State private var isLoading: Bool = true
    
    var body: some View {
        VStack {
            // 文件信息
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("File:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(logFile.fileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Size:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(logFile.formattedFileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Last Modified:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(logFile.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal)
            
            // 日志内容或空状态
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Loading log content...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if isLogContentEmpty {
                // 空日志文件提示
                VStack(alignment: .center, spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("Empty Log File")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("This log file contains no content yet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        if logFile.isCurrentLog {
                            Text("Start using the app to generate logs.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // 日志内容
                ScrollView {
                    Text(logContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .padding(.horizontal)
            }
        }
        .navigationBarTitle("Log Detail", displayMode: .inline)
        .navigationBarItems(trailing: 
            Button(action: {
                refreshContent()
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)
        )
        .onAppear {
            loadLogContent()
        }
    }
    
    // 检查日志内容是否为空
    private var isLogContentEmpty: Bool {
        let trimmedContent = logContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedContent.isEmpty || 
               trimmedContent == "No log file found at: \(logFile.filePath)" ||
               trimmedContent == "Failed to read log file" ||
               trimmedContent.hasPrefix("Log file not found")
    }
    
    private func loadLogContent() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let content = AppLogManager.shared.readLogFile(logFile.filePath, lineCount: 2000)
            DispatchQueue.main.async {
                self.logContent = content
                self.isLoading = false
            }
        }
    }
    
    private func refreshContent() {
        loadLogContent()
    }
}

struct DetailedLogsView: View {
    @StateObject private var logManager = AppLogManager.shared
    @State private var logs: String = "Loading logs..."
    @State private var isLoading: Bool = true
    @State private var isAutoRefreshEnabled: Bool = false
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack {
            // 控制栏
            HStack {
                Toggle("Auto Refresh", isOn: $isAutoRefreshEnabled)
                    .onChange(of: isAutoRefreshEnabled) { enabled in
                        if enabled {
                            startAutoRefresh()
                        } else {
                            stopAutoRefresh()
                        }
                    }
                
                Spacer()
                
                Button(action: {
                    loadLogs()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                }
                .disabled(isLoading)
            }
            .padding()
            .background(Color(.systemGray6))
            
            // 日志内容
            ScrollView {
                Text(logs)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .background(Color(.systemBackground))
        }
        .navigationBarTitle("Current Logs", displayMode: .inline)
        .navigationBarItems(trailing: 
            Button(action: {
                shareContent()
            }) {
                Image(systemName: "square.and.arrow.up")
            }
        )
        .onAppear {
            loadLogs()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }
    
    private func loadLogs() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let content = logManager.readLatestLogs(lineCount: 1000)
            DispatchQueue.main.async {
                self.logs = content.isEmpty ? "No logs available.\n\nTo see logs here:\n1. Enable 'Log Recording' in Settings\n2. Use the app to generate some activity\n3. Come back to view the logs" : content
                self.isLoading = false
            }
        }
    }
    
    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            if !isLoading {
                loadLogs()
            }
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func shareContent() {
        let activityVC = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            
            // For iPad
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootVC.present(activityVC, animated: true)
        }
    }
}

struct ADBKeysManagementView: View {
    @State private var privateKey: String = ""
    @State private var publicKey: String = ""
    @State private var showPrivateKey: Bool = false
    @State private var isLoading: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false
    @State private var showingExportPicker: Bool = false
    @State private var showingGenerateAlert: Bool = false
    
    let adbClient = ADBClient.shared()
    
    var body: some View {
        Form {
            Section(header: Text("ADB Keys Directory")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ADB Home:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(adbClient.getADBHomeDirectory())
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.blue)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Private Key (adbkey)")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Content:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Button(action: {
                            showPrivateKey.toggle()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showPrivateKey ? "eye.slash" : "eye")
                                Text(showPrivateKey ? "Hide" : "Show")
                            }
                            .font(.caption)
                        }
                    }
                    
                    if showPrivateKey {
                        TextEditor(text: $privateKey)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 100)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    } else {
                        Text("••••••••••••••••••••••••••••••••")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                }
            }
            
            Section(header: Text("Public Key (adbkey.pub)")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Content:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextEditor(text: $publicKey)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 80)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
            
            Section {
                Button(action: {
                    saveKeys()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Save Keys")
                    }
                }
                .disabled(isLoading)
                
                Button(action: {
                    showingExportPicker = true
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Keys")
                    }
                }
                .disabled(isLoading || !adbClient.adbKeyPairExists())
                
                Button(action: {
                    showingGenerateAlert = true
                }) {
                    HStack {
                        Image(systemName: "key")
                        Text("Generate New Key Pair")
                    }
                }
                .disabled(isLoading)
            }
            
            if !statusMessage.isEmpty {
                Section(header: Text("Status")) {
                    HStack {
                        Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(statusIsError ? .red : .green)
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(statusIsError ? .red : .primary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationBarTitle("ADB Keys Management", displayMode: .inline)
        .onAppear {
            loadKeys()
        }
        .fileExporter(
            isPresented: $showingExportPicker,
            document: ADBKeysDocument(),
            contentType: .folder,
            defaultFilename: "ADB_Keys"
        ) { result in
            switch result {
            case .success(let url):
                exportKeys(to: url)
            case .failure(let error):
                setStatus("Export failed: \(error.localizedDescription)", isError: true)
            }
        }
        .alert("⚠️ Generate New ADB Key Pair", isPresented: $showingGenerateAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Generate New Keys", role: .destructive) {
                generateNewKeys()
            }
        } message: {
            Text("This is a destructive operation!\n\n• Your current ADB keys will be permanently deleted\n• All devices previously authorized with your current keys will lose authorization\n• You will need to re-authorize all devices manually\n• This action cannot be undone\n\nAre you sure you want to generate new ADB keys?")
        }
    }
    
    private func loadKeys() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedPrivateKey = adbClient.readADBPrivateKey() ?? ""
            let loadedPublicKey = adbClient.readADBPublicKey() ?? ""
            
            DispatchQueue.main.async {
                self.privateKey = loadedPrivateKey
                self.publicKey = loadedPublicKey
                self.isLoading = false
                
                if loadedPrivateKey.isEmpty && loadedPublicKey.isEmpty {
                    self.setStatus("No ADB keys found. You may need to generate a new key pair.", isError: false)
                } else if loadedPrivateKey.isEmpty || loadedPublicKey.isEmpty {
                    self.setStatus("Incomplete key pair found. Some keys are missing.", isError: true)
                } else {
                    self.setStatus("ADB keys loaded successfully", isError: false)
                }
            }
        }
    }
    
    private func saveKeys() {
        guard !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
              !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("Both private and public keys must be provided", isError: true)
            return
        }
        
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let privateSuccess = adbClient.writeADBPrivateKey(self.privateKey)
            let publicSuccess = adbClient.writeADBPublicKey(self.publicKey)
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if privateSuccess && publicSuccess {
                    self.setStatus("ADB keys saved successfully", isError: false)
                } else {
                    var errorMessage = "Failed to save keys:"
                    if !privateSuccess { errorMessage += " private key" }
                    if !publicSuccess { errorMessage += " public key" }
                    self.setStatus(errorMessage, isError: true)
                }
            }
        }
    }
    
    private func exportKeys(to url: URL) {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let success = adbClient.exportADBKeys(toDirectory: url.path)
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if success {
                    self.setStatus("ADB keys exported successfully to \(url.lastPathComponent)", isError: false)
                } else {
                    self.setStatus("Failed to export ADB keys", isError: true)
                }
            }
        }
    }
    
    private func generateNewKeys() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let success = adbClient.generateNewADBKeyPair()
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if success {
                    self.setStatus("New ADB key pair generated successfully", isError: false)
                    // Reload the keys after generation
                    self.loadKeys()
                } else {
                    self.setStatus("Failed to generate new ADB key pair", isError: true)
                }
            }
        }
    }
    
    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
        
        // Auto-clear status after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.statusMessage == message {
                self.statusMessage = ""
            }
        }
    }
}

// Helper document type for file export
struct ADBKeysDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    
    init() {}
    
    init(configuration: ReadConfiguration) throws {}
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(directoryWithFileWrappers: [:])
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}

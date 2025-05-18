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
                    NavigationLink(destination: ProxySettingsView()) {
                        Text("Use SOCKS Proxy")
                    }
                    NavigationLink(destination: AboutView()) {
                        Text("About")
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

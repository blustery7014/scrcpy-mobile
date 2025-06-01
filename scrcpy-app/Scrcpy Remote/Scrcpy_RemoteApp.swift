//
//  Scrcpy_RemoteApp.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/5/24.
//

import SwiftUI

@main
struct Scrcpy_RemoteApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var logManager = AppLogManager.shared
    @StateObject private var schemeManager = AppSchemeManagerV2.shared
    
    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(appSettings)
                .environmentObject(schemeManager)
                .onAppear {
                    // 确保在视图显示时应用主题
                    appSettings.applyTheme()
                    
                    // 初始化日志管理器
                    initializeLogManager()
                }
                // 注册通知中心观察者，监听前后台切换
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // 当应用变为前台激活状态时应用主题
                    appSettings.applyTheme()
                    
                    // 恢复日志记录（如果设置为启用）
                    if appSettings.loggingEnabled {
                        logManager.startLogging()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // 当应用将要进入前台时应用主题
                    appSettings.applyTheme()
                }
                // 处理 URL scheme
                .onOpenURL { url in
                    print("📱 [App] Received URL: \(url)")
                    _ = schemeManager.handleURL(url)
                }
                // 显示 scheme 连接提示
                .alert("URL Scheme Connection", 
                       isPresented: $schemeManager.shouldShowConnectionAlert) {
                    Button("OK") {
                        schemeManager.shouldShowConnectionAlert = false
                    }
                } message: {
                    Text(schemeManager.connectionMessage)
                }
        }
    }
    
    private func initializeLogManager() {
        // 同步日志管理器和设置的状态
        logManager.toggleLogging(appSettings.loggingEnabled)
    }
}

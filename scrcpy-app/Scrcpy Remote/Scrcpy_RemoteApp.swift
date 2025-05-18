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
    
    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(appSettings)
                .onAppear {
                    // 确保在视图显示时应用主题
                    appSettings.applyTheme()
                }
                // 注册通知中心观察者，监听前后台切换
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // 当应用变为前台激活状态时应用主题
                    appSettings.applyTheme()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // 当应用将要进入前台时应用主题
                    appSettings.applyTheme()
                }
        }
    }
}

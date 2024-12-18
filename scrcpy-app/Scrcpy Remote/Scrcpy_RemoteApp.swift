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
        }
    }
}

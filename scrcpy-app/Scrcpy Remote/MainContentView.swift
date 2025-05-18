//
//  ContentView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/5/24.
//

import SwiftUI

struct MainContentView: View {
    @State private var selectedTab = 0
    @State private var isSettingsPresented = false
    @State private var isSessionCreatePresented = false
    @State private var isSessionConnecting = false
    @EnvironmentObject var appSettings: AppSettings
    @State var savedSessions: [ScrcpySession]
    @State var editingSession: ScrcpySession?
    
    init() {
        savedSessions = SessionManager.shared.loadSessions().map {
            ScrcpySession(sessionModel: $0)
        }
        
        // Configure navigation bar and tab bar appearance for iOS 14+
        if #available(iOS 14.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithDefaultBackground()
            tabBarAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            UITabBar.appearance().standardAppearance = tabBarAppearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            }
        }
    }
    
    init(sessions: [ScrcpySession]) {
        savedSessions = sessions
        
        // Configure navigation bar and tab bar appearance for iOS 14+
        if #available(iOS 14.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithDefaultBackground()
            tabBarAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            UITabBar.appearance().standardAppearance = tabBarAppearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            }
        }
    }
    
    func reloadSessions() {
        savedSessions = SessionManager.shared.loadSessions().map {
            ScrcpySession(sessionModel: $0)
        }
        print("Reloaded sessions:", savedSessions.count)
    }

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                SessionsView(savedSessions: savedSessions, onDeleteSession: { id in
                    print("Deleting session:", id)
                    SessionManager.shared.deleteSession(id: id)
                    reloadSessions()
                }, onConnectSession: { session in
                    print("Connecting to session:", session.title)
                    isSessionConnecting = true
                    
                    // Connect to session
                    DispatchQueue.main.async {
                        ScrcpyClientWrapper().startClient(session.sessionModel.toDict(), completion: { statusCode, message in
                            DispatchQueue.main.async {
                                switch statusCode.rawValue {
                                case ScrcpyStatusConnected.rawValue:
                                    print("Connected to session:", session.title)
                                    isSessionConnecting = false
                                case ScrcpyStatusConnectingFailed.rawValue:
                                    print("Failed to connect to session:", session.title)
                                    isSessionConnecting = false
                                    // Show error alert
                                    let alert = UIAlertController(
                                        title: "Connection Failed",
                                        message: message.count == 0 ? "Failed to connect to device" : message,
                                        preferredStyle: .alert
                                    )
                                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let rootViewController = windowScene.windows.first?.rootViewController {
                                        rootViewController.present(alert, animated: true)
                                    }
                                default:
                                    print("Connection status:", statusCode, message)
                                }
                            }
                        })
                    }
                }, onEditSession: { session in
                    print("Editing session:", session.title)
                    editingSession = session
                })
                    .tabItem {
                        Image(systemName: "rectangle.stack")
                        Text("Sessions")
                    }
                    .tag(0)
                ActionsView()
                    .tabItem {
                        Image(systemName: "play.square.stack.fill")
                        Text("Actions")
                    }
                    .tag(1)
            }
            .navigationBarTitle(
                selectedTab == 0 ? "Scrcpy Sessions" : "Scrcpy Actions",
                displayMode: .inline
            )
            .navigationBarItems(leading: Button(action: {
                isSettingsPresented.toggle()
            }) {
                Image(systemName: "gear")
            }.disabled(isSessionConnecting), trailing: Button(action: {
                if selectedTab == 0 {
                    isSessionCreatePresented.toggle()
                }
            }) {
                Image(systemName: "plus")
            }.disabled(isSessionConnecting))
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
            }
            .sheet(isPresented: $isSessionCreatePresented, onDismiss: {
                // Reset editing session
                editingSession = nil
                
                // Reload sessions
                reloadSessions()
            }) {
                SessionCreateView()
            }
            .sheet(item: $editingSession, onDismiss: {
                // Reset editing session
                editingSession = nil
                
                // Reload sessions
                reloadSessions()
            }) { item in
                SessionCreateView(sessionModel: item.sessionModel)
            }
            .overlay {
                if isSessionConnecting {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                        .animation(.easeInOut, value: true)
                    ProgressView("Connecting..\n")
                        .multilineTextAlignment(.center)
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(width: 140, height: 140)
                        .tint(.white)
                        .background(.black.opacity(0.9))
                        .foregroundColor(.white)
                        .font(.system(size: 15, weight: .bold))
                        .cornerRadius(16)
                        .overlay {
                            Button(action: {
                                isSessionConnecting = false
                            }) {
                                Label("Cancel", systemImage: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .foregroundColor(.white)
                                    .background(.red.opacity(0.5))
                                    .cornerRadius(20)
                                    .clipped()
                            }
                            .offset(x: 0, y: 44)
                        }
                }
            }
        }
    }
}

#Preview {
    MainContentView(sessions: [
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "test.abc.com", port: "5555")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "vnc://myvnc.com", port: "5901")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "adb://test.example.com", port: "1555")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "10.1.1.1", port: "8080")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "test2.examle.com", port: "5555"))
    ])
}

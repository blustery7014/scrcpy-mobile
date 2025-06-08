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
    @State private var sessionsRefreshID = UUID() // 用于强制刷新 SessionsView 布局
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var schemeManager: AppSchemeManagerV2
    @ObservedObject private var connectionManager = SessionConnectionManager.shared
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
    
    /// 连接到指定会话
    private func connectToSession(_ session: ScrcpySession) {
        print("Connecting to session:", session.title)
        
        // 使用 SessionConnectionManager 进行连接
        SessionConnectionManager.shared.connectToSession(
            session.sessionModel,
            statusCallback: { status, message, isConnecting in
                // 状态更新由 @ObservedObject 自动处理
                switch status {
                case ScrcpyStatusSDLWindowAppeared:
                    print("✅ Connected to session:", session.title)
                    
                case ScrcpyStatusConnectingFailed:
                    print("❌ Failed to connect to session:", session.title)
                    
                default:
                    print("🔄 Connection status update:", status.description)
                    if let msg = message {
                        print("📝 Status message:", msg)
                    }
                }
            },
            errorCallback: { title, message in
                DispatchQueue.main.async {
                    // Show error alert
                    let alert = UIAlertController(
                        title: title,
                        message: message,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {
                        rootViewController.present(alert, animated: true)
                    }
                }
            }
        )
    }

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                SessionsView(savedSessions: savedSessions, onDeleteSession: { id in
                    print("Deleting session:", id)
                    SessionManager.shared.deleteSession(id: id)
                    reloadSessions()
                }, onConnectSession: { session in
                    connectToSession(session)
                }, onEditSession: { session in
                    print("Editing session:", session.title)
                    editingSession = session
                }, onDuplicateSession: { duplicatedSession in
                    print("Duplicating session:", duplicatedSession.title)
                    SessionManager.shared.saveSession(duplicatedSession.sessionModel)
                    reloadSessions()
                })
                    .id(sessionsRefreshID) // 使用 ID 强制重新创建视图
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
            }.disabled(connectionManager.isConnecting), trailing: Button(action: {
                if selectedTab == 0 {
                    isSessionCreatePresented.toggle()
                }
            }) {
                Image(systemName: "plus")
            }.disabled(connectionManager.isConnecting))
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
                    .environmentObject(appSettings)
            }
            .sheet(item: $editingSession, onDismiss: {
                // Reset editing session
                editingSession = nil
                
                // Reload sessions
                reloadSessions()
            }) { item in
                SessionCreateView(sessionModel: item.sessionModel)
                    .environmentObject(appSettings)
            }
            .overlay {
                if connectionManager.isConnecting {
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
                                // 取消连接
                                SessionConnectionManager.shared.disconnectCurrent()
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
            // 监听 session disconnect 通知
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ScrcpyStatusUpdated"))) { notification in
                guard let userInfo = notification.userInfo,
                      let statusValue = userInfo["status"] as? Int else {
                    return
                }
                
                // 检查是否为断开连接状态
                if statusValue == ScrcpyStatusDisconnected.rawValue {
                    print("🔔 [MainContentView] Received disconnect status notification - refreshing SessionsView layout")
                    
                    // 强制刷新 SessionsView 布局
                    sessionsRefreshID = UUID()
                }
            }
            // 监听 scheme 连接通知
            .onReceive(NotificationCenter.default.publisher(for: .startSchemeConnection)) { notification in
                guard let session = notification.userInfo?["session"] as? ScrcpySessionModel else {
                    print("❌ [MainContentView] No session found in scheme connection notification")
                    return
                }
                
                print("🔗 [MainContentView] Received scheme connection request for: \(session.host):\(session.port)")
                
                // 创建会话对象并连接
                let scrcpySession = ScrcpySession(sessionModel: session)
                connectToSession(scrcpySession)
                
                // 切换到会话标签页
                selectedTab = 0
            }
        }
    }
}

#Preview {
    MainContentView(sessions: [
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "test.abc.com", port: "5555", sessionName: "Test Server")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "vnc://myvnc.com", port: "5901", sessionName: "My VNC")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "adb://test.example.com", port: "1555")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "10.1.1.1", port: "8080", sessionName: "Local Device")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "test2.examle.com", port: "5555"))
    ])
}

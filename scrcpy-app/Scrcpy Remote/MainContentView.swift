//
//  ContentView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/5/24.
//

import SwiftUI

struct MainContentView: View {
    @StateObject private var connectionManager = SessionConnectionManager.shared
    
    @State private var selectedTab = 0
    @State private var isSettingsPresented = false
    @State private var isSessionCreatePresented = false
    @State private var isNewActionPresented = false
    @State private var editingSession: ScrcpySession? = nil
    @State private var savedSessions: [ScrcpySession] = []
    @State private var currentStatusMessage: String?
    @State private var isNavigationBarHidden: Bool = false
    @State private var shouldShowNavigationBarAfterDismiss: Bool = false
    @EnvironmentObject var appSettings: AppSettings
    
    init(sessions: [ScrcpySession] = []) {
        self._savedSessions = State(initialValue: sessions)
        
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
                DispatchQueue.main.async {
                    print("📝 [MainContentView] Status callback received - Status: \(status.description), Message: \(message ?? "nil"), IsConnecting: \(isConnecting)")
                    self.currentStatusMessage = message
                    if let msg = message {
                        print("📝 [MainContentView] Setting currentStatusMessage to: \(msg)")
                    } else {
                        print("📝 [MainContentView] Setting currentStatusMessage to nil")
                    }
                }
                
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
                // 错误信息现在通过 ConnectionStatusView 展示，不再显示 alert
                print("❌ [MainContentView] Connection error: \(title) - \(message)")
                // 错误信息会通过 statusCallback 传递到 ConnectionStatusView
            }
        )
    }

    // MARK: - Computed Properties
    
    /// 判断是否应该显示连接状态视图
    private var shouldShowConnectionStatusView: Bool {
        // 只有在以下情况下才显示 ConnectionStatusView：
        // 1. 正在连接中
        // 2. 连接失败（给用户时间看到错误信息）
        // 3. 有当前会话且状态不是已断开
        return connectionManager.isConnecting || 
               connectionManager.connectionStatus == ScrcpyStatusConnectingFailed ||
               (connectionManager.currentSession != nil && 
                connectionManager.connectionStatus != ScrcpyStatusDisconnected &&
                connectionManager.connectionStatus != ScrcpyStatusConnected &&
                connectionManager.connectionStatus != ScrcpyStatusSDLWindowAppeared)
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
                } else if selectedTab == 1 {
                    isNewActionPresented.toggle()
                }
            }) {
                Image(systemName: "plus")
            }.disabled(connectionManager.isConnecting))
            .navigationBarHidden(isNavigationBarHidden)
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
            .sheet(isPresented: $isNewActionPresented) {
                NewActionView { action in
                    ActionManager.shared.saveAction(action)
                }
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
                // 只有在正在连接或连接失败时才显示 ConnectionStatusView
                if shouldShowConnectionStatusView {
                    ConnectionStatusView(
                        session: ScrcpySession(sessionModel: connectionManager.currentSession ?? ScrcpySessionModel()),
                        connectionStatus: connectionManager.connectionStatus,
                        statusMessage: currentStatusMessage,
                        onCancel: {
                            // 如果当前是连接失败状态，需要显示导航条
                            if connectionManager.connectionStatus == ScrcpyStatusConnectingFailed {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isNavigationBarHidden = false
                                }
                            }
                            // 清理状态消息
                            currentStatusMessage = nil
                            SessionConnectionManager.shared.disconnectCurrent()
                        }
                    )
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeInOut(duration: 0.3), value: shouldShowConnectionStatusView)
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
            .onAppear {
                // 初始化会话列表
                if savedSessions.isEmpty {
                    reloadSessions()
                }
            }
            .onChange(of: connectionManager.isConnecting) { isConnecting in
                // 根据连接状态更新导航条显示
                // 只有在不是连接失败状态时才自动显示导航条
                if !isConnecting && connectionManager.connectionStatus != ScrcpyStatusConnectingFailed {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isNavigationBarHidden = false
                    }
                } else if isConnecting {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isNavigationBarHidden = true
                    }
                }
                
                // 只有在非连接失败状态下才自动清理状态消息
                if !isConnecting && connectionManager.connectionStatus != ScrcpyStatusConnectingFailed {
                    print("🧹 [MainContentView] Auto-clearing currentStatusMessage (not in failure state)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        currentStatusMessage = nil
                        print("🧹 [MainContentView] currentStatusMessage cleared")
                    }
                } else if !isConnecting && connectionManager.connectionStatus == ScrcpyStatusConnectingFailed {
                    print("⚠️ [MainContentView] Not auto-clearing currentStatusMessage (in failure state)")
                }
            }
            .onChange(of: connectionManager.connectionStatus) { newStatus in
                // 监听连接状态变化
                print("🔄 [MainContentView] Connection status changed to: \(newStatus.description)")
                print("🔄 [MainContentView] Current currentStatusMessage: \(currentStatusMessage ?? "nil")")
                
                switch newStatus {
                case ScrcpyStatusSDLWindowAppeared, ScrcpyStatusConnected:
                    print("✅ [MainContentView] Connection successful, preparing to hide status view")
                    // 连接成功时，延迟清理状态消息
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        currentStatusMessage = nil
                        print("🧹 [MainContentView] currentStatusMessage cleared after success")
                    }
                    
                case ScrcpyStatusConnectingFailed:
                    print("❌ [MainContentView] Connection failed, will show error briefly")
                    print("❌ [MainContentView] Current currentStatusMessage: \(currentStatusMessage ?? "nil")")
                    // 连接失败时，保持导航条隐藏，等用户点击取消后才显示
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isNavigationBarHidden = true
                    }
                    // 延长状态消息显示时间，让用户有足够时间看到错误信息
                    // 只有在用户主动取消或状态发生变化时才清理
                    // 不在这里自动清理 currentStatusMessage
                    
                case ScrcpyStatusDisconnected:
                    print("🔌 [MainContentView] Connection disconnected, cleaning up")
                    currentStatusMessage = nil
                    print("🧹 [MainContentView] currentStatusMessage cleared after disconnect")
                    
                default:
                    break
                }
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

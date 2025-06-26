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
        if #available(iOS 16.0, *) {
            NavigationStack {
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
                .navigationTitle(
                    selectedTab == 0 ? "Scrcpy Sessions" : "Scrcpy Actions"
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            isSettingsPresented.toggle()
                        }) {
                            Image(systemName: "gear")
                        }
                        .disabled(connectionManager.isConnecting)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            if selectedTab == 0 {
                                isSessionCreatePresented.toggle()
                            } else if selectedTab == 1 {
                                isNewActionPresented.toggle()
                            }
                        }) {
                            Image(systemName: "plus")
                        }
                        .disabled(connectionManager.isConnecting)
                    }
                }
                .navigationBarHidden(isNavigationBarHidden)
                .sheet(isPresented: $isSettingsPresented) {
                    SettingsView()
                        .environmentObject(appSettings)
                }
                .sheet(isPresented: $isSessionCreatePresented, onDismiss: {
                    editingSession = nil
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
                    editingSession = nil
                    reloadSessions()
                }) { item in
                    SessionCreateView(sessionModel: item.sessionModel)
                        .environmentObject(appSettings)
                }
                .overlay {
                    if shouldShowConnectionStatusView {
                        ConnectionStatusView(
                            session: ScrcpySession(sessionModel: connectionManager.currentSession ?? ScrcpySessionModel()),
                            connectionStatus: connectionManager.connectionStatus,
                            statusMessage: currentStatusMessage,
                            onCancel: {
                                print("🚫 [MainContentView] User cancelled connection, restoring navigation bar")
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isNavigationBarHidden = false
                                }
                                currentStatusMessage = nil
                                SessionConnectionManager.shared.disconnectCurrent()
                            }
                        )
                        .transition(.opacity.combined(with: .scale))
                        .animation(.easeInOut(duration: 0.3), value: shouldShowConnectionStatusView)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .startSchemeConnection)) { notification in
                    guard let session = notification.userInfo?["session"] as? ScrcpySessionModel else {
                        print("❌ [MainContentView] No session found in scheme connection notification")
                        return
                    }
                    
                    print("🔗 [MainContentView] Received scheme connection request for: \(session.host):\(session.port)")
                    
                    let scrcpySession = ScrcpySession(sessionModel: session)
                    connectToSession(scrcpySession)
                    
                    selectedTab = 0
                }
                .onAppear {
                    if savedSessions.isEmpty {
                        reloadSessions()
                    }
                }
                .onChange(of: connectionManager.isConnecting) { isConnecting in
                    if isConnecting {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isNavigationBarHidden = true
                        }
                    }
                    
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
                    print("🔄 [MainContentView] Connection status changed to: \(newStatus.description)")
                    print("🔄 [MainContentView] Current currentStatusMessage: \(currentStatusMessage ?? "nil")")
                    
                    switch newStatus {
                    case ScrcpyStatusSDLWindowAppeared:
                        print("✅ [MainContentView] SDL Window appeared, restoring navigation bar and hiding status view")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isNavigationBarHidden = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            currentStatusMessage = nil
                            print("🧹 [MainContentView] currentStatusMessage cleared after SDL window appeared")
                        }
                        
                    case ScrcpyStatusConnected:
                        print("✅ [MainContentView] Connection successful, preparing to hide status view")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            currentStatusMessage = nil
                            print("🧹 [MainContentView] currentStatusMessage cleared after connection success")
                        }
                        
                    case ScrcpyStatusConnectingFailed:
                        print("❌ [MainContentView] Connection failed, will show error briefly")
                        print("❌ [MainContentView] Current currentStatusMessage: \(currentStatusMessage ?? "nil")")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isNavigationBarHidden = true
                        }
                        
                    case ScrcpyStatusDisconnected:
                        print("🔌 [MainContentView] Connection disconnected, restoring navigation bar and cleaning up")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isNavigationBarHidden = false
                        }
                        currentStatusMessage = nil
                        print("🧹 [MainContentView] currentStatusMessage cleared after disconnect")
                        
                    default:
                        break
                    }
                }
            }
        } else {
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
                            if #available(iOS 15.0, *) {
                                Image(systemName: "play.rectangle.on.rectangle.fill")
                            } else {
                                Image(systemName: "play.rectangle.on.rectangle")
                            }
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
                        .environmentObject(appSettings)
                }
                .sheet(isPresented: $isSessionCreatePresented, onDismiss: {
                    editingSession = nil
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
                    editingSession = nil
                    reloadSessions()
                }) { item in
                    SessionCreateView(sessionModel: item.sessionModel)
                        .environmentObject(appSettings)
                }
                .overlay {
                    if shouldShowConnectionStatusView {
                        ConnectionStatusView(
                            session: ScrcpySession(sessionModel: connectionManager.currentSession ?? ScrcpySessionModel()),
                            connectionStatus: connectionManager.connectionStatus,
                            statusMessage: currentStatusMessage,
                            onCancel: {
                                print("🚫 [MainContentView] User cancelled connection, restoring navigation bar")
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isNavigationBarHidden = false
                                }
                                currentStatusMessage = nil
                                SessionConnectionManager.shared.disconnectCurrent()
                            }
                        )
                        .transition(.opacity.combined(with: .scale))
                        .animation(.easeInOut(duration: 0.3), value: shouldShowConnectionStatusView)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .startSchemeConnection)) { notification in
                    guard let session = notification.userInfo?["session"] as? ScrcpySessionModel else {
                        print("❌ [MainContentView] No session found in scheme connection notification")
                        return
                    }
                    
                    print("🔗 [MainContentView] Received scheme connection request for: \(session.host):\(session.port)")
                    
                    let scrcpySession = ScrcpySession(sessionModel: session)
                    connectToSession(scrcpySession)
                    
                    selectedTab = 0
                }
                .onAppear {
                    if savedSessions.isEmpty {
                        reloadSessions()
                    }
                }
                .onChange(of: connectionManager.isConnecting) { isConnecting in
                    if isConnecting {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isNavigationBarHidden = true
                        }
                    }
                    
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
                    print("🔄 [MainContentView] Connection status changed to: \(newStatus.description)")
                    print("🔄 [MainContentView] Current currentStatusMessage: \(currentStatusMessage ?? "nil")")
                    
                    switch newStatus {
                    case ScrcpyStatusSDLWindowAppeared:
                        print("✅ [MainContentView] SDL Window appeared, restoring navigation bar and hiding status view")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isNavigationBarHidden = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            currentStatusMessage = nil
                            print("🧹 [MainContentView] currentStatusMessage cleared after SDL window appeared")
                        }
                        
                    case ScrcpyStatusConnected:
                        print("✅ [MainContentView] Connection successful, preparing to hide status view")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            currentStatusMessage = nil
                            print("🧹 [MainContentView] currentStatusMessage cleared after connection success")
                        }
                        
                    case ScrcpyStatusConnectingFailed:
                        print("❌ [MainContentView] Connection failed, will show error briefly")
                        print("❌ [MainContentView] Current currentStatusMessage: \(currentStatusMessage ?? "nil")")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isNavigationBarHidden = true
                        }
                        
                    case ScrcpyStatusDisconnected:
                        print("🔌 [MainContentView] Connection disconnected, restoring navigation bar and cleaning up")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isNavigationBarHidden = false
                        }
                        currentStatusMessage = nil
                        print("🧹 [MainContentView] currentStatusMessage cleared after disconnect")
                        
                    default:
                        break
                    }
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
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

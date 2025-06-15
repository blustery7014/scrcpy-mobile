//
//  SessionConnectionManager.swift
//  Scrcpy Remote
//
//  Created by Ethan on 1/1/25.
//
//  断开连接处理逻辑：
//  - 所有断开连接都静默处理，不显示给用户
//  - 只记录日志用于调试
//

import Foundation
import UIKit
import ActivityKit

// MARK: - Connection Callback Types

/// 连接状态回调闭包类型
/// - Parameters:
///   - status: 连接状态
///   - message: 状态消息
///   - isConnecting: 是否正在连接中
typealias ConnectionStatusCallback = (ScrcpyStatus, String?, Bool) -> Void

/// 连接错误回调闭包类型
/// - Parameters:
///   - title: 错误标题
///   - message: 错误消息
typealias ConnectionErrorCallback = (String, String) -> Void

/// 管理当前连接会话的状态
@objc class SessionConnectionManager: NSObject, ObservableObject {
    @objc static let shared = SessionConnectionManager()
    
    // MARK: - Connection State
    
    /// 当前连接的会话信息
    @Published var currentSession: ScrcpySessionModel?
    
    /// 当前连接状态
    @Published var connectionStatus: ScrcpyStatus = ScrcpyStatusDisconnected
    
    /// 实际连接的主机地址（解析后的，可能通过 Tailscale 代理）
    @Published var actualHost: String?
    
    /// 实际连接的端口（解析后的，可能通过 Tailscale 代理）
    @Published var actualPort: String?
    
    /// 是否使用 Tailscale 连接
    @Published var isUsingTailscale: Bool = false
    
    /// Tailscale 本地转发端口（如果使用）
    @Published var tailscaleLocalPort: Int?
    
    /// 是否正在连接中
    @Published var isConnecting: Bool = false
    
    /// 当前连接的开始时间
    @Published var connectionStartTime: Date?
    
    // MARK: - Private Properties
    
    /// 当前连接的回调闭包
    private var currentConnectionCallback: ConnectionStatusCallback?
    
    /// 当前错误回调闭包
    private var currentErrorCallback: ConnectionErrorCallback?
    
    /// Scrcpy 客户端包装器实例，用于直接管理连接
    private var scrcpyClientWrapper: ScrcpyClientWrapper?
    
    /// Live Activity 管理器
    private lazy var liveActivityManager: Any? = {
        if #available(iOS 16.1, *) {
            return ScrcpyLiveActivityManager.shared
        } else {
            return nil
        }
    }()
    
    override private init() {
        super.init()
        setupNotificationObservers()
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // 监听 scrcpy 状态更新
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrcpyStatusUpdate(_:)),
            name: Notification.Name("ScrcpyStatusUpdated"),
            object: nil
        )
        
        // 监听应用进入后台
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // 监听应用变为活跃
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func handleScrcpyStatusUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let statusValue = userInfo["status"] as? Int else {
            print("⚠️ [SessionConnectionManager] Invalid notification: \(notification)")
            return
        }
        
        let statusMessage = userInfo["message"] as? String
        print("🔔 [SessionConnectionManager] Received status update: \(statusValue) from notification")
        
        DispatchQueue.main.async {
            let newStatus = ScrcpyStatus(UInt32(statusValue))
            self.connectionStatus = newStatus
            
            switch newStatus {
            case ScrcpyStatusConnecting:
                print("🔄 [SessionConnectionManager] Status: Connecting")
                self.isConnecting = true
                
            case ScrcpyStatusSDLWindowAppeared:
                print("✅ [SessionConnectionManager] Status: Connected")
                self.isConnecting = false
                
                // 记录连接开始时间
                if self.connectionStartTime == nil {
                    self.connectionStartTime = Date()
                    print("⏰ [SessionConnectionManager] Connection start time recorded: \(self.connectionStartTime!)")
                }
                
            case ScrcpyStatusDisconnected:
                print("❌ [SessionConnectionManager] Status: Disconnected - clearing session")
                if let disconnectMessage = statusMessage, !disconnectMessage.isEmpty {
                    print("ℹ️ [SessionConnectionManager] Disconnect message: \(disconnectMessage)")
                }
                self.isConnecting = false
                self.clearCurrentSession()
                
            case ScrcpyStatusConnectingFailed:
                print("❌ [SessionConnectionManager] Status: Connection Failed")
                self.isConnecting = false
                
                // 如果有错误消息且存在错误回调，显示错误信息
                if let errorMessage = statusMessage, !errorMessage.isEmpty,
                   let errorCallback = self.currentErrorCallback {
                    print("📝 [SessionConnectionManager] Showing error message: \(errorMessage)")
                    errorCallback("Connection Failed", errorMessage)
                } else if let errorCallback = self.currentErrorCallback {
                    // 使用默认错误消息
                    errorCallback("Connection Failed", "Failed to connect to device. Please check your network connection and device settings.")
                }
                
            default:
                print("🔄 [SessionConnectionManager] Status update: \(statusValue)")
            }
            
            // 调用状态回调
            if let callback = self.currentConnectionCallback {
                callback(newStatus, statusMessage, self.isConnecting)
            }
            
            // 更新 Live Activity
            self.updateLiveActivityIfNeeded(status: newStatus, message: statusMessage)
        }
    }
    
    @objc private func handleApplicationDidEnterBackground() {
        print("📱 [SessionConnectionManager] Application did enter background")
        
        // 如果当前有活跃连接，启动 Live Activity
        startLiveActivityIfNeeded()
    }
    
    @objc private func handleApplicationDidBecomeActive() {
        print("📱 [SessionConnectionManager] Application did become active")
        // 可以在这里添加前台恢复逻辑
    }
    
    // MARK: - Connection Management
    
    /// 连接到指定会话
    /// - Parameters:
    ///   - session: 要连接的会话模型
    ///   - statusCallback: 连接状态回调
    ///   - errorCallback: 错误回调
    func connectToSession(
        _ session: ScrcpySessionModel,
        statusCallback: @escaping ConnectionStatusCallback,
        errorCallback: @escaping ConnectionErrorCallback
    ) {
        print("🚀 [SessionConnectionManager] Starting connection to session: \(session.sessionName)")
        
        // 保存回调闭包
        currentConnectionCallback = statusCallback
        currentErrorCallback = errorCallback
        
        // 如果当前状态不是 Disconnected，先断开现有连接
        if connectionStatus != ScrcpyStatusDisconnected {
            print("🔄 [SessionConnectionManager] Current status is \(connectionStatus.description), disconnecting first")
            disconnectCurrent()
            
            // 等待断开完成后再开始新连接
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.performConnection(to: session, statusCallback: statusCallback, errorCallback: errorCallback)
            }
        } else {
            // 直接开始连接
            performConnection(to: session, statusCallback: statusCallback, errorCallback: errorCallback)
        }
    }
    
    /// 执行实际的连接逻辑
    /// - Parameters:
    ///   - session: 要连接的会话模型
    ///   - statusCallback: 连接状态回调
    ///   - errorCallback: 错误回调
    private func performConnection(
        to session: ScrcpySessionModel,
        statusCallback: @escaping ConnectionStatusCallback,
        errorCallback: @escaping ConnectionErrorCallback
    ) {
        print("🔗 [SessionConnectionManager] Performing connection to session: \(session.sessionName)")
        
        // 更新连接状态
        isConnecting = true
        statusCallback(ScrcpyStatusConnecting, "Preparing connection...", true)
        
        // 异步获取连接信息并连接
        Task {
            do {
                // 获取连接信息
                guard let connectionInfo = await SessionNetworking.shared.getConnectionInfo(for: session) else {
                    await MainActor.run {
                        self.handleConnectionError(
                            title: "Connection Setup Failed",
                            message: "Failed to setup connection. Please check your network configuration and try again.",
                            errorCallback: errorCallback
                        )
                    }
                    return
                }
                
                print("📍 [SessionConnectionManager] Connection info obtained: \(connectionInfo.description)")
                
                await MainActor.run {
                    // 设置当前会话
                    self.setCurrentSession(session, connectionInfo: connectionInfo)
                    
                    // 准备会话字典
                    var sessionDict = session.toDict()
                    sessionDict["hostReal"] = connectionInfo.host
                    sessionDict["port"] = connectionInfo.port
                    
                    // 更新主机信息
                    if connectionInfo.isUsingTailscale {
                        print("🔗 [SessionConnectionManager] Using Tailscale connection: \(connectionInfo.originalHost):\(connectionInfo.originalPort) -> \(connectionInfo.host):\(connectionInfo.port)")
                    } else {
                        sessionDict["host"] = connectionInfo.host
                        print("🔌 [SessionConnectionManager] Using direct connection: \(connectionInfo.host):\(connectionInfo.port)")
                    }
                    
                    // 开始连接
                    self.startScrcpyConnection(sessionDict: sessionDict, connectionInfo: connectionInfo)
                }
                
            } catch {
                await MainActor.run {
                    self.handleConnectionError(
                        title: "Connection Error",
                        message: "Failed to establish connection: \(error.localizedDescription)",
                        errorCallback: errorCallback
                    )
                }
            }
        }
    }
    
    /// 开始 Scrcpy 连接
    /// - Parameters:
    ///   - sessionDict: 会话字典
    ///   - connectionInfo: 连接信息
    private func startScrcpyConnection(sessionDict: [String: Any], connectionInfo: NetworkConnectionInfo) {
        print("🔗 [SessionConnectionManager] Starting Scrcpy client connection")
        
        // 创建或获取 ScrcpyClientWrapper 实例
        if scrcpyClientWrapper == nil {
            scrcpyClientWrapper = ScrcpyClientWrapper()
        }
        
        scrcpyClientWrapper?.startClient(sessionDict) { [weak self] statusCode, message in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch statusCode.rawValue {
                case ScrcpyStatusSDLWindowAppeared.rawValue:
                    print("✅ [SessionConnectionManager] Successfully connected to session")
                    // 状态更新会通过通知处理
                    
                case ScrcpyStatusConnectingFailed.rawValue:
                    print("❌ [SessionConnectionManager] Failed to connect to session")
                    
                    // 停止端口转发（如果使用 Tailscale）
                    if connectionInfo.isUsingTailscale,
                       let sessionId = self.currentSession?.id {
                        _ = SessionNetworking.shared.stopForwarding(for: sessionId)
                    }
                    
                    // 注意：错误消息现在主要通过状态更新通知处理
                    // 这里的备用处理已被注释，避免重复显示错误信息
                    // 状态更新通知会自动处理 ScrcpyStatusConnectingFailed 的错误显示
                    /*
                    if let errorCallback = self.currentErrorCallback {
                        let errorMessage = message.isEmpty == false ? message : "Failed to connect to device. Please check your connection and try again."
                        print("📝 [SessionConnectionManager] Backup error handling: \(errorMessage)")
                        errorCallback("Connection Failed", errorMessage)
                    }
                    */
                    
                default:
                    print("🔄 [SessionConnectionManager] Connection status: \(statusCode.description)")
                    if !message.isEmpty {
                        print("📝 [SessionConnectionManager] Status message: \(message)")
                    }
                    // 其他状态更新会通过通知处理
                }
            }
        }
    }
    
    /// 处理连接错误
    /// - Parameters:
    ///   - title: 错误标题
    ///   - message: 错误消息
    ///   - errorCallback: 错误回调
    private func handleConnectionError(title: String, message: String, errorCallback: ConnectionErrorCallback) {
        print("❌ [SessionConnectionManager] Connection error: \(title) - \(message)")
        
        isConnecting = false
        connectionStatus = ScrcpyStatusConnectingFailed
        
        errorCallback(title, message)
    }
    
    /// 设置当前连接的会话
    /// - Parameters:
    ///   - session: 会话模型
    ///   - connectionInfo: 连接信息（包含实际的 host 和 port）
    func setCurrentSession(_ session: ScrcpySessionModel, connectionInfo: NetworkConnectionInfo?) {
        currentSession = session
        
        if let info = connectionInfo {
            actualHost = info.host
            actualPort = info.port
            isUsingTailscale = info.isUsingTailscale
            tailscaleLocalPort = info.localForwardPort
        } else {
            actualHost = session.hostReal
            actualPort = session.port
            isUsingTailscale = false
            tailscaleLocalPort = nil
        }
        
        connectionStatus = ScrcpyStatusConnecting
        
        print("📱 [SessionConnectionManager] Current session set: \(session.sessionName)")
        print("📍 [SessionConnectionManager] Connection: \(actualHost ?? "unknown"):\(actualPort ?? "unknown")")
        if isUsingTailscale {
            print("🔗 [SessionConnectionManager] Using Tailscale (local port: \(tailscaleLocalPort ?? 0))")
        }
    }
    
    /// 清除当前会话信息
    func clearCurrentSession() {
        let wasConnected = currentSession != nil
        let previousHost = actualHost
        let previousPort = actualPort
        
        currentSession = nil
        actualHost = nil
        actualPort = nil
        isUsingTailscale = false
        tailscaleLocalPort = nil
        connectionStatus = ScrcpyStatusDisconnected
        isConnecting = false
        connectionStartTime = nil
        
        // 清理 ScrcpyClientWrapper 实例
        scrcpyClientWrapper = nil
        
        // 停止 Live Activity
        if #available(iOS 16.1, *),
           let manager = liveActivityManager as? ScrcpyLiveActivityManager {
            manager.stopActivity()
        }
        
        // 保留状态回调，立即清除
        currentConnectionCallback = nil
        
        // 延迟清除错误回调，确保用户能看到可能的错误消息
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.currentErrorCallback = nil
        }
        
        if wasConnected {
            print("🧹 [SessionConnectionManager] Session cleared - was connected to \(previousHost ?? "unknown"):\(previousPort ?? "unknown")")
            print("⏰ [SessionConnectionManager] Connection time cleared")
        } else {
            print("🧹 [SessionConnectionManager] Session cleared - no previous connection")
        }
    }
    
    /// 检查是否需要重连到新会话
    /// - Parameters:
    ///   - newSession: 新的会话
    ///   - newConnectionInfo: 新会话的连接信息
    /// - Returns: 是否需要重连
    func shouldReconnect(to newSession: ScrcpySessionModel, with newConnectionInfo: NetworkConnectionInfo?) -> Bool {
        // 如果当前没有活跃连接，直接连接
        guard connectionStatus != ScrcpyStatusDisconnected else {
            print("🆕 [SessionConnectionManager] No active connection, will connect")
            return true
        }
        
        // 获取新会话的实际连接地址
        let newHost = newConnectionInfo?.host ?? newSession.hostReal
        let newPort = newConnectionInfo?.port ?? newSession.port
        
        // 检查连接地址是否相同
        if actualHost == newHost && actualPort == newPort {
            print("🔄 [SessionConnectionManager] Same connection (\(newHost):\(newPort)), no reconnection needed")
            return false
        }
        
        // 检查会话类型是否相同
        if let currentSession = currentSession {
            if currentSession.deviceType != newSession.deviceType {
                print("🔀 [SessionConnectionManager] Different device type (\(currentSession.deviceType.rawValue) → \(newSession.deviceType.rawValue)), will reconnect")
                return true
            }
        }
        
        print("🔀 [SessionConnectionManager] Different connection (\(actualHost ?? "unknown"):\(actualPort ?? "unknown") → \(newHost):\(newPort)), will reconnect")
        return true
    }
    
    /// 断开当前连接
    func disconnectCurrent() {
        guard connectionStatus != ScrcpyStatusDisconnected else {
            print("🚫 [SessionConnectionManager] Already disconnected, no action needed")
            return
        }
        
        print("🔌 [SessionConnectionManager] Disconnecting current connection")
        
        // 使用 ScrcpyClientWrapper 的 disconnect 方法
        if let wrapper = scrcpyClientWrapper {
            wrapper.disconnectCurrentClient()
        } else {
            // 备用方案：发送断开通知
            NotificationCenter.default.post(
                name: Notification.Name("ScrcpyRequestDisconnectNotification"),
                object: nil
            )
        }
        
        // 清理端口转发
        if isUsingTailscale {
            SessionNetworking.shared.stopAllForwarding()
        }
        
        // 更新状态
        connectionStatus = ScrcpyStatusDisconnected
        isConnecting = false
        connectionStartTime = nil
    }
    
    // MARK: - Utility Methods
    
    /// 获取当前连接的描述信息
    var connectionDescription: String {
        guard let session = currentSession else {
            return "No active connection"
        }
        
        let deviceType = session.deviceType.rawValue.uppercased()
        let sessionName = session.sessionName.isEmpty ? "\(session.hostReal):\(session.port)" : session.sessionName
        let connectionInfo = "\(actualHost ?? "unknown"):\(actualPort ?? "unknown")"
        
        var description = "[\(deviceType)] \(sessionName)"
        
        if isUsingTailscale {
            description += " via Tailscale (\(connectionInfo))"
        } else if actualHost != session.hostReal || actualPort != session.port {
            description += " → \(connectionInfo)"
        }
        
        return description
    }
    
    /// 获取连接状态的描述
    var statusDescription: String {
        return connectionStatus.description
    }
    
    /// 获取当前连接的持续时间（秒）
    var connectionDuration: TimeInterval {
        guard let startTime = connectionStartTime else {
            return 0
        }
        return Date().timeIntervalSince(startTime)
    }
    
    /// 获取格式化的连接持续时间字符串
    var formattedConnectionDuration: String {
        let duration = connectionDuration
        let minutes = Int(duration / 60)
        
        if minutes < 1 {
            return "< 1m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Debug Methods
    
    /// 测试通知系统是否正常工作
    func testNotificationSystem() {
        print("🧪 [SessionConnectionManager] Testing notification system...")
        
        // 发送一个测试通知
        NotificationCenter.default.post(
            name: Notification.Name("ScrcpyStatusUpdated"),
            object: nil,
            userInfo: ["status": 0] // ScrcpyStatusDisconnected
        )
        
        print("🧪 [SessionConnectionManager] Test notification sent")
    }
    
    // MARK: - Live Activity Integration
    
    /// 如果需要，启动 Live Activity
    private func startLiveActivityIfNeeded() {
        guard #available(iOS 16.1, *) else { return }
        
        // 检查用户是否启用了 Live Activity
        let liveActivityEnabled = UserDefaults.standard.object(forKey: "settings.live_activity.enabled") as? Bool ?? true
        guard liveActivityEnabled else {
            print("ℹ️ [SessionConnectionManager] Live Activity disabled by user")
            return
        }
        
        guard let session = currentSession,
              connectionStatus.isActive else {
            print("ℹ️ [SessionConnectionManager] Live Activity not needed")
            return
        }
        
        guard let manager = liveActivityManager as? ScrcpyLiveActivityManager else {
            print("ℹ️ [SessionConnectionManager] Live Activity manager not available")
            return
        }
        
        guard !manager.hasActiveActivity else {
            print("ℹ️ [SessionConnectionManager] Live Activity already active")
            return
        }
        
        print("🎭 [SessionConnectionManager] Starting Live Activity for background session")
        
        let sessionName = session.sessionName.isEmpty ? "\(session.hostReal):\(session.port)" : session.sessionName
        let deviceType = session.deviceType.rawValue
        let host = actualHost ?? session.hostReal
        let port = actualPort ?? session.port
        
        // 如果已经连接，使用实际的连接开始时间
        let actualStartTime = connectionStartTime ?? Date()
        
        manager.startActivity(
            sessionName: sessionName,
            deviceType: deviceType,
            hostAddress: host,
            port: port,
            initialStatus: connectionStatus,
            isUsingTailscale: isUsingTailscale,
            connectionStartTime: actualStartTime
        )
    }
    
    /// 如果需要，更新 Live Activity
    private func updateLiveActivityIfNeeded(status: ScrcpyStatus, message: String?) {
        guard #available(iOS 16.1, *) else { return }
        
        guard let manager = liveActivityManager as? ScrcpyLiveActivityManager else {
            return
        }
        
        guard manager.hasActiveActivity else {
            print("ℹ️ [SessionConnectionManager] No active Live Activity to update")
            return
        }
        
        let actualDuration = connectionDuration
        print("🔄 [SessionConnectionManager] Updating Live Activity with status: \(status.description), duration: \(actualDuration)s")
        manager.updateActivity(status: status, statusMessage: message, connectionDuration: actualDuration)
    }
    
    /// 检查 Live Activity 是否可用
    @available(iOS 16.1, *)
    var isLiveActivityAvailable: Bool {
        if let manager = liveActivityManager as? ScrcpyLiveActivityManager {
            return manager.isActivityAvailable
        }
        return false
    }
    
    /// 手动启动 Live Activity（用于测试或用户主动启动）
    @available(iOS 16.1, *)
    func startLiveActivity() {
        startLiveActivityIfNeeded()
    }
    
    /// 手动停止 Live Activity
    @available(iOS 16.1, *)
    func stopLiveActivity() {
        if let manager = liveActivityManager as? ScrcpyLiveActivityManager {
            manager.stopActivity()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Objective-C Bridge Methods
    
    /// 获取当前连接的设备类型，供Objective-C代码调用
    /// - Returns: 设备类型字符串，"adb"或"vnc"，如果没有连接则返回nil
    @objc public func getCurrentDeviceType() -> String? {
        return currentSession?.deviceType.rawValue
    }
    
    /// 检查是否有当前活跃的连接，供Objective-C代码调用
    /// - Returns: 是否有活跃连接
    @objc public func hasActiveConnection() -> Bool {
        return currentSession != nil && connectionStatus.isActive
    }
} 

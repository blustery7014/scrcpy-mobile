//
//  SessionConnectionManager.swift
//  Scrcpy Remote
//
//  Created by Ethan on 1/1/25.
//

import Foundation
import UIKit

/// 管理当前连接会话的状态
class SessionConnectionManager: ObservableObject {
    static let shared = SessionConnectionManager()
    
    // MARK: - Connection State
    
    /// 当前连接状态
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case failed(Error?)
        
        var isActive: Bool {
            switch self {
            case .connecting, .connected:
                return true
            case .disconnected, .failed:
                return false
            }
        }
    }
    
    /// 当前连接的会话信息
    @Published var currentSession: ScrcpySessionModel?
    
    /// 当前连接状态
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
    /// 实际连接的主机地址（解析后的，可能通过 Tailscale 代理）
    @Published var actualHost: String?
    
    /// 实际连接的端口（解析后的，可能通过 Tailscale 代理）
    @Published var actualPort: String?
    
    /// 是否使用 Tailscale 连接
    @Published var isUsingTailscale: Bool = false
    
    /// Tailscale 本地转发端口（如果使用）
    @Published var tailscaleLocalPort: Int?
    
    private init() {
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
    }
    
    @objc private func handleScrcpyStatusUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let statusValue = userInfo["status"] as? Int else {
            print("⚠️ [SessionConnectionManager] Invalid notification: \(notification)")
            return
        }
        
        print("🔔 [SessionConnectionManager] Received status update: \(statusValue) from notification")
        
        DispatchQueue.main.async {
            switch statusValue {
            case 2: // ScrcpyStatusConnecting
                self.connectionStatus = .connecting
                print("🔄 [SessionConnectionManager] Status: Connecting")
                
            case 5: // ScrcpyStatusSDLWindowAppeared
                self.connectionStatus = .connected
                print("✅ [SessionConnectionManager] Status: Connected")
                
            case 0: // ScrcpyStatusDisconnected
                self.connectionStatus = .disconnected
                print("❌ [SessionConnectionManager] Status: Disconnected - clearing session")
                self.clearCurrentSession()
                
            case 1: // ScrcpyStatusConnectingFailed
                self.connectionStatus = .failed(nil)
                print("❌ [SessionConnectionManager] Status: Connection Failed")
                
            default:
                print("🔄 [SessionConnectionManager] Status update: \(statusValue)")
            }
        }
    }
    
    // MARK: - Connection Management
    
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
        
        connectionStatus = .connecting
        
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
        connectionStatus = .disconnected
        
        if wasConnected {
            print("🧹 [SessionConnectionManager] Session cleared - was connected to \(previousHost ?? "unknown"):\(previousPort ?? "unknown")")
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
        guard connectionStatus.isActive else {
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
        guard connectionStatus.isActive else {
            print("🚫 [SessionConnectionManager] No active connection to disconnect")
            return
        }
        
        print("🔌 [SessionConnectionManager] Disconnecting current connection")
        
        // 发送断开通知
        NotificationCenter.default.post(
            name: Notification.Name("ScrcpyRequestDisconnectNotification"),
            object: nil
        )
        
        // 清理端口转发
        if isUsingTailscale {
            SessionNetworking.shared.stopAllForwarding()
        }
        
        // 更新状态
        connectionStatus = .disconnected
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
        switch connectionStatus {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .failed(let error):
            return "Failed" + (error != nil ? ": \(error!.localizedDescription)" : "")
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
} 
import Foundation
import ActivityKit
import SwiftUI

// MARK: - Live Activity Attributes
@available(iOS 16.1, *)
public struct ScrcpyLiveActivityAttributes: ActivityAttributes {
    public typealias ScrcpyLiveActivityStatus = ContentState
    
    public struct ContentState: Codable, Hashable {
        // Session 基本信息
        public var sessionName: String
        public var deviceType: String
        public var hostAddress: String
        public var port: String
        
        // 连接状态信息
        public var connectionStatus: String
        public var connectionStatusCode: Int
        public var isConnected: Bool
        public var startTime: Date
        public var isUsingTailscale: Bool
        
        // 动态更新的信息
        public var lastUpdateTime: Date
        
        public init(
            sessionName: String,
            deviceType: String,
            hostAddress: String,
            port: String,
            connectionStatus: String,
            connectionStatusCode: Int,
            isConnected: Bool,
            startTime: Date = Date(),
            isUsingTailscale: Bool = false
        ) {
            self.sessionName = sessionName
            self.deviceType = deviceType
            self.hostAddress = hostAddress
            self.port = port
            self.connectionStatus = connectionStatus
            self.connectionStatusCode = connectionStatusCode
            self.isConnected = isConnected
            self.startTime = startTime
            self.isUsingTailscale = isUsingTailscale
            self.lastUpdateTime = Date()
        }
        
        // 计算连接时长
        public var connectionDuration: TimeInterval {
            Date().timeIntervalSince(startTime)
        }
        
        // 格式化连接时长 (仅显示分钟数)
        public var formattedDuration: String {
            let duration = connectionDuration
            let minutes = Int(duration) / 60
            
            if minutes > 0 {
                return String(format: "%dm", minutes)
            } else {
                return "< 1m"
            }
        }
        
        // 获取状态颜色
        public var statusColor: Color {
            // 当状态码大于等于 Window Created 状态时，都显示绿色
            if connectionStatusCode >= 3 { // sdlWindowCreated = 3, connected = 6, sdlWindowAppeared = 7
                return .green
            } else if connectionStatus == "Connecting" || connectionStatus.contains("Connecting") {
                return .orange
            } else if connectionStatus.contains("Failed") || connectionStatus.contains("Error") {
                return .red
            } else {
                return .gray
            }
        }
        
        // 获取状态图标
        public var statusIcon: String {
            // 当状态码大于等于 Window Created 状态时，都显示成功图标
            if connectionStatusCode >= 3 { // sdlWindowCreated = 3, connected = 6, sdlWindowAppeared = 7
                return "checkmark.circle.fill"
            } else if connectionStatus == "Connecting" || connectionStatus.contains("Connecting") {
                return "arrow.clockwise.circle.fill"
            } else if connectionStatus.contains("Failed") || connectionStatus.contains("Error") {
                return "xmark.circle.fill"
            } else {
                return "circle"
            }
        }
        
        // 获取显示状态文案
        public var displayStatus: String {
            // 当状态码大于等于 Window Created 状态时，都显示"已连接"
            if connectionStatusCode >= 3 { // sdlWindowCreated = 3, connected = 6, sdlWindowAppeared = 7
                return "已连接"
            } else {
                return connectionStatus
            }
        }
    }
    
    // 静态属性，不会更改
    public var activityId: String
    
    public init(activityId: String) {
        self.activityId = activityId
    }
} 
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
        public var isUsingTailscale: Bool
        public var startTime: Date
        
        // 动态更新的信息
        public var lastUpdateTime: Date
        /// 已连接分钟（文本，向上取整，至少 1m），由主应用计算后写入
        public var elapsedMinutesText: String
        
        public init(
            sessionName: String,
            deviceType: String,
            hostAddress: String,
            port: String,
            connectionStatus: String,
            connectionStatusCode: Int,
            isConnected: Bool,
            startTime: Date = Date(),
            isUsingTailscale: Bool = false,
            elapsedMinutesText: String? = nil
        ) {
            self.sessionName = sessionName
            self.deviceType = deviceType
            self.hostAddress = hostAddress
            self.port = port
            self.connectionStatus = connectionStatus
            self.connectionStatusCode = connectionStatusCode
            self.isConnected = isConnected
            self.isUsingTailscale = isUsingTailscale
            self.startTime = startTime
            self.lastUpdateTime = Date()
            // 分钟文本（由主应用计算后写入；若未提供则按 startTime 计算）
            if let elapsedMinutesText {
                self.elapsedMinutesText = elapsedMinutesText
            } else {
                let seconds = max(0, Date().timeIntervalSince(startTime))
                let minutes = max(1, Int(ceil(seconds / 60.0)))
                self.elapsedMinutesText = "\(minutes)m"
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

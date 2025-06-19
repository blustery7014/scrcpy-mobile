//
//  ScrcpyStatus+Extensions.swift
//  Scrcpy Remote
//
//  Created by Ethan on 1/1/25.
//

import Foundation

// MARK: - ScrcpyStatus Extensions
extension ScrcpyStatus {
    
    /// 检查连接状态是否为活跃状态
    /// 活跃状态包括：正在连接、已连接、以及其他非断开状态
    var isActive: Bool {
        switch self {
        case ScrcpyStatusDisconnected:
            return false
        case ScrcpyStatusConnectingFailed:
            return false
        default:
            return true
        }
    }
    
    /// 检查连接状态是否为完全连接状态
    var isFullyConnected: Bool {
        switch self {
        case ScrcpyStatusSDLWindowCreated:
            return true
        case ScrcpyStatusSDLWindowAppeared:
            return true
        case ScrcpyStatusConnected:
            return true
        default:
            return false
        }
    }
    
    /// 检查连接状态是否正在连接中
    var isConnecting: Bool {
        switch self {
        case ScrcpyStatusConnecting:
            return true
        case ScrcpyStatusADBConnected:
            return true
        case ScrcpyStatusSDLWindowCreated:
            return true
        default:
            return false
        }
    }
    
    /// 获取状态的描述文本
    var description: String {
        switch self {
        case ScrcpyStatusDisconnected:
            return "Disconnected"
        case ScrcpyStatusConnecting:
            return "Connecting"
        case ScrcpyStatusADBConnected:
            return "ADB Connected"
        case ScrcpyStatusConnected:
            return "Connected"
        case ScrcpyStatusSDLWindowCreated:
            return "Window Created"
        case ScrcpyStatusSDLWindowAppeared:
            return "Connected"
        case ScrcpyStatusConnectingFailed:
            return "Connection Failed"
        default:
            return "Unknown (\(self.rawValue))"
        }
    }
} 
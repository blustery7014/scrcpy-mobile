import Foundation

// MARK: - Scrcpy Status Enum
// This enum defines the connection status for Scrcpy sessions

@objc public enum ScrcpyStatus: UInt32, CaseIterable {
    case disconnected = 0
    case adbConnected = 1
    case sdlInited = 2
    case sdlWindowCreated = 3
    case connecting = 4
    case connectingFailed = 5
    case connected = 6
    case sdlWindowAppeared = 7
    
    /// Human-readable description of the status
    public var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .adbConnected:
            return "ADB Connected"
        case .sdlInited:
            return "Initializing"
        case .sdlWindowCreated:
            return "Window Created"
        case .connecting:
            return "Connecting"
        case .connectingFailed:
            return "Connection Failed"
        case .connected:
            return "Connected"
        case .sdlWindowAppeared:
            return "Connected"
        }
    }
    
    /// Whether the status indicates an active connection
    public var isActive: Bool {
        switch self {
        case .adbConnected, .sdlInited, .sdlWindowCreated, .connecting, .connected, .sdlWindowAppeared:
            return true
        case .disconnected, .connectingFailed:
            return false
        }
    }
    
    /// Whether the status indicates a fully established connection
    public var isFullyConnected: Bool {
        switch self {
        case .connected, .sdlWindowAppeared:
            return true
        case .disconnected, .adbConnected, .sdlInited, .sdlWindowCreated, .connecting, .connectingFailed:
            return false
        }
    }
    
    /// Whether the status indicates a failed state
    public var isFailed: Bool {
        switch self {
        case .connectingFailed:
            return true
        case .disconnected, .adbConnected, .sdlInited, .sdlWindowCreated, .connecting, .connected, .sdlWindowAppeared:
            return false
        }
    }
}

// MARK: - Legacy Support
// These constants maintain compatibility with existing Objective-C code
// Values based on the original enum in ../porting/libs/include/scrcpy-porting.h

public let ScrcpyStatusDisconnected: UInt32 = 0
public let ScrcpyStatusADBConnected: UInt32 = 1
public let ScrcpyStatusSDLInited: UInt32 = 2
public let ScrcpyStatusSDLWindowCreated: UInt32 = 3
public let ScrcpyStatusConnecting: UInt32 = 4
public let ScrcpyStatusConnectingFailed: UInt32 = 5
public let ScrcpyStatusConnected: UInt32 = 6
public let ScrcpyStatusSDLWindowAppeared: UInt32 = 7 
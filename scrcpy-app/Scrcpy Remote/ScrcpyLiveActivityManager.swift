import Foundation
import ActivityKit
import WidgetKit
import SwiftUI
import os.log

/// Scrcpy Live Activity 管理器
/// 负责管理连接状态的 Live Activity 显示
@available(iOS 16.1, *)
class ScrcpyLiveActivityManager: ObservableObject {
    static let shared = ScrcpyLiveActivityManager()
    
    // MARK: - Properties
    
    /// 当前活跃的 Live Activity
    private var currentActivity: Activity<ScrcpyLiveActivityAttributes>?
    
    /// 连接开始时间
    private var connectionStartTime: Date?
    
    /// 定时器用于更新连接时长
    private var updateTimer: Timer?
    
    /// 日志系统
    private let logger = Logger(subsystem: "com.mobile.scrcpy-ios", category: "LiveActivity")
    
    private init() {
        logger.info("🎭 [ScrcpyLiveActivityManager] Initialized")
    }
    
    // MARK: - Public Methods
    
    /// 检查 Live Activity 是否可用
    var isActivityAvailable: Bool {
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    
    /// 开始 Live Activity
    /// - Parameters:
    ///   - sessionName: 会话名称
    ///   - deviceType: 设备类型
    ///   - hostAddress: 主机地址
    ///   - port: 端口
    ///   - initialStatus: 初始连接状态
    ///   - isUsingTailscale: 是否使用 Tailscale
    ///   - connectionStartTime: 连接开始时间（可选，默认为当前时间）
    func startActivity(
        sessionName: String,
        deviceType: String,
        hostAddress: String,
        port: String,
        initialStatus: ScrcpyStatus = ScrcpyStatus.init(rawValue: 0),
        isUsingTailscale: Bool = false,
        connectionStartTime: Date? = nil
    ) {
        logger.info("🚀 [ScrcpyLiveActivityManager] Starting Live Activity for session: \(sessionName)")
        
        // 如果已有活动，先停止
        stopActivity()
        
        // 检查权限
        guard isActivityAvailable else {
            logger.warning("⚠️ [ScrcpyLiveActivityManager] Live Activities not available or not authorized")
            return
        }
        
        // 使用传入的连接开始时间或当前时间
        self.connectionStartTime = connectionStartTime ?? Date()
        
        logger.debug("⏰ [ScrcpyLiveActivityManager] Connection start time: \(self.connectionStartTime!)")
        
        // 创建初始状态
        let initialContentState = ScrcpyLiveActivityAttributes.ContentState(
            sessionName: sessionName,
            deviceType: deviceType,
            hostAddress: hostAddress,
            port: port,
            connectionStatus: initialStatus.description,
            connectionStatusCode: Int(initialStatus.rawValue),
            isConnected: initialStatus.rawValue >= 3, // sdlWindowCreated = 3, connected = 6, sdlWindowAppeared = 7
            startTime: self.connectionStartTime!,
            isUsingTailscale: isUsingTailscale
        )
        
        // 创建 Activity 属性
        let activityAttributes = ScrcpyLiveActivityAttributes(
            activityId: "scrcpy-connection-\(UUID().uuidString)"
        )
        
        // 启动 Live Activity
        do {
            let activity = try Activity<ScrcpyLiveActivityAttributes>.request(
                attributes: activityAttributes,
                contentState: initialContentState,
                pushType: nil
            )
            
            currentActivity = activity
            
            logger.info("✅ [ScrcpyLiveActivityManager] Live Activity started successfully")
            
            // 开始定时更新
            startUpdateTimer()
            
        } catch {
            logger.error("❌ [ScrcpyLiveActivityManager] Failed to start Live Activity: \(error.localizedDescription)")
        }
    }
    
    /// 更新 Live Activity 状态
    /// - Parameters:
    ///   - status: Scrcpy 连接状态
    ///   - statusMessage: 状态消息
    ///   - connectionDuration: 实际连接持续时间（秒）
    func updateActivity(status: ScrcpyStatus, statusMessage: String? = nil, connectionDuration: TimeInterval? = nil) {
        guard let activity = currentActivity else {
            logger.warning("⚠️ [ScrcpyLiveActivityManager] No active Live Activity to update")
            return
        }
        
        logger.info("🔄 [ScrcpyLiveActivityManager] Updating Live Activity with status: \(status.description)")
        
        // 获取当前状态
        let currentState = activity.contentState
        
        // 计算使用的开始时间
        let actualStartTime: Date
        if let duration = connectionDuration, duration > 0 {
            // 使用传入的持续时间计算开始时间
            actualStartTime = Date().addingTimeInterval(-duration)
            logger.debug("⏰ [ScrcpyLiveActivityManager] Using actual connection duration: \(duration)s")
        } else {
            // 使用原始开始时间
            actualStartTime = currentState.startTime
        }
        
        // 创建新状态
        let newContentState = ScrcpyLiveActivityAttributes.ContentState(
            sessionName: currentState.sessionName,
            deviceType: currentState.deviceType,
            hostAddress: currentState.hostAddress,
            port: currentState.port,
            connectionStatus: statusMessage ?? status.description,
            connectionStatusCode: Int(status.rawValue),
            isConnected: status.rawValue >= 3, // sdlWindowCreated = 3, connected = 6, sdlWindowAppeared = 7
            startTime: actualStartTime,
            isUsingTailscale: currentState.isUsingTailscale
        )
        
        // 更新 Activity
        Task {
            do {
                await activity.update(using: newContentState)
                logger.info("✅ [ScrcpyLiveActivityManager] Live Activity updated successfully")
            } catch {
                logger.error("❌ [ScrcpyLiveActivityManager] Failed to update Live Activity: \(error.localizedDescription)")
            }
        }
        
        // 如果连接失败或断开，停止定时器
        if !status.isActive {
            stopUpdateTimer()
            
            // 延迟停止 Activity，让用户看到最终状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.stopActivity()
            }
        }
    }
    
    /// 停止 Live Activity
    func stopActivity() {
        guard let activity = currentActivity else {
            logger.info("ℹ️ [ScrcpyLiveActivityManager] No active Live Activity to stop")
            return
        }
        
        logger.info("🛑 [ScrcpyLiveActivityManager] Stopping Live Activity")
        
        // 停止定时器
        stopUpdateTimer()
        
        // 结束 Activity
        Task {
            await activity.end(dismissalPolicy: .immediate)
            logger.info("✅ [ScrcpyLiveActivityManager] Live Activity stopped successfully")
        }
        
        // 清空当前活动
        currentActivity = nil
        connectionStartTime = nil
    }
    
    /// 强制停止所有 Live Activities
    func stopAllActivities() {
        logger.info("🧹 [ScrcpyLiveActivityManager] Stopping all Live Activities")
        
        // 停止当前管理的活动
        stopActivity()
        
        // 停止所有系统中的相关活动
        Task {
            for activity in Activity<ScrcpyLiveActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
                logger.info("🗑️ [ScrcpyLiveActivityManager] Ended activity: \(activity.id)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// 开始定时更新
    private func startUpdateTimer() {
        stopUpdateTimer()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.updateCurrentActivity()
        }
        
        logger.debug("⏰ [ScrcpyLiveActivityManager] Update timer started")
    }
    
    /// 停止定时更新
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
        logger.debug("⏰ [ScrcpyLiveActivityManager] Update timer stopped")
    }
    
    /// 更新当前活动（主要用于更新时长）
    private func updateCurrentActivity() {
        guard let activity = currentActivity,
              activity.contentState.connectionStatusCode >= 3 else { // sdlWindowCreated = 3, connected = 6, sdlWindowAppeared = 7
            return
        }
        
        // 获取实际连接时间
        guard let sessionManager = getSessionManager() else {
            return
        }
        
        let actualDuration = sessionManager.connectionDuration
        guard actualDuration > 0 else {
            return
        }
        
        logger.debug("⏰ [ScrcpyLiveActivityManager] Updating with actual duration: \(actualDuration)s")
        
        // 创建更新的状态（使用实际连接时间）
        let currentState = activity.contentState
        let actualStartTime = Date().addingTimeInterval(-actualDuration)
        
        let updatedState = ScrcpyLiveActivityAttributes.ContentState(
            sessionName: currentState.sessionName,
            deviceType: currentState.deviceType,
            hostAddress: currentState.hostAddress,
            port: currentState.port,
            connectionStatus: currentState.connectionStatus,
            connectionStatusCode: currentState.connectionStatusCode,
            isConnected: currentState.isConnected,
            startTime: actualStartTime,
            isUsingTailscale: currentState.isUsingTailscale
        )
        
        Task {
            do {
                await activity.update(using: updatedState)
            } catch {
                logger.error("❌ [ScrcpyLiveActivityManager] Failed to update activity timer: \(error.localizedDescription)")
            }
        }
    }
    
    /// 获取 SessionConnectionManager 实例
    private func getSessionManager() -> SessionConnectionManager? {
        return SessionConnectionManager.shared
    }
    
    // MARK: - Utility Methods
    
    /// 获取当前活动状态
    var currentActivityState: ScrcpyLiveActivityAttributes.ContentState? {
        return currentActivity?.contentState
    }
    
    /// 检查是否有活跃的 Live Activity
    var hasActiveActivity: Bool {
        return currentActivity != nil
    }
    
    /// 获取连接时长描述 (仅显示分钟数)
    var connectionDurationDescription: String? {
        guard let startTime = connectionStartTime else { return nil }
        
        let duration = Date().timeIntervalSince(startTime)
        let minutes = Int(duration) / 60
        
        if minutes > 0 {
            return String(format: "%dm", minutes)
        } else {
            return "< 1m"
        }
    }
    
    deinit {
        stopUpdateTimer()
        logger.info("🔄 [ScrcpyLiveActivityManager] Deinitialized")
    }
} 

//
//  ConnectionStatusView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 1/1/25.
//

import SwiftUI

struct ConnectionStatusView: View {
    let session: ScrcpySession
    let connectionStatus: ScrcpyStatus
    let statusMessage: String?
    let onCancel: () -> Void
    
    @State private var animationPhase: Int = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var glowOpacity: Double = 0.5
    @State private var breathingScale: CGFloat = 1.0
    
    // 使用 State 来控制 Timer 的生命周期
    @State private var isTimerActive: Bool = true
    
    // 添加状态跟踪，用于检测状态变化
    @State private var previousConnectionStatus: ScrcpyStatus?
    
    // 新增：动画重置控制
    @State private var animationResetTrigger: Bool = false
    @State private var currentIconName: String = ""
    @State private var currentIconColor: Color = .gray
    
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // 背景渐变
            backgroundGradient
            
            // 主要内容
            VStack(spacing: 10) {
                Spacer()

                // 顶部设备信息
                deviceInfoSection
                
                Spacer()
                
                // 连接状态动画区域
                connectionAnimationSection
                
                // 连接过程状态
                connectionProgressSection
                
                Spacer()
                Spacer()

                // 取消按钮
                cancelButton
                
                Spacer()
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 50)
        }
        .ignoresSafeArea()
        .onReceive(timer) { _ in
            // 只有在 Timer 激活且视图仍然需要时才更新动画
            if isTimerActive && shouldContinueAnimating {
                updateAnimations()
            }
        }
        .onAppear {
            // 视图出现时激活 Timer
            isTimerActive = true
            // 初始化动画状态
            resetAnimationState()
            previousConnectionStatus = connectionStatus
            currentIconName = connectionStatusIcon
            currentIconColor = connectionStatusColor
            print("🎭 [ConnectionStatusView] View appeared for session: \(session.title)")
        }
        .onDisappear {
            // 视图消失时停止 Timer 和动画
            isTimerActive = false
            print("🎭 [ConnectionStatusView] View disappeared for session: \(session.title)")
        }
        .onChange(of: connectionStatus) { newStatus in
            // 检测状态变化并重置动画
            if let previousStatus = previousConnectionStatus, previousStatus != newStatus {
                print("🔄 [ConnectionStatusView] Status changed from \(previousStatus.description) to \(newStatus.description)")
                
                // 状态变化时重置动画状态
                resetAnimationState()
                
                // 更新当前图标信息
                currentIconName = connectionStatusIcon
                currentIconColor = connectionStatusColor
                
                // 触发动画重置
                animationResetTrigger.toggle()
                
                // 短暂延迟后重新开始动画（如果需要）
                if shouldContinueAnimating {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTimerActive = true
                    }
                }
            }
            
            // 更新前一个状态
            previousConnectionStatus = newStatus
            
            // 当连接成功时，准备停止动画
            if newStatus.isFullyConnected {
                print("✅ [ConnectionStatusView] Connection successful, preparing to stop animations")
                // 延迟停止 Timer，给用户一个短暂的视觉反馈
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTimerActive = false
                    print("⏹️ [ConnectionStatusView] Stopped animations after successful connection")
                }
            } else if newStatus == ScrcpyStatusConnectingFailed {
                // 连接失败时，保持动画一段时间让用户看到错误信息
                print("❌ [ConnectionStatusView] Connection failed, keeping animations for error visibility")
                // 延迟停止动画，给用户时间看到错误信息
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isTimerActive = false
                    print("⏹️ [ConnectionStatusView] Stopped animations after connection failure")
                }
            }
        }
    }
    
    // MARK: - Animation Reset Function
    private func resetAnimationState() {
        withAnimation(.easeInOut(duration: 0.2)) {
            pulseScale = 1.0
            breathingScale = 1.0
            rotationAngle = 0
            glowOpacity = 0.5
        }
        animationPhase = 0
        print("🔄 [ConnectionStatusView] Animation state reset")
    }
    
    // MARK: - Computed Properties
    
    /// 判断是否应该继续运行动画
    private var shouldContinueAnimating: Bool {
        // 只有在连接中或连接失败时才继续动画
        // 连接失败时也继续动画，给用户时间看到错误信息
        return connectionStatus.isConnecting
    }
    
    // MARK: - Background Gradient
    private var backgroundGradient: some View {
        ZStack {
            // 主背景渐变
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // 简化的动态光效 - 只在动画激活时显示
            if isTimerActive && shouldContinueAnimating {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.05),
                        Color.clear
                    ]),
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 300
                )
                .scaleEffect(pulseScale)
                .opacity(glowOpacity)
                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: pulseScale)
            }
        }
    }
    
    // MARK: - Device Info Section
    private var deviceInfoSection: some View {
        VStack(spacing: 15) {
            // 设备图标
            deviceTypeIcon
            
            // 设备名称
            Text(session.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Device Type Icon
    private var deviceTypeIcon: some View {
        let iconName: String
        let iconColor: Color
        
        switch session.deviceType {
        case "adb":
            iconName = "android-large"
            iconColor = .green
        case "vnc":
            iconName = "vnc-large"
            iconColor = .blue
        default:
            iconName = "questionmark.circle"
            iconColor = .gray
        }
        
        return Image(iconName)
            .resizable()
            .scaledToFit()
            .frame(width: 40, height: 40)
            .foregroundColor(.white)
            .colorMultiply(.white)
            .background(
                Circle()
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 60, height: 60)
            )
            .overlay(
                Circle()
                    .stroke(iconColor.opacity(0.4), lineWidth: 1)
                    .frame(width: 60, height: 60)
            )
    }
    
    // MARK: - Connection Animation Section
    private var connectionAnimationSection: some View {
        VStack(spacing: 10) {
            // 主连接动画 - 固定高度区域
            ZStack {
                // 简化的脉冲环 - 只在动画激活时显示
                if isTimerActive && shouldContinueAnimating {
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 4)
                        .frame(width: 80, height: 80)
                        .scaleEffect(pulseScale)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulseScale)
                }
                
                // 中心连接图标 - 使用独立的状态变量避免动画冲突
                Image(systemName: currentIconName)
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(currentIconColor)
                    .scaleEffect(breathingScale)
                    .rotationEffect(.degrees(rotationAngle))
                    .animation(
                        isTimerActive && shouldContinueAnimating && connectionStatus.isConnecting ? 
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : 
                        .easeInOut(duration: 0.3),
                        value: breathingScale
                    )
                    .animation(
                        isTimerActive && shouldContinueAnimating ? 
                        .linear(duration: 3).repeatForever(autoreverses: false) : 
                        .easeInOut(duration: 0.3),
                        value: rotationAngle
                    )
                    // 使用 animationResetTrigger 来强制重新创建视图，清除之前的动画
                    .id("\(currentIconName)_\(animationResetTrigger)")
            }
            .frame(height: 80) // 固定动画区域高度
        }
    }
    
    // MARK: - Connection Progress Section
    private var connectionProgressSection: some View {
        VStack(spacing: 10) {
            // 当前状态消息 - 固定高度区域
            if let message = statusMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .frame(minHeight: 60) // 设置最小高度
                    .frame(maxWidth: .infinity) // 确保宽度一致
                    .onAppear {
                        print("🔍 [ConnectionStatusView] Displaying specific status message: \(message)")
                    }
            } else if connectionStatus == ScrcpyStatusConnectingFailed {
                // 连接失败时，即使没有具体错误消息，也显示连接失败的提示
                Text("Connection failed. Please check your network settings and try again.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .frame(minHeight: 60) // 设置最小高度
                    .frame(maxWidth: .infinity) // 确保宽度一致
                    .onAppear {
                        print("🔍 [ConnectionStatusView] Displaying fallback error message (statusMessage is nil or empty)")
                    }
            } else {
                // 其他状态的默认状态消息 - 固定高度区域
                Text(defaultStatusMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .frame(minHeight: 60) // 设置最小高度
                    .frame(maxWidth: .infinity) // 确保宽度一致
                    .onAppear {
                        print("🔍 [ConnectionStatusView] Displaying default status message: \(defaultStatusMessage)")
                    }
            }
        }
    }
    
    // MARK: - Cancel Button
    private var cancelButton: some View {
        Button(action: onCancel) {
            HStack(spacing: 8) {
                Image(systemName: connectionStatus == ScrcpyStatusConnectingFailed ? "xmark.circle" : "xmark.circle.fill")
                    .font(.system(size: 16))
                Text(connectionStatus == ScrcpyStatusConnectingFailed ? "Dismiss" : "Cancel Connection")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.red.opacity(0.3))
            .cornerRadius(25)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Computed Properties
    private var connectionStatusIcon: String {
        switch connectionStatus {
        case ScrcpyStatusConnecting, ScrcpyStatusADBConnected:
            return "inset.filled.circle"
        case ScrcpyStatusConnected, ScrcpyStatusSDLWindowCreated, ScrcpyStatusSDLWindowAppeared:
            return "checkmark.circle.fill"
        case ScrcpyStatusConnectingFailed:
            return "xmark.circle.fill"
        default:
            return "wifi"
        }
    }
    
    private var connectionStatusColor: Color {
        switch connectionStatus {
        case ScrcpyStatusConnecting, ScrcpyStatusADBConnected:
            return .blue
        case ScrcpyStatusConnected, ScrcpyStatusSDLWindowCreated, ScrcpyStatusSDLWindowAppeared:
            return .green
        case ScrcpyStatusConnectingFailed:
            return .red
        default:
            return .gray
        }
    }
    
    private var connectionStatusText: String {
        switch connectionStatus {
        case ScrcpyStatusConnecting:
            return "Initializing Connection"
        case ScrcpyStatusADBConnected:
            return "ADB Connected"
        case ScrcpyStatusSDLWindowCreated:
            return "Creating Display Window"
        case ScrcpyStatusConnected, ScrcpyStatusSDLWindowAppeared:
            return "Connected Successfully"
        case ScrcpyStatusConnectingFailed:
            return "Connection Failed"
        default:
            return "Preparing Connection"
        }
    }
    
    private var defaultStatusMessage: String {
        switch connectionStatus {
        case ScrcpyStatusConnecting:
            return "Establishing network connection to \(session.sessionModel.hostReal):\(session.sessionModel.port)"
        case ScrcpyStatusADBConnected:
            return "ADB protocol connection established successfully"
        case ScrcpyStatusSDLWindowCreated:
            return "Creating display window for remote screen"
        case ScrcpyStatusConnected, ScrcpyStatusSDLWindowAppeared:
            return "Connection established successfully"
        case ScrcpyStatusConnectingFailed:
            return "Failed to establish connection"
        default:
            return "Preparing connection..."
        }
    }
    
    // MARK: - Connection Steps
    private var connectionSteps: [ConnectionStep] {
        [
            ConnectionStep(title: "Network", icon: "wifi", status: .network),
            ConnectionStep(title: "ADB/VNC", icon: session.deviceType == "adb" ? "android" : "display", status: .protocolConnection),
            ConnectionStep(title: "Display", icon: "rectangle", status: .display)
        ]
    }
    
    // MARK: - Animation Updates
    private func updateAnimations() {
        // 只有在 Timer 激活且需要继续动画时才更新
        guard isTimerActive && shouldContinueAnimating else { 
            // 如果不需要动画，确保状态重置
            if !shouldContinueAnimating {
                resetAnimationState()
            }
            return 
        }
        
        animationPhase = (animationPhase + 1) % 100
        
        // 更新脉冲动画
        if animationPhase % 25 == 0 {
            withAnimation(.easeInOut(duration: 2)) {
                pulseScale = pulseScale == 1.0 ? 1.1 : 1.0
            }
        }
        
        // 更新呼吸灯动画 - 只在连接中状态时执行
        if connectionStatus.isConnecting && animationPhase % 15 == 0 {
            withAnimation(.easeInOut(duration: 1.5)) {
                breathingScale = breathingScale == 1.0 ? 1.2 : 1.0
            }
        }
        
        // 更新旋转动画 - 只在连接中状态时执行
        if connectionStatus.isConnecting {
            rotationAngle += 0.2
        }
    }
}

// MARK: - Connection Step Model
struct ConnectionStep {
    let title: String
    let icon: String
    let status: ConnectionStepStatus
    
    func isActive(for scrcpyStatus: ScrcpyStatus) -> Bool {
        switch status {
        case .network:
            return scrcpyStatus == ScrcpyStatusConnecting
        case .protocolConnection:
            return scrcpyStatus == ScrcpyStatusADBConnected
        case .display:
            return scrcpyStatus == ScrcpyStatusSDLWindowCreated
        }
    }
    
    func isCompleted(for scrcpyStatus: ScrcpyStatus) -> Bool {
        switch status {
        case .network:
            return scrcpyStatus.rawValue > ScrcpyStatusConnecting.rawValue
        case .protocolConnection:
            return scrcpyStatus.rawValue > ScrcpyStatusADBConnected.rawValue
        case .display:
            return scrcpyStatus == ScrcpyStatusConnected || scrcpyStatus == ScrcpyStatusSDLWindowAppeared
        }
    }
}

enum ConnectionStepStatus {
    case network
    case protocolConnection
    case display
}

// MARK: - Preview
struct ConnectionStatusView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionStatusView(
            session: ScrcpySession(sessionModel: ScrcpySessionModel(host: "test.example.com", port: "5555", sessionName: "Test Device")),
            connectionStatus: ScrcpyStatusConnecting,
            statusMessage: "Establishing network connection...",
            onCancel: {}
        )
    }
} 

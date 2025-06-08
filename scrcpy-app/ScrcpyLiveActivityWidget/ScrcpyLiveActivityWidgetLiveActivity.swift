//
//  ScrcpyLiveActivityWidgetLiveActivity.swift
//  ScrcpyLiveActivityWidget
//
//  Created by Ethan on 6/8/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.1, *)
struct ScrcpyLiveActivityWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScrcpyLiveActivityAttributes.self) { context in
            // 锁屏显示内容
            ScrcpyLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color.clear)
                .activitySystemActionForegroundColor(Color.black)
        } dynamicIsland: { context in
            // 灵动岛显示内容
            DynamicIsland {
                // 展开状态 - 顶部区域
                DynamicIslandExpandedRegion(.leading) {
                    ScrcpyLiveActivityExpandedLeadingView(context: context)
                }
                
                // 展开状态 - 底部区域
                DynamicIslandExpandedRegion(.trailing) {
                    ScrcpyLiveActivityExpandedTrailingView(context: context)
                }
                
                // 展开状态 - 底部区域
                DynamicIslandExpandedRegion(.bottom) {
                    ScrcpyLiveActivityExpandedBottomView(context: context)
                }
            } compactLeading: {
                // 紧凑状态 - 左侧
                ScrcpyLiveActivityCompactLeadingView(context: context)
            } compactTrailing: {
                // 紧凑状态 - 右侧
                ScrcpyLiveActivityCompactTrailingView(context: context)
            } minimal: {
                // 最小状态
                ScrcpyLiveActivityMinimalView(context: context)
            }
        }
    }
}

// MARK: - 锁屏视图
@available(iOS 16.1, *)
struct ScrcpyLiveActivityLockScreenView: View {
    let context: ActivityViewContext<ScrcpyLiveActivityAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            // 简化的标题行
            HStack {
                // App 图标和名称
                HStack(spacing: 6) {
                    Image(systemName: "display")
                        .foregroundStyle(.blue)
                        .font(.title3)
                    
                    Text("Scrcpy")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                // 状态
                Text(context.state.connectionStatus)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(context.state.statusColor)
            }
            
            // 设备信息
            HStack {
                Image(systemName: deviceTypeIcon)
                    .foregroundStyle(deviceTypeColor)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.sessionName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text("\(context.state.hostAddress):\(context.state.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // 连接时长
                if context.state.isConnected {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        
                        Text(context.state.formattedDuration)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    }
                }
                
                // Tailscale 标识
                if context.state.isUsingTailscale {
                    Image(systemName: "shield.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var deviceTypeIcon: String {
        switch context.state.deviceType.lowercased() {
        case "android":
            return "smartphone"
        case "ios":
            return "iphone"
        default:
            return "display"
        }
    }
    
    private var deviceTypeColor: Color {
        switch context.state.deviceType.lowercased() {
        case "android":
            return .green
        case "ios":
            return .blue
        default:
            return .purple
        }
    }
}

// MARK: - 灵动岛展开视图 - 左侧
@available(iOS 16.1, *)
struct ScrcpyLiveActivityExpandedLeadingView: View {
    let context: ActivityViewContext<ScrcpyLiveActivityAttributes>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(context.state.sessionName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Text("\(context.state.hostAddress):\(context.state.port)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - 灵动岛展开视图 - 右侧
@available(iOS 16.1, *)
struct ScrcpyLiveActivityExpandedTrailingView: View {
    let context: ActivityViewContext<ScrcpyLiveActivityAttributes>
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(context.state.connectionStatus)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(context.state.statusColor)
            
            if context.state.isConnected {
                Text(context.state.formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - 灵动岛展开视图 - 底部
@available(iOS 16.1, *)
struct ScrcpyLiveActivityExpandedBottomView: View {
    let context: ActivityViewContext<ScrcpyLiveActivityAttributes>
    
    var body: some View {
        HStack {
            if context.state.isUsingTailscale {
                Text("Tailscale")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            
            Spacer()
            
            Text(context.state.deviceType)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 灵动岛紧凑视图 - 左侧
@available(iOS 16.1, *)
struct ScrcpyLiveActivityCompactLeadingView: View {
    let context: ActivityViewContext<ScrcpyLiveActivityAttributes>
    
    var body: some View {
        Image(systemName: context.state.statusIcon)
            .foregroundStyle(context.state.statusColor)
            .font(.caption)
    }
    
}

// MARK: - 灵动岛紧凑视图 - 右侧
@available(iOS 16.1, *)
struct ScrcpyLiveActivityCompactTrailingView: View {
    let context: ActivityViewContext<ScrcpyLiveActivityAttributes>
    
    var body: some View {
        if context.state.isConnected {
            Text(context.state.formattedDuration)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.green)
                .monospacedDigit()
        } else {
            Text(context.state.connectionStatus)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(context.state.statusColor)
                .lineLimit(1)
        }
    }
}

// MARK: - 灵动岛最小视图
@available(iOS 16.1, *)
struct ScrcpyLiveActivityMinimalView: View {
    let context: ActivityViewContext<ScrcpyLiveActivityAttributes>
    
    var body: some View {
        Image(systemName: context.state.statusIcon)
            .foregroundStyle(context.state.statusColor)
            .font(.caption)
    }
}

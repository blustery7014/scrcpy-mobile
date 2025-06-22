//
//  WindowUtil.swift
//  Scrcpy Remote
//
//  Created by Claude on 2025-06-22.
//

import Foundation
import UIKit
import SwiftUI

/// Window utility class for managing frontmost window detection and global alert display
class WindowUtil {
    
    /// 检查是否有活跃的窗口 - 动态获取最前显示的Window
    static func hasActiveWindow() -> Bool {
        if #available(iOS 13.0, *) {
            // iOS 13+ 使用 scene 方式
            let activeScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return activeScenes.contains { $0.activationState == .foregroundActive }
        } else {
            // iOS 12 及以下使用传统方式
            return UIApplication.shared.windows.contains { $0.isKeyWindow }
        }
    }
    
    /// 获取最前显示的窗口
    static func getFrontmostWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            // iOS 13+ 从活跃的 UIWindowScene 中获取关键窗口
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene,
                      windowScene.activationState == .foregroundActive else {
                    continue
                }
                
                // 获取该场景中的关键窗口
                for window in windowScene.windows {
                    if window.isKeyWindow {
                        return window
                    }
                }
                
                // 如果没有关键窗口，返回第一个可见窗口
                return windowScene.windows.first { $0.isHidden == false }
            }
        } else {
            // iOS 12 及以下使用传统方式
            if let keyWindow = UIApplication.shared.keyWindow {
                return keyWindow
            }
            return UIApplication.shared.windows.first { $0.isHidden == false }
        }
        
        return nil
    }
    
    /// 在最前显示的窗口上显示Action确认弹窗
    /// - Parameters:
    ///   - action: 需要确认的Action
    ///   - confirmCallback: 用户确认后的回调
    static func showGlobalActionConfirmation(action: ScrcpyAction, confirmCallback: @escaping () -> Void) {
        DispatchQueue.main.async {
            guard let frontmostWindow = getFrontmostWindow() else {
                print("❌ [WindowUtil] No frontmost window found, cannot show global confirmation")
                return
            }
            
            print("✅ [WindowUtil] Found frontmost window, showing global action confirmation for: \(action.name)")
            
            let alert = UIAlertController(
                title: "Execute Action",
                message: getActionExecutionSummary(action),
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Execute", style: .default) { _ in
                print("✅ [WindowUtil] User confirmed action execution")
                confirmCallback()
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                print("❌ [WindowUtil] User cancelled action execution")
            })
            
            // 从最前显示的窗口的根视图控制器展示Alert
            if let rootViewController = frontmostWindow.rootViewController {
                var topViewController = rootViewController
                
                // 找到最顶层的视图控制器
                while let presentedViewController = topViewController.presentedViewController {
                    topViewController = presentedViewController
                }
                
                topViewController.present(alert, animated: true) {
                    print("🎯 [WindowUtil] Global action confirmation presented on frontmost window")
                }
            } else {
                print("❌ [WindowUtil] No root view controller found on frontmost window")
            }
        }
    }
    
    /// 生成Action执行摘要文本
    /// - Parameter action: Action对象
    /// - Returns: 执行摘要文本
    private static func getActionExecutionSummary(_ action: ScrcpyAction) -> String {
        var summary = "About to execute '\(action.name)'\n\n"
        
        if action.deviceType == .vnc {
            if !action.vncQuickActions.isEmpty {
                summary += "VNC Actions:\n"
                for vncAction in action.vncQuickActions {
                    summary += "• \(vncAction.rawValue)\n"
                }
            }
        } else {
            // ADB Action details based on type
            switch action.adbActionType {
            case .homeKey:
                summary += "ADB Action: Home Key\n"
                summary += "• Execute 'adb shell input keyevent 3' (KEYCODE_HOME)"
                
            case .switchKey:
                summary += "ADB Action: Switch Key\n"
                summary += "• Execute 'adb shell input keyevent 187' (KEYCODE_APP_SWITCH)"
                
            case .inputKeys:
                summary += "ADB Action: Input Keys\n"
                if !action.adbInputKeysConfig.keys.isEmpty {
                    summary += "Key sequence (\(action.adbInputKeysConfig.intervalMs)ms interval):\n"
                    
                    // Display 4 keys per line to save space
                    let keys = action.adbInputKeysConfig.keys
                    var currentLine = ""
                    
                    for (index, keyAction) in keys.enumerated() {
                        let keyDisplay = "\(keyAction.keyName)(\(keyAction.keyCode))"
                        
                        if index % 4 == 0 {
                            // Start a new line
                            if !currentLine.isEmpty {
                                summary += currentLine + "\n"
                            }
                            currentLine = "\(index + 1). \(keyDisplay)"
                        } else {
                            // Add to current line
                            currentLine += "  \(index + 1). \(keyDisplay)"
                        }
                    }
                    
                    // Add the last line
                    if !currentLine.isEmpty {
                        summary += currentLine + "\n"
                    }
                } else {
                    summary += "• No keys configured"
                }
                
            case .shellCommands:
                summary += "ADB Action: Shell Commands\n"
                if !action.adbShellConfig.commands.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let commandLines = action.adbShellConfig.commands.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    
                    summary += "Commands (\(action.adbShellConfig.intervalMs)ms interval):\n"
                    
                    // Show first 5 commands
                    let displayCount = min(commandLines.count, 5)
                    for i in 0..<displayCount {
                        summary += "\(i + 1). \(commandLines[i])\n"
                    }
                    
                    // Show "and X more..." if there are more than 5 commands
                    if commandLines.count > 5 {
                        summary += "... and \(commandLines.count - 5) more commands"
                    }
                } else {
                    summary += "• No commands configured"
                }
            }
            
            // Show legacy commands if present (for backward compatibility)
            if !action.adbCommands.isEmpty {
                summary += "\n\nLegacy ADB Commands:\n\(action.adbCommands)"
            }
        }
        
        return summary
    }
}
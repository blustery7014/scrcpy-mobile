//
//  SDLVNCClient.h
//  VNCClient
//
//  Created by Ethan on 12/16/24.
//

#import <Foundation/Foundation.h>
#import "ScrcpyClientWrapper.h"

NS_ASSUME_NONNULL_BEGIN

// VNC Quick Action Types (matching Swift enum)
typedef NS_ENUM(NSInteger, VNCQuickActionType) {
    VNCQuickActionTypeMissionControl = 0,
    VNCQuickActionTypeDesktop,
    VNCQuickActionTypeLaunchpad,
    VNCQuickActionTypeInputText,
    VNCQuickActionTypeScreenshot,
    VNCQuickActionTypeClipboard
};

@interface ScrcpyVNCClient : NSObject

#pragma mark - Upper Layer Gesture Interface Methods

/// 发送鼠标点击事件到VNC服务器
/// @param location SDL坐标系中的点击位置
/// @param isRightClick 是否为右键点击
- (void)sendMouseClickAtLocation:(CGPoint)location isRightClick:(BOOL)isRightClick;

/// 发送鼠标移动事件到VNC服务器
/// @param location SDL坐标系中的鼠标位置
- (void)sendMouseMoveToLocation:(CGPoint)location;

/// 发送鼠标拖拽开始事件到VNC服务器
/// @param location SDL坐标系中的拖拽开始位置
- (void)sendMouseDragStartAtLocation:(CGPoint)location;

/// 发送鼠标拖拽移动事件到VNC服务器
/// @param location SDL坐标系中的拖拽位置
- (void)sendMouseDragToLocation:(CGPoint)location;

/// 发送鼠标拖拽结束事件到VNC服务器
/// @param location SDL坐标系中的拖拽结束位置
- (void)sendMouseDragEndAtLocation:(CGPoint)location;

/// 发送滚轮事件到VNC服务器
/// @param location SDL坐标系中的滚轮位置
/// @param deltaX 水平滚动增量
/// @param deltaY 垂直滚动增量
- (void)sendMouseWheelAtLocation:(CGPoint)location deltaX:(int)deltaX deltaY:(int)deltaY;

#pragma mark - VNC Action Execution Methods

/// 执行 VNC 快捷动作
/// @param actionType VNC 动作类型
/// @return 是否成功执行
- (BOOL)executeVNCAction:(VNCQuickActionType)actionType;

/// 执行多个 VNC 快捷动作
/// @param actionTypes VNC 动作类型数组
/// @param completion 完成回调，返回成功执行的动作数量
- (void)executeVNCActions:(NSArray<NSNumber *> *)actionTypes completion:(void(^)(NSInteger successCount))completion;

@end

NS_ASSUME_NONNULL_END

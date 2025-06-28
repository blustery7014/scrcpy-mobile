//
//  ScrcpyVNCClient+MouseControl.h
//  VNCClient
//
//  Created by Ethan on 12/28/24.
//

#import "ScrcpyVNCClient.h"
#import "CursorPosManager.h"

NS_ASSUME_NONNULL_BEGIN

/// Category for handling mouse and cursor control functionality
@interface ScrcpyVNCClient (MouseControl) <CursorPosManagerDelegate>

#pragma mark - Mouse Event Methods

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

#pragma mark - Cursor Management

/// 创建默认箭头光标纹理
- (void)createDefaultArrowCursor;

/// 渲染光标到屏幕
- (void)renderCursor;

/// 主动请求光标更新
/// 用于获取当前光标形状和位置
- (void)requestCursorUpdate;

#pragma mark - Touchpad Integration

/// 处理来自触摸屏的手势，转换为鼠标事件
/// @param touches 触摸点集合
/// @param event 触摸事件
/// @param eventType 事件类型（began, moved, ended）
- (void)handleTouchEvent:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event eventType:(NSString *)eventType;

#pragma mark - Internal Helper Methods

/// 将远程桌面坐标转换为当前渲染区域坐标
/// @param remoteLocation 远程桌面坐标
/// @return 当前渲染区域的坐标
- (CGPoint)convertRemoteLocationToRenderRegion:(CGPoint)remoteLocation;

/// 将渲染区域坐标转换为远程桌面坐标
/// @param renderLocation 渲染区域坐标
/// @return 远程桌面坐标
- (CGPoint)convertRenderLocationToRemote:(CGPoint)renderLocation;

@end

NS_ASSUME_NONNULL_END
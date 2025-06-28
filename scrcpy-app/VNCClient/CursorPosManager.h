#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// Forward declaration
@class CursorPosManager;

// Touchpad event types
typedef NS_ENUM(NSInteger, TouchpadEventType) {
    TouchpadEventTypeTap,           // Single tap (left click)
    TouchpadEventTypeTwoFingerTap,  // Two finger tap (right click)
    TouchpadEventTypeMove,          // Mouse movement
    TouchpadEventTypeDragStart,     // Start dragging (mouse down)
    TouchpadEventTypeDrag,          // Continue dragging (mouse drag)
    TouchpadEventTypeDragEnd,       // End dragging (mouse up)
    TouchpadEventTypeScroll         // Two finger scroll
};

// Touchpad event delegate protocol
@protocol CursorPosManagerDelegate <NSObject>
@optional
- (void)cursorPosManager:(CursorPosManager *)manager didGenerateEvent:(TouchpadEventType)eventType atRemoteLocation:(CGPoint)remoteLocation;
- (void)cursorPosManager:(CursorPosManager *)manager didGenerateScrollEvent:(CGPoint)remoteLocation deltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY;
- (void)cursorPosManager:(CursorPosManager *)manager didUpdateCursorPosition:(CGPoint)remoteLocation;
@end

@interface CursorPosManager : NSObject

// Delegate for touchpad events  
@property (nonatomic, assign) id<CursorPosManagerDelegate> delegate;

// 记录当前鼠标的实际位置
@property (nonatomic, assign) CGPoint underlyingPos;

// 用于输出显示屏幕上的鼠标位置 (underlyingPos + offsetPos)
@property (nonatomic, assign, readonly) CGPoint displayPos;

// 远程桌面的尺寸
@property (nonatomic, assign) CGSize remoteScreenSize;

// 当前展示区域的尺寸
@property (nonatomic, assign) CGSize localScreenSize;

// 换算出的远程屏幕上鼠标的坐标位置
@property (nonatomic, assign, readonly) CGPoint remoteCursorPos;

// Touchpad sensitivity settings
@property (nonatomic, assign) CGFloat sensitivity; // Default: 1.0
@property (nonatomic, assign) CGFloat scrollSensitivity; // Default: 1.0

#pragma mark - Original Movement Methods

/// 开始移动
/// @param startPos 拖拽开始的屏幕位置
- (void)beginMove:(CGPoint)startPos;

/// 移动到新位置
/// @param newPos 拖拽移动到的新屏幕位置
- (void)moveTo:(CGPoint)newPos;

/// 停止移动
- (void)stopMove;

#pragma mark - Touchpad Methods

/// 处理单指触摸开始（可能是点击或拖拽）
/// @param location 触摸位置
- (void)handleTouchBegin:(CGPoint)location;

/// 处理单指触摸移动
/// @param location 当前触摸位置
- (void)handleTouchMove:(CGPoint)location;

/// 处理单指触摸结束
/// @param location 结束位置
- (void)handleTouchEnd:(CGPoint)location;

/// 处理单指点击（轻触）
/// @param location 点击位置
- (void)handleTap:(CGPoint)location;

/// 处理双指点击（右键）
/// @param location 点击位置
- (void)handleTwoFingerTap:(CGPoint)location;

/// 处理双指滚动
/// @param location 滚动中心位置
/// @param deltaX 水平滚动增量
/// @param deltaY 垂直滚动增量
- (void)handleScroll:(CGPoint)location deltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY;

/// 重置所有状态
- (void)resetState;

@end

NS_ASSUME_NONNULL_END

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

// Mouse control methods are now available in ScrcpyVNCClient+MouseControl category

#pragma mark - VNC Action Execution Methods

/// 执行 VNC 快捷动作
/// @param actionType VNC 动作类型
/// @return 是否成功执行
- (BOOL)executeVNCAction:(VNCQuickActionType)actionType;

/// 执行多个 VNC 快捷动作
/// @param actionTypes VNC 动作类型数组
/// @param completion 完成回调，返回成功执行的动作数量
- (void)executeVNCActions:(NSArray<NSNumber *> *)actionTypes completion:(void(^)(BOOL success, NSString *error))completion;

/// 测试光标显示功能
/// @param cursorType 要测试的系统光标类型 (SDL_SystemCursor)
- (void)testCursorDisplay:(int)cursorType;

// Cursor management and touchpad integration methods are now available in ScrcpyVNCClient+MouseControl category

@end

NS_ASSUME_NONNULL_END

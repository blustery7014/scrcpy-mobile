//
//  ScrcpyClientWrapper.h
//  Scrcpy Remote
//
//  Created by Ethan on 12/15/24.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "scrcpy-porting.h"

NS_ASSUME_NONNULL_BEGIN

static inline UIWindowScene * GetCurrentWindowScene(void)
{
    for (UIWindowScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            return scene;
        }
    }
    return nil;
}

// Make interface to match: @implementation SDLUIKitDelegate
@interface SDLUIKitDelegate: NSObject<UIApplicationDelegate>
+ (id)sharedAppDelegate;
+ (NSString *)getAppDelegateClassName;
- (void)hideLaunchScreen;

- (UIWindow *)window;
- (void)applicationWillTerminate:(UIApplication *)application;
- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;
- (void)applicationWillResignActive:(UIApplication*)application;
- (void)applicationWillEnterForeground:(UIApplication*)application;
- (void)applicationDidBecomeActive:(UIApplication*)application;
@end


@interface ScrcpyClientWrapper : NSObject

- (void)startClient:(NSDictionary *)arguments completion:(void (^)(enum ScrcpyStatus statusCode, NSString *message))completion;

// Method for disconnect current active client
- (void)disconnectCurrentClient;

// MARK: - Action Execution Methods

/// 执行 VNC Actions
/// @param vncActions VNC 动作类型数组 (NSNumber array of VNCQuickActionType)
/// @param completion 完成回调
- (void)executeVNCActions:(NSArray<NSNumber *> *)vncActions completion:(void(^)(BOOL success, NSString *error))completion;

/// 执行 ADB Home 按键
/// @param deviceSerial 目标设备序列号
/// @param completion 完成回调
- (void)executeADBHomeKeyOnDevice:(NSString *)deviceSerial completion:(void (^)(NSString * _Nullable output, int returnCode))completion;

/// 执行 ADB Switch 按键
/// @param deviceSerial 目标设备序列号
/// @param completion 完成回调
- (void)executeADBSwitchKeyOnDevice:(NSString *)deviceSerial completion:(void (^)(NSString * _Nullable output, int returnCode))completion;

/// 执行 ADB 按键序列
/// @param keyCodes 按键码数组
/// @param deviceSerial 目标设备序列号
/// @param intervalMs 按键间隔（毫秒）
/// @param completion 完成回调
- (void)executeADBKeySequence:(NSArray<NSNumber *> *)keyCodes
                     onDevice:(NSString *)deviceSerial
                     interval:(NSInteger)intervalMs
                   completion:(void(^)(NSInteger successCount, NSString *error))completion;

/// 执行 ADB Shell 命令序列
/// @param commands 命令字符串数组
/// @param deviceSerial 目标设备序列号
/// @param intervalMs 命令间隔（毫秒）
/// @param completion 完成回调
- (void)executeADBShellCommands:(NSArray<NSString *> *)commands
                       onDevice:(NSString *)deviceSerial
                       interval:(NSInteger)intervalMs
                     completion:(void(^)(BOOL success, NSString *error))completion;

@end

NS_ASSUME_NONNULL_END

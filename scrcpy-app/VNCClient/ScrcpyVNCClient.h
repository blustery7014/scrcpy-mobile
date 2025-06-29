//
//  ScrcpyVNCClient.h
//  VNCClient
//
//  Created by Ethan on 6/28/25.
//

#import <Foundation/Foundation.h>
#import "ScrcpyClientWrapper.h"
#import "ScrcpyCommon.h"
#import <SDL2/SDL.h>
#import <rfb/rfbclient.h>
#import <rfb/keysym.h>
#import <stdlib.h>
#import <arpa/inet.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyVNCClient : NSObject <ScrcpyClientProtocol>

@property (nonatomic, strong) SDLUIKitDelegate *sdlDelegate;
@property (nonatomic, copy) void (^sessionCompletion)(enum ScrcpyStatus, NSString *);
@property (nonatomic, copy) NSDictionary *sessionArguments;

// VNC客户端状态
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign, nullable) rfbClient *rfbClient;
@property (nonatomic, assign) enum ScrcpyStatus scrcpyStatus;

// VNC远程桌面的图像像素大小
@property (nonatomic, assign) CGSize imagePixelsSize;

// SDL渲染对象
@property (nonatomic, assign) SDL_Renderer *currentRenderer;
@property (nonatomic, assign) SDL_Texture *currentTexture;

// 鼠标坐标管理
@property (nonatomic, assign) int currentMouseX;
@property (nonatomic, assign) int currentMouseY;

- (UIWindowScene *)currentScene;

/// 启动VNC连接并显示
/// @param arguments 连接参数，包含主机、端口、用户名、密码等信息
/// @param completion 连接完成回调
- (void)startWithArguments:(NSDictionary *)arguments completion:(void (^)(enum ScrcpyStatus, NSString *))completion;

/// 停止VNC连接
- (void)stopVNC;

/// 移动远程鼠标到指定位置
/// @param x 目标X坐标
/// @param y 目标Y坐标
- (void)moveMouseToX:(int)x y:(int)y;

/// 发送鼠标点击事件到远程桌面
/// @param x 点击X坐标
/// @param y 点击Y坐标
/// @param isRightClick 是否为右键点击
- (void)sendMouseClickAtX:(int)x y:(int)y isRightClick:(BOOL)isRightClick;

@end

NS_ASSUME_NONNULL_END

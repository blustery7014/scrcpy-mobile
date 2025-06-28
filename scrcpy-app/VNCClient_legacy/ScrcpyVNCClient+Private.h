//
//  ScrcpyVNCClient+Private.h
//  VNCClient
//
//  Created by Ethan on 12/28/24.
//

#import "ScrcpyVNCClient.h"
#import "CursorPosManager.h"
#import "RenderRegionCalculator.h"
#import <SDL2/SDL.h>
#import <rfb/rfbclient.h>

NS_ASSUME_NONNULL_BEGIN

/// Private interface for accessing internal properties from Categories
@interface ScrcpyVNCClient ()

// VNC Client Status
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) rfbClient *rfbClient;

// VNC 远程桌面的图像像素大小
@property (nonatomic, assign) CGSize imagePixelsSize;

// 本机渲染屏幕区域大小
@property (nonatomic, assign) CGSize renderScreenSize;

// SDL rendering objects
@property (nonatomic, assign) SDL_Renderer *currentRenderer;
@property (nonatomic, assign) SDL_Texture *currentTexture;

// VNC 光标相关属性
@property (nonatomic, assign) SDL_Texture *cursorTexture;
@property (nonatomic, assign) int cursorX;
@property (nonatomic, assign) int cursorY;
@property (nonatomic, assign) int cursorWidth;
@property (nonatomic, assign) int cursorHeight;
@property (nonatomic, assign) int cursorHotX;
@property (nonatomic, assign) int cursorHotY;
@property (nonatomic, assign) BOOL cursorVisible;

// VNC 拖拽手势相关属性
@property (nonatomic, strong) CursorPosManager *cursorPosManager;
@property (nonatomic, assign) int buttonMask;

// Scale render properties
@property (nonatomic, strong) RenderRegionResult *currentRenderingRegion;

@end

NS_ASSUME_NONNULL_END
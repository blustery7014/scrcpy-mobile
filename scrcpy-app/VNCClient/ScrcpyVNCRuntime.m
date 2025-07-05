//
//  ScrcpyVNCRuntime.m
//  VNCClient
//
//  Created by Ethan on 6/28/25.
//

#import "ScrcpyVNCRuntime.h"
#import "ScrcpyCommon.h"
#import "ScrcpyConstants.h"
#import <SDL2/SDL.h>
#import <rfb/rfbclient.h>
#import <arpa/inet.h>
#import <objc/runtime.h>
#import <math.h>
#import "ScrcpyVNCClient.h"

// 光标边缘跟随常量定义
static const int CURSOR_EDGE_THRESHOLD = 20;     // 边缘阈值（像素）- 光标距离屏幕边缘多近时触发跟随
static const int CURSOR_FOLLOW_DISTANCE = 40;    // 边缘跟随移动距离（2倍阈值）- 一次移动的距离
static const int CURSOR_FOLLOW_COOLDOWN = 2;     // 冷却时间（帧数）- 降低为2帧提高响应性

// 旧版本的常量定义（用于旧函数，后续将移除）
static const int CURSOR_FOLLOW_SPEED = 8;        // 每帧移动速度（像素）- 平滑连续移动
static const float CURSOR_FOLLOW_ACCELERATION = 1.5f; // 加速系数 - 距离边缘越近移动越快

// 光标位置跟踪变量 - 用于检测移动方向和防振荡
static int g_lastScreenMouseX = -1;
static int g_lastScreenMouseY = -1;
static int g_lastRemoteMouseX = -1;   // 上次的远程鼠标X坐标
static int g_lastRemoteMouseY = -1;   // 上次的远程鼠标Y坐标
static int g_lastViewOffsetX = 0;
static int g_lastViewOffsetY = 0;
static int g_edgeFollowCooldown = 0;  // 防振荡冷却计数器
static BOOL g_mouseMovedThisFrame = NO;  // 标记本帧是否由于鼠标移动产生位置变化
static BOOL g_mouseIsMoving = NO;     // 标记鼠标是否正在移动
static BOOL g_mouseJustStopped = NO;  // 标记鼠标是否刚刚停止移动（用于边界情况）
static int g_mouseStopCounter = 0;    // 鼠标停止移动计数器
static const int MOUSE_STOP_THRESHOLD = 3;  // 鼠标停止移动阈值（帧数）


// 前向声明
void VNCRuntimeDrawMacOSCursor(SDL_Renderer* renderer, int x, int y, float scale);
void VNCRuntimeSetMouseMoved(void);
static void VNCRuntimeCheckCursorEdgeFollow(ScrcpyVNCClient* vncClient, int screenMouseX, int screenMouseY, 
                                          int renderWidth, int renderHeight, int* offsetX, int* offsetY,
                                          int scaledWidth, int scaledHeight, int textureWidth, int textureHeight, float finalScale);

/**
 * 自定义的SetFormatAndEncodings函数，确保包含光标编码
 */
static rfbBool CustomSetFormatAndEncodings(rfbClient* client) {
    // 首先调用原始的SetFormatAndEncodings函数
    rfbBool result = SetFormatAndEncodings(client);
    
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to set format and encodings");
        return FALSE;
    }
    
    // 发送额外的编码设置，确保包含光标编码
    uint32_t encodings[] = {
        rfbEncodingRaw,
        rfbEncodingCopyRect,
        rfbEncodingRRE,
        rfbEncodingCoRRE,
        rfbEncodingHextile,
        rfbEncodingZlib,
        rfbEncodingTight,
        rfbEncodingXCursor,      // 添加X光标编码
        rfbEncodingRichCursor,   // 添加富光标编码
        rfbEncodingPointerPos    // 添加指针位置编码
    };
    
    int numEncodings = sizeof(encodings) / sizeof(encodings[0]);
    
    // 发送SetEncodings消息
    rfbSetEncodingsMsg msg;
    msg.type = rfbSetEncodings;
    msg.pad = 0;
    msg.nEncodings = htons(numEncodings);
    
    if (!WriteToRFBServer(client, (char *)&msg, sz_rfbSetEncodingsMsg)) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send SetEncodings message header");
        return FALSE;
    }
    
    // 发送编码列表
    for (int i = 0; i < numEncodings; i++) {
        uint32_t encoding = htonl(encodings[i]);
        if (!WriteToRFBServer(client, (char *)&encoding, sizeof(encoding))) {
            NSLog(@"❌ [ScrcpyVNCClient] Failed to send encoding %d", encodings[i]);
            return FALSE;
        }
    }
    
    NSLog(@"✅ [ScrcpyVNCClient] Successfully set encodings including cursor encodings");
    return TRUE;
}


// VNC runtime callback implementations

rfbBool VNCRuntimeMallocFrameBuffer(rfbClient* client, ScrcpyVNCClient *vncClient, SDL_Window **sdlWindow, SDL_Renderer **sdlRenderer, SDL_Texture **sdlTexture) {
    int width = client->width, height = client->height, depth = client->format.bitsPerPixel;

    // 保存VNC客户端实例引用，以便在回调中访问
    rfbClientSetClientData(client, (void*)0x1234, (__bridge void*)vncClient);

    // 保存原始尺寸（仅在第一次时保存）
    if (vncClient.imagePixelsSize.width == 0 && vncClient.imagePixelsSize.height == 0) {
        vncClient.imagePixelsSize = CGSizeMake(width, height);
        NSLog(@"🔍 [ScrcpyVNCClient] VNC remote screen size: %.0fx%.0f", (double)width, (double)height);
    }
    
    // 释放旧surface并创建新的
    SDL_FreeSurface(rfbClientGetClientData(client, SDL_Init));
    SDL_Surface* sdl = SDL_CreateRGBSurface(0, width, height, depth, 0, 0, 0, 0);
    if (!sdl) {
        rfbClientErr("resize: error creating surface: %s\n", SDL_GetError());
        return FALSE;
    }

    rfbClientSetClientData(client, SDL_Init, sdl);
    client->width = sdl->pitch / (depth / 8);
    client->frameBuffer = sdl->pixels;

    // 设置像素格式
    client->format.bitsPerPixel = depth;
    client->format.redShift = sdl->format->Rshift;
    client->format.greenShift = sdl->format->Gshift;
    client->format.blueShift = sdl->format->Bshift;
    client->format.redMax = sdl->format->Rmask >> client->format.redShift;
    client->format.greenMax = sdl->format->Gmask >> client->format.greenShift;
    client->format.blueMax = sdl->format->Bmask >> client->format.blueShift;
    
    CustomSetFormatAndEncodings(client);

    // 获取设备屏幕尺寸（考虑Retina缩放）
    int screenWidth, screenHeight;
    SDL_DisplayMode displayMode;
    SDL_GetCurrentDisplayMode(0, &displayMode);
    
    NSLog(@"[VNCScreenDebug] SDL DisplayMode: %dx%d", displayMode.w, displayMode.h);
    
    screenWidth = (int)displayMode.w;
    screenHeight = (int)displayMode.h;
    
    NSLog(@"[VNCScreenDebug] Final screen size: %dx%d", screenWidth, screenHeight);
    NSLog(@"[VNCScreenDebug] Remote screen size: %dx%d", width, height);
    
    // 计算缩放比例，保持宽高比
    float scaleX = (float)screenWidth / width;
    float scaleY = (float)screenHeight / height;
    float scale = fminf(scaleX, scaleY);
    
    NSLog(@"[VNCScreenDebug] Scale calculation: scaleX=%.3f, scaleY=%.3f, final scale=%.3f", scaleX, scaleY, scale);
    
    int scaledWidth = (int)(width * scale);
    int scaledHeight = (int)(height * scale);
    
    NSLog(@"[VNCScreenDebug] Scaled remote size: %dx%d", scaledWidth, scaledHeight);
    
    // 创建全屏窗口（使用设备屏幕尺寸）
    int sdlFlags = SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_FULLSCREEN;
    *sdlWindow = SDL_CreateWindow(client->desktopName,
                                  SDL_WINDOWPOS_UNDEFINED,
                                  SDL_WINDOWPOS_UNDEFINED,
                                  screenWidth,
                                  screenHeight,
                                  sdlFlags);
                                 
    NSLog(@"[VNCScreenDebug] Created SDL window with size: %dx%d", screenWidth, screenHeight);
    if (!sdlWindow) {
        rfbClientErr("resize: error creating window: %s\n", SDL_GetError());
        return FALSE;
    }
    
    // 检查实际创建的窗口尺寸
    int actualWidth, actualHeight;
    SDL_GetWindowSize(*sdlWindow, &actualWidth, &actualHeight);
    NSLog(@"[VNCScreenDebug] Actual SDL window size: %dx%d", actualWidth, actualHeight);
    
    // 检查窗口标志
    Uint32 windowFlags = SDL_GetWindowFlags(*sdlWindow);
    NSLog(@"[VNCScreenDebug] Window flags: 0x%x (fullscreen: %s)",
          windowFlags, (windowFlags & SDL_WINDOW_FULLSCREEN) ? "YES" : "NO");

    // 更新状态
    vncClient.scrcpyStatus = ScrcpyStatusSDLWindowCreated;
    ScrcpyUpdateStatus(ScrcpyStatusSDLWindowCreated, "SDL window created successfully");

    // 创建渲染器
    *sdlRenderer = SDL_CreateRenderer(*sdlWindow, -1, SDL_RENDERER_ACCELERATED);
    if (!sdlRenderer) {
        rfbClientErr("resize: error creating renderer: %s\n", SDL_GetError());
        return FALSE;
    }
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");
    
    // 获取设备缩放因子并设置SDL渲染器缩放
    float deviceScale = UIScreen.mainScreen.nativeScale;
    NSLog(@"[VNCScreenDebug] Device scale factor: %.2f", deviceScale);
    SDL_RenderSetScale(*sdlRenderer, deviceScale, deviceScale);
    
    // 保存渲染器
    vncClient.currentRenderer = *sdlRenderer;
    
    // 设置SDL窗口
    vncClient.sdlDelegate.window.windowScene = vncClient.currentScene;
    [vncClient.sdlDelegate.window makeKeyWindow];

    // 创建纹理
    *sdlTexture = SDL_CreateTexture(*sdlRenderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, width, height);
    if (!*sdlTexture) {
        rfbClientErr("resize: error creating texture: %s\n", SDL_GetError());
        return FALSE;
    }
    
    // 保存纹理
    vncClient.currentTexture = *sdlTexture;
    
    // 设置帧缓冲区更新回调（在SDL对象创建后）
    vncClient.rfbClient->GotFrameBufferUpdate = GotFrameBufferUpdateBlock;
    VNCRuntimeSetupGotFrameBufferUpdateCallback(vncClient.rfbClient, *sdlTexture, *sdlRenderer, *sdlWindow);
    
    return TRUE;
}

static inline void VNCRuntimeGotFrameBufferUpdate(rfbClient* cl, int x, int y, int w, int h, SDL_Texture* sdlTexture, SDL_Renderer* sdlRenderer, SDL_Window* sdlWindow) {
    NSLog(@"📦 [FrameBufferUpdate] START: x=%d, y=%d, w=%d, h=%d, g_mouseMovedThisFrame=%s", 
          x, y, w, h, g_mouseMovedThisFrame ? "YES" : "NO");
    
    if (!sdlTexture || !sdlRenderer || !sdlWindow) {
        NSLog(@"❌ [VNCRuntime] Invalid SDL objects: texture=%p, renderer=%p, window=%p", sdlTexture, sdlRenderer, sdlWindow);
        return;
    }
    
    SDL_Surface *sdl = rfbClientGetClientData(cl, SDL_Init);
    if (!sdl || !sdl->pixels) {
        NSLog(@"❌ [VNCRuntime] Invalid SDL surface or pixels");
        return;
    }
    
    SDL_Rect r = {x, y, w, h};
    
    if (SDL_UpdateTexture(sdlTexture, &r, sdl->pixels + y*sdl->pitch + x*4, sdl->pitch) < 0) {
        rfbClientErr("update: failed to update texture: %s\n", SDL_GetError());
        return;
    }
    
    // 获取窗口和纹理尺寸
    int windowWidth, windowHeight;
    SDL_GetWindowSize(sdlWindow, &windowWidth, &windowHeight);
    
    int textureWidth, textureHeight;
    SDL_QueryTexture(sdlTexture, NULL, NULL, &textureWidth, &textureHeight);
    
    // 获取渲染器的逻辑尺寸
    int logicalWidth, logicalHeight;
    SDL_RenderGetLogicalSize(sdlRenderer, &logicalWidth, &logicalHeight);
    
    // 如果设置了逻辑尺寸，使用逻辑尺寸；否则使用窗口尺寸
    int renderWidth = logicalWidth > 0 ? logicalWidth : windowWidth;
    int renderHeight = logicalHeight > 0 ? logicalHeight : windowHeight;
    
    NSLog(@"[VNCScreenDebug] Render - Window: %dx%d, Logical: %dx%d, Texture: %dx%d", 
          windowWidth, windowHeight, renderWidth, renderHeight, textureWidth, textureHeight);
    
    // 获取VNC客户端实例以获取缩放参数
    ScrcpyVNCClient *vncClient = (__bridge ScrcpyVNCClient*)rfbClientGetClientData(cl, (void*)0x1234);
    
    // 计算基础缩放（保持比例的适配缩放）
    float baseScaleX = (float)renderWidth / textureWidth;
    float baseScaleY = (float)renderHeight / textureHeight;
    float baseScale = fminf(baseScaleX, baseScaleY);
    
    // 应用用户缩放（从双指手势）
    float userZoomScale = 1.0f;
    float zoomCenterX = 0.5f;
    float zoomCenterY = 0.5f;
    
    if (vncClient) {
        userZoomScale = vncClient.currentZoomScale;
        zoomCenterX = vncClient.zoomCenterX;
        zoomCenterY = vncClient.zoomCenterY;
        
        // 更新渲染参数用于边缘跟随
        vncClient.renderWidth = renderWidth;
        vncClient.renderHeight = renderHeight;
        vncClient.remoteDesktopWidth = textureWidth;
        vncClient.remoteDesktopHeight = textureHeight;
        
        // 清除更新标志
        if (vncClient.zoomUpdatePending) {
            vncClient.zoomUpdatePending = NO;
            NSLog(@"🔍 [VNCRuntime] Applying user zoom: %.2f at center (%.3f, %.3f)", 
                  userZoomScale, zoomCenterX, zoomCenterY);
        }
    }
    
    // 最终缩放 = 基础缩放 × 用户缩放
    float finalScale = baseScale * userZoomScale;
    
    int scaledWidth = (int)(textureWidth * finalScale);
    int scaledHeight = (int)(textureHeight * finalScale);
    
    // 计算偏移量，考虑缩放中心和边缘跟随调整
    int centerX = (int)(renderWidth * zoomCenterX);
    int centerY = (int)(renderHeight * zoomCenterY);
    
    int offsetX = centerX - (int)(scaledWidth * zoomCenterX);
    int offsetY = centerY - (int)(scaledHeight * zoomCenterY);
    
    // 应用边缘跟随的偏移量调整
    if (vncClient) {
        offsetX += vncClient.viewOffsetX;
        offsetY += vncClient.viewOffsetY;
    }
    
    // 边界检查 - 边缘跟随调整后的最终检查
    if (scaledWidth <= renderWidth) {
        // 如果缩放后内容小于等于屏幕，居中显示 - 重置viewOffset
        offsetX = (renderWidth - scaledWidth) / 2;
        if (vncClient) vncClient.viewOffsetX = 0;
    } else {
        // 如果缩放后内容大于屏幕，限制边界并更新viewOffset
        if (offsetX > 0) {
            offsetX = 0;
            if (vncClient) vncClient.viewOffsetX = 0;
        }
        if (offsetX + scaledWidth < renderWidth) {
            offsetX = renderWidth - scaledWidth;
            if (vncClient) vncClient.viewOffsetX = renderWidth - scaledWidth - (centerX - (int)(scaledWidth * zoomCenterX));
        }
    }
    
    if (scaledHeight <= renderHeight) {
        // 如果缩放后内容小于等于屏幕，居中显示 - 重置viewOffset
        offsetY = (renderHeight - scaledHeight) / 2;
        if (vncClient) vncClient.viewOffsetY = 0;
    } else {
        // 如果缩放后内容大于屏幕，限制边界并更新viewOffset
        if (offsetY > 0) {
            offsetY = 0;
            if (vncClient) vncClient.viewOffsetY = 0;
        }
        if (offsetY + scaledHeight < renderHeight) {
            offsetY = renderHeight - scaledHeight;
            if (vncClient) vncClient.viewOffsetY = renderHeight - scaledHeight - (centerY - (int)(scaledHeight * zoomCenterY));
        }
    }
    
    // 绘制鼠标光标并检查边缘跟随（在绘制内容之前）
    if (vncClient && cl->appData.useRemoteCursor) {
        // 执行简化的边缘跟随检测
        int remoteMouseX = vncClient.currentMouseX;
        int remoteMouseY = vncClient.currentMouseY;
        
        // 将远程坐标转换为本地屏幕坐标
        int screenMouseX = offsetX + (remoteMouseX * scaledWidth) / textureWidth;
        int screenMouseY = offsetY + (remoteMouseY * scaledHeight) / textureHeight;
        
        NSLog(@"🔧 [CoordTransform] Remote: (%d,%d), offsetX=%d, offsetY=%d, scaledW/H=%dx%d, textureW/H=%dx%d", 
              remoteMouseX, remoteMouseY, offsetX, offsetY, scaledWidth, scaledHeight, textureWidth, textureHeight);
        NSLog(@"🔧 [CoordTransform] Result: screenMouseX=%d, screenMouseY=%d", screenMouseX, screenMouseY);
        
        // 检测鼠标是否在合理的范围内
        // 大幅放宽范围限制，允许快速移动时的边缘跟随
        int extendedThreshold = CURSOR_EDGE_THRESHOLD * 5; // 扩展到100像素范围
        BOOL mouseInValidRange = (screenMouseX >= -extendedThreshold && screenMouseX < renderWidth + extendedThreshold && 
                                 screenMouseY >= -extendedThreshold && screenMouseY < renderHeight + extendedThreshold);
        
        NSLog(@"🔍 [SimpleEdgeFollow] Remote: (%d,%d) -> Screen: (%d,%d), Render: %dx%d", 
              remoteMouseX, remoteMouseY, screenMouseX, screenMouseY, renderWidth, renderHeight);
        NSLog(@"📐 [ScaledSize] scaledWidth=%d, scaledHeight=%d, renderWidth=%d, renderHeight=%d", 
              scaledWidth, scaledHeight, renderWidth, renderHeight);
        NSLog(@"📍 [ViewOffset] Current: viewOffsetX=%d, viewOffsetY=%d", 
              vncClient.viewOffsetX, vncClient.viewOffsetY);
        NSLog(@"🎯 [MouseCheck] MovedThisFrame: %s, InValidRange: %s, IsMoving: %s, StopCounter: %d", 
              g_mouseMovedThisFrame ? "YES" : "NO", mouseInValidRange ? "YES" : "NO", 
              g_mouseIsMoving ? "YES" : "NO", g_mouseStopCounter);
        
        // 更新鼠标移动状态（在检测之后）
        if (!g_mouseMovedThisFrame) {
            g_mouseStopCounter++;
            if (g_mouseStopCounter == MOUSE_STOP_THRESHOLD) {
                // 鼠标刚刚停止移动，设置标记用于边界情况处理
                g_mouseJustStopped = YES;
                g_mouseIsMoving = NO;
                NSLog(@"🛑 [MouseStop] Mouse just stopped moving after %d frames, setting justStopped flag", MOUSE_STOP_THRESHOLD);
            }
        } else {
            // 重置刚停止标记（如果鼠标重新开始移动）
            g_mouseJustStopped = NO;
        }
        
        // 防振荡：减少冷却计数器
        if (g_edgeFollowCooldown > 0) {
            g_edgeFollowCooldown--;
            NSLog(@"🔍 [SimpleEdgeFollow] Cooldown active: %d frames remaining", g_edgeFollowCooldown);
        }
        
        // 基础边缘跟随条件：
        // 1. 冷却时间结束
        // 2. 鼠标正在移动或刚刚停止移动（处理边界情况）
        // 3. 鼠标在有效范围内（包括超出边界的情况）
        // 特殊情况：如果鼠标明显超出边界，即使本帧没有移动也允许跟随
        BOOL canTriggerMovingOrJustStopped = g_mouseIsMoving || g_mouseJustStopped;
        BOOL mouseNeedsRescue = (screenMouseX < 0 || screenMouseX >= renderWidth || 
                               screenMouseY < 0 || screenMouseY >= renderHeight);
        BOOL baseCanTriggerEdgeFollow = (g_edgeFollowCooldown == 0) && mouseInValidRange && 
                                       (canTriggerMovingOrJustStopped || mouseNeedsRescue);
        
        NSLog(@"🎯 [EdgeFollowConditions] Cooldown: %d, IsMoving: %s, JustStopped: %s, InValidRange: %s, NeedsRescue: %s, CanTrigger: %s", 
              g_edgeFollowCooldown, g_mouseIsMoving ? "YES" : "NO", g_mouseJustStopped ? "YES" : "NO", 
              mouseInValidRange ? "YES" : "NO", mouseNeedsRescue ? "YES" : "NO", baseCanTriggerEdgeFollow ? "YES" : "NO");
        
        // 水平边缘检测 - 直接移动，无平滑处理
        if (scaledWidth > renderWidth) {
            int currentOffsetX = offsetX;
            NSLog(@"🔍 [HorizontalEdgeCheck] scaledWidth=%d > renderWidth=%d, currentOffsetX=%d", 
                  scaledWidth, renderWidth, currentOffsetX);
            
            // 检查左边缘条件
            BOOL leftEdgeCondition = (screenMouseX < CURSOR_EDGE_THRESHOLD);
            BOOL leftContentAvailable = (currentOffsetX < 0);
            NSLog(@"🔍 [LeftEdgeCheck] screenMouseX=%d < threshold=%d: %s, contentAvailable=%s", 
                  screenMouseX, CURSOR_EDGE_THRESHOLD, leftEdgeCondition ? "YES" : "NO", 
                  leftContentAvailable ? "YES" : "NO");
            
            // 左边缘：鼠标在左侧阈值内，且还有左侧内容可以显示
            if (baseCanTriggerEdgeFollow && leftEdgeCondition && leftContentAvailable) {
                // 向右移动视图（增加viewOffsetX）
                int maxViewOffsetX = -currentOffsetX + vncClient.viewOffsetX;
                int newViewOffsetX = vncClient.viewOffsetX + CURSOR_FOLLOW_DISTANCE;
                vncClient.viewOffsetX = MIN(maxViewOffsetX, newViewOffsetX);
                
                g_edgeFollowCooldown = CURSOR_FOLLOW_COOLDOWN;
                NSLog(@"🔄 [SimpleEdgeFollow] ✅ LEFT edge triggered: viewOffsetX %d -> %d", 
                      vncClient.viewOffsetX - CURSOR_FOLLOW_DISTANCE, vncClient.viewOffsetX);
            }
            // 右边缘：鼠标在右侧阈值内，且还有右侧内容可以显示
            else if (baseCanTriggerEdgeFollow && screenMouseX > (renderWidth - CURSOR_EDGE_THRESHOLD) && 
                     (currentOffsetX + scaledWidth) > renderWidth) {
                // 向左移动视图（减少viewOffsetX）
                int minViewOffsetX = (renderWidth - scaledWidth) - currentOffsetX + vncClient.viewOffsetX;
                int newViewOffsetX = vncClient.viewOffsetX - CURSOR_FOLLOW_DISTANCE;
                vncClient.viewOffsetX = MAX(minViewOffsetX, newViewOffsetX);
                
                g_edgeFollowCooldown = CURSOR_FOLLOW_COOLDOWN;
                NSLog(@"🔄 [SimpleEdgeFollow] ✅ RIGHT edge triggered: viewOffsetX %d -> %d", 
                      vncClient.viewOffsetX + CURSOR_FOLLOW_DISTANCE, vncClient.viewOffsetX);
            }
        }
        
        // 垂直边缘检测 - 直接移动，无平滑处理
        NSLog(@"🔍 [VerticalEdgeCheck] scaledHeight=%d vs renderHeight=%d, condition: %s", 
              scaledHeight, renderHeight, (scaledHeight > renderHeight) ? "TRUE" : "FALSE");
        if (scaledHeight > renderHeight) {
            int currentOffsetY = offsetY;
            NSLog(@"🔍 [VerticalEdgeCheck] ENABLED - currentOffsetY=%d, screenMouseY=%d", currentOffsetY, screenMouseY);
            
            // 上边缘：鼠标在上侧阈值内，且还有上侧内容可以显示
            if (baseCanTriggerEdgeFollow && screenMouseY < CURSOR_EDGE_THRESHOLD && currentOffsetY < 0) {
                // 向下移动视图（增加viewOffsetY）
                int maxViewOffsetY = -currentOffsetY + vncClient.viewOffsetY;
                int newViewOffsetY = vncClient.viewOffsetY + CURSOR_FOLLOW_DISTANCE;
                vncClient.viewOffsetY = MIN(maxViewOffsetY, newViewOffsetY);
                
                g_edgeFollowCooldown = CURSOR_FOLLOW_COOLDOWN;
                NSLog(@"🔄 [SimpleEdgeFollow] ✅ TOP edge triggered: viewOffsetY %d -> %d", 
                      vncClient.viewOffsetY - CURSOR_FOLLOW_DISTANCE, vncClient.viewOffsetY);
            }
            // 下边缘：鼠标在下侧阈值内，且还有下侧内容可以显示
            else if (baseCanTriggerEdgeFollow && screenMouseY > (renderHeight - CURSOR_EDGE_THRESHOLD) && 
                     (currentOffsetY + scaledHeight) > renderHeight) {
                // 向上移动视图（减少viewOffsetY）
                int minViewOffsetY = (renderHeight - scaledHeight) - currentOffsetY + vncClient.viewOffsetY;
                int newViewOffsetY = vncClient.viewOffsetY - CURSOR_FOLLOW_DISTANCE;
                vncClient.viewOffsetY = MAX(minViewOffsetY, newViewOffsetY);
                
                g_edgeFollowCooldown = CURSOR_FOLLOW_COOLDOWN;
                NSLog(@"🔄 [SimpleEdgeFollow] ✅ BOTTOM edge triggered: viewOffsetY %d -> %d", 
                      vncClient.viewOffsetY + CURSOR_FOLLOW_DISTANCE, vncClient.viewOffsetY);
            }
        }
        
        // 更新防振荡跟踪变量
        g_lastViewOffsetX = vncClient.viewOffsetX;
        g_lastViewOffsetY = vncClient.viewOffsetY;
        
        // 重置鼠标移动标记，为下一帧做准备（必须在边缘跟随检测完成后）
        g_mouseMovedThisFrame = NO;
        
        // 重置刚停止标记，确保只使用一次（处理边界情况后）
        if (g_mouseJustStopped) {
            g_mouseJustStopped = NO;
            NSLog(@"🔄 [MouseStop] Reset justStopped flag after edge follow processing");
        }
    }
    
    // 使用可能更新后的偏移量创建目标矩形
    SDL_Rect dstRect = {offsetX, offsetY, scaledWidth, scaledHeight};
    
    NSLog(@"[VNCScreenDebug] BaseScale: %.3f, UserZoom: %.2f, FinalScale: %.3f, Scaled: %dx%d, Offset: %d,%d", 
          baseScale, userZoomScale, finalScale, scaledWidth, scaledHeight, offsetX, offsetY);
    NSLog(@"[VNCScreenDebug] ZoomCenter: (%.3f, %.3f), ScreenCenter: (%d, %d)", 
          zoomCenterX, zoomCenterY, centerX, centerY);
    
    // 清除渲染器并绘制纹理（居中并保持比例）
    SDL_SetRenderDrawColor(sdlRenderer, 0, 0, 0, 255);
    SDL_RenderClear(sdlRenderer);
    SDL_RenderCopy(sdlRenderer, sdlTexture, NULL, &dstRect);
    
    // 绘制鼠标光标（使用最终的屏幕坐标）
    if (vncClient && cl->appData.useRemoteCursor) {
        int remoteMouseX = vncClient.currentMouseX;
        int remoteMouseY = vncClient.currentMouseY;
        int screenMouseX = offsetX + (remoteMouseX * scaledWidth) / textureWidth;
        int screenMouseY = offsetY + (remoteMouseY * scaledHeight) / textureHeight;
        
        // 绘制macOS风格的鼠标光标（使用最终缩放）
        VNCRuntimeDrawMacOSCursor(sdlRenderer, screenMouseX, screenMouseY, finalScale);
        
        NSLog(@"🖱️ [VNCRuntime] Drawing cursor at remote(%d,%d) -> screen(%d,%d), finalScale=%.2f", 
              remoteMouseX, remoteMouseY, screenMouseX, screenMouseY, finalScale);
    }
    
    SDL_RenderPresent(sdlRenderer);
}

static inline rfbBool VNCRuntimeHandleCursorPos(rfbClient* cl, int x, int y, int* currentMouseX, int* currentMouseY) {
    NSLog(@"🖱️ [ScrcpyVNCClient] Received cursor position: (%d, %d)", x, y);
    
    // 更新VNC服务器报告的光标位置
    *currentMouseX = x;
    *currentMouseY = y;
    
    NSLog(@"🖱️ [ScrcpyVNCClient] Cursor position updated from server: (%d, %d)", x, y);
    return TRUE;
}

static inline char* VNCRuntimeGetPassword(rfbClient* cl, NSString* password) {
    NSLog(@"🔐 [ScrcpyVNCClient] GetPassword callback invoked");
    
    if (!password || password.length == 0) {
        NSLog(@"❌ [ScrcpyVNCClient] Password is empty for VNC authentication");
        return NULL;
    }
    
    size_t passwordLength = password.length + 1;
    char *passwordCStr = malloc(passwordLength);
    if (!passwordCStr) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to allocate memory for VNC password");
        return NULL;
    }
    
    strncpy(passwordCStr, password.UTF8String, passwordLength - 1);
    passwordCStr[passwordLength - 1] = '\0';
    passwordCStr[strcspn(passwordCStr, "\n")] = '\0';
    
    NSLog(@"🔐 [ScrcpyVNCClient] Password provided for VNC authentication");
    return passwordCStr;
}

static inline rfbCredential* VNCRuntimeGetCredential(rfbClient* cl, int credentialType, NSString* user, NSString* password) {
    NSLog(@"🔐 [ScrcpyVNCClient] GetCredential callback invoked, type: %d", credentialType);
    
    rfbCredential *c = malloc(sizeof(rfbCredential));
    if (!c) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to allocate memory for VNC credential");
        return NULL;
    }
    
    if (credentialType != rfbCredentialTypeUser) {
        NSLog(@"❌ [ScrcpyVNCClient] Unsupported credential type: %d", credentialType);
        free(c);
        return NULL;
    }
    
    // 分配并复制用户名
    c->userCredential.username = malloc(RFB_BUF_SIZE);
    if (!c->userCredential.username) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to allocate memory for VNC username");
        free(c);
        return NULL;
    }
    strncpy(c->userCredential.username, user ? user.UTF8String : "", RFB_BUF_SIZE - 1);
    c->userCredential.username[RFB_BUF_SIZE - 1] = '\0';
    
    // 分配并复制密码
    c->userCredential.password = malloc(RFB_BUF_SIZE);
    if (!c->userCredential.password) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to allocate memory for VNC password");
        free(c->userCredential.username);
        free(c);
        return NULL;
    }
    strncpy(c->userCredential.password, password ? password.UTF8String : "", RFB_BUF_SIZE - 1);
    c->userCredential.password[RFB_BUF_SIZE - 1] = '\0';

    NSLog(@"🔐 [ScrcpyVNCClient] VNC credentials prepared");

    // 移除尾随换行符
    c->userCredential.username[strcspn(c->userCredential.username, "\n")] = '\0';
    c->userCredential.password[strcspn(c->userCredential.password, "\n")] = '\0';

    return c;
}

// Public interface functions

void VNCRuntimeSetupGotFrameBufferUpdateCallback(rfbClient* client, SDL_Texture* sdlTexture, SDL_Renderer* sdlRenderer, SDL_Window* sdlWindow) {
    GetSet_GotFrameBufferUpdateBlockIMP(client, imp_implementationWithBlock(^void(rfbClient* cl, int x, int y, int w, int h){
        VNCRuntimeGotFrameBufferUpdate(cl, x, y, w, h, sdlTexture, sdlRenderer, sdlWindow);
    }));
}

void VNCRuntimeSetupHandleCursorPosCallback(rfbClient* client, int* currentMouseX, int* currentMouseY) {
    GetSet_HandleCursorPosBlockIMP(client, imp_implementationWithBlock(^rfbBool(rfbClient* cl, int x, int y){
        return VNCRuntimeHandleCursorPos(cl, x, y, currentMouseX, currentMouseY);
    }));
}

void VNCRuntimeSetupGetPasswordCallback(rfbClient* client, NSString* password) {
    GetSet_GetPasswordBlockIMP(client, imp_implementationWithBlock(^char *(rfbClient* cl){
        return VNCRuntimeGetPassword(cl, password);
    }));
}

void VNCRuntimeSetupGetCredentialCallback(rfbClient* client, NSString* user, NSString* password) {
    GetSet_GetCredentialBlockIMP(client, imp_implementationWithBlock(^rfbCredential *(rfbClient* cl, int credentialType){
        return VNCRuntimeGetCredential(cl, credentialType, user, password);
    }));
}

void VNCRuntimeCleanupCallbacks(rfbClient* client) {
    GetSet_GetCredentialBlockIMP(client, nil);
    GetSet_GotFrameBufferUpdateBlockIMP(client, nil);
    GetSet_HandleCursorPosBlockIMP(client, nil);
    GetSet_GetPasswordBlockIMP(client, nil);
}

// 光标尺寸常量定义 - 支持Retina显示
static const int CURSOR_TEXTURE_SIZE = 128;      // 光标纹理尺寸（Retina）
static const int CURSOR_BASE_SIZE = 5;           // 光标基础显示尺寸（8的2/3约等于5）
static const int CURSOR_RADIUS = 12;             // 光标圆点半径（在128x128纹理中）
static const int CURSOR_BORDER_WIDTH = 4;        // 光标白色边框宽度（增加以改善锐度）
static const int CURSOR_MIN_SIZE = 10;            // 光标最小显示尺寸
static const int CURSOR_MAX_SIZE = 10;           // 光标最大显示尺寸


// 全局光标纹理变量
static SDL_Texture* g_cursorTexture = NULL;
static SDL_Renderer* g_cursorRenderer = NULL;



typedef struct {
    SDL_Texture* texture;
    int width, height;
    float alpha;
} CustomCursor;

static CustomCursor* createCustomCursor(SDL_Renderer* renderer) {
    CustomCursor* cursor = malloc(sizeof(CustomCursor));
    if (!cursor) return NULL;
    
    // 创建光标纹理
    SDL_Surface* surface = SDL_CreateRGBSurface(0, CURSOR_TEXTURE_SIZE, CURSOR_TEXTURE_SIZE, 32, 
        0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);
    
    if (!surface) {
        free(cursor);
        return NULL;
    }
    
    // 清空背景（透明）
    SDL_FillRect(surface, NULL, SDL_MapRGBA(surface->format, 0, 0, 0, 0));
    
    Uint32* pixels = (Uint32*)surface->pixels;
    const int size = CURSOR_TEXTURE_SIZE;
    const int centerX = size / 2;  // 中心点 X 坐标
    const int centerY = size / 2;  // 中心点 Y 坐标
    const int radius = CURSOR_RADIUS;
    
    // 绘制高质量抗锯齿圆形光标
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            // 使用子像素采样进行抗锯齿处理
            float totalAlpha = 0.0f;
            float totalWhiteAlpha = 0.0f;
            const int samples = 4; // 2x2子像素采样
            
            for (int sy = 0; sy < samples; sy++) {
                for (int sx = 0; sx < samples; sx++) {
                    // 计算子像素位置
                    float subX = x + (sx + 0.5f) / samples - 0.5f;
                    float subY = y + (sy + 0.5f) / samples - 0.5f;
                    
                    // 计算到圆心的距离
                    float dx = subX - centerX;
                    float dy = subY - centerY;
                    float distance = sqrtf(dx * dx + dy * dy);
                    
                    // 内圆（黑色部分）- 使用平滑过渡
                    float innerRadius = radius - CURSOR_BORDER_WIDTH;
                    if (distance <= innerRadius) {
                        totalAlpha += 1.0f;
                    } else if (distance <= innerRadius + 1.0f) {
                        // 内圆边缘的平滑过渡
                        totalAlpha += (innerRadius + 1.0f - distance);
                    }
                    
                    // 外圆（白色边框）- 使用平滑过渡
                    float outerRadius = radius + CURSOR_BORDER_WIDTH;
                    if (distance >= radius - 0.5f && distance <= outerRadius) {
                        if (distance <= radius + 0.5f) {
                            // 边框内侧的平滑过渡
                            totalWhiteAlpha += 1.0f;
                        } else if (distance <= outerRadius) {
                            // 边框外侧的平滑过渡
                            totalWhiteAlpha += (outerRadius - distance) / CURSOR_BORDER_WIDTH;
                        }
                    }
                }
            }
            
            // 计算最终的alpha值
            totalAlpha /= (samples * samples);
            totalWhiteAlpha /= (samples * samples);
            
            // 应用颜色
            if (totalAlpha > 0.0f) {
                // 黑色圆心
                int alpha = (int)(255 * totalAlpha);
                if (alpha > 255) alpha = 255;
                pixels[y * size + x] = SDL_MapRGBA(surface->format, 0, 0, 0, alpha);
            } else if (totalWhiteAlpha > 0.0f) {
                // 白色边框
                int alpha = (int)(200 * totalWhiteAlpha); // 稍微降低白色边框的不透明度
                if (alpha > 200) alpha = 200;
                pixels[y * size + x] = SDL_MapRGBA(surface->format, 255, 255, 255, alpha);
            }
        }
    }
    
    cursor->texture = SDL_CreateTextureFromSurface(renderer, surface);
    SDL_SetTextureBlendMode(cursor->texture, SDL_BLENDMODE_BLEND);
    
    cursor->width = CURSOR_TEXTURE_SIZE;
    cursor->height = CURSOR_TEXTURE_SIZE;
    cursor->alpha = 1.0f;
    
    SDL_FreeSurface(surface);
    return cursor;
}

static void freeCustomCursor(CustomCursor* cursor) {
    if (cursor) {
        if (cursor->texture) {
            SDL_DestroyTexture(cursor->texture);
        }
        free(cursor);
    }
}

void VNCRuntimeDrawMacOSCursor(SDL_Renderer* renderer, int x, int y, float scale) {
    if (!renderer) return;
    
    // 确保光标纹理已创建
    if (!g_cursorTexture || g_cursorRenderer != renderer) {
        if (g_cursorTexture && g_cursorRenderer != renderer) {
            SDL_DestroyTexture(g_cursorTexture);
            g_cursorTexture = NULL;
        }
        
        CustomCursor* cursor = createCustomCursor(renderer);
        if (cursor) {
            g_cursorTexture = cursor->texture;
            g_cursorRenderer = renderer;
            // 不释放纹理，只释放结构体
            free(cursor);
        }
    }
    
    if (!g_cursorTexture) return;
    
    // 获取设备缩放因子以支持Retina显示
    float deviceScale = [[UIScreen mainScreen] nativeScale];
    
    // 使用固定光标尺寸，不受内容缩放影响
    // 这样光标在任何缩放级别下都保持相同的视觉大小，便于用户识别和使用
    int cursorSize = (int)(CURSOR_BASE_SIZE * deviceScale); // 只应用设备缩放以支持Retina
    
    // 确保光标尺寸在合理范围内（现在最小和最大值相同，保持固定尺寸）
    if (cursorSize < (int)(CURSOR_MIN_SIZE * deviceScale)) cursorSize = (int)(CURSOR_MIN_SIZE * deviceScale);
    if (cursorSize > (int)(CURSOR_MAX_SIZE * deviceScale)) cursorSize = (int)(CURSOR_MAX_SIZE * deviceScale);
    
    // 设置透明度
    SDL_SetTextureAlphaMod(g_cursorTexture, (Uint8)(255));
    
    // 圆形光标热点在中心位置
    SDL_Rect destRect = {
        x - cursorSize / 2,  // 圆心对准实际点击位置
        y - cursorSize / 2,  // 圆心对准实际点击位置
        cursorSize,
        cursorSize
    };
    
    // 应用最高质量渲染选项以减少锯齿
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "best");
    SDL_SetHint(SDL_HINT_RENDER_VSYNC, "1");
    
    // 使用高质量纹理过滤
    SDL_SetTextureScaleMode(g_cursorTexture, SDL_ScaleModeLinear);
    
    SDL_RenderCopy(renderer, g_cursorTexture, NULL, &destRect);
    
    // 可选：添加调试信息显示当前鼠标位置（仅在调试模式下）
    #ifdef DEBUG_CURSOR
    SDL_SetRenderDrawColor(renderer, 255, 0, 0, 128);
    SDL_Rect debugPoint = {x - 1, y - 1, 2, 2};
    SDL_RenderFillRect(renderer, &debugPoint);
    #endif
}

// 光标边缘跟随逻辑实现 - 支持连续平滑移动并检测移动方向
static void VNCRuntimeCheckCursorEdgeFollow(ScrcpyVNCClient* vncClient, int screenMouseX, int screenMouseY, 
                                          int renderWidth, int renderHeight, int* offsetX, int* offsetY,
                                          int scaledWidth, int scaledHeight, int textureWidth, int textureHeight, float finalScale) {
    
    // 只有在内容被放大（scaledWidth > renderWidth 或 scaledHeight > renderHeight）时才需要边缘跟随
    if (scaledWidth <= renderWidth && scaledHeight <= renderHeight) {
        // 重置上一帧位置
        g_lastScreenMouseX = screenMouseX;
        g_lastScreenMouseY = screenMouseY;
        return; // 内容完全可见，无需跟随
    }
    
    // 计算鼠标移动方向
    int mouseDeltaX = 0;
    int mouseDeltaY = 0;
    
    if (g_lastScreenMouseX >= 0 && g_lastScreenMouseY >= 0) {
        mouseDeltaX = screenMouseX - g_lastScreenMouseX;
        mouseDeltaY = screenMouseY - g_lastScreenMouseY;
    }
    
    // 详细日志：当前鼠标状态
    NSLog(@"🔍 [EdgeFollow] Mouse position: (%d,%d), last: (%d,%d), delta: (%d,%d)", 
          screenMouseX, screenMouseY, g_lastScreenMouseX, g_lastScreenMouseY, mouseDeltaX, mouseDeltaY);
    NSLog(@"🔍 [EdgeFollow] Screen size: %dx%d, Content size: %dx%d, Offset: (%d,%d)", 
          renderWidth, renderHeight, scaledWidth, scaledHeight, *offsetX, *offsetY);
    
    // 标记是否需要更新视图
    BOOL needsUpdate = NO;
    int newOffsetX = *offsetX;
    int newOffsetY = *offsetY;
    
    // 检查水平边缘跟随 - 连续性移动且考虑移动方向
    if (scaledWidth > renderWidth) {
        // 详细分析左边缘条件
        BOOL leftEdgeInThreshold = (screenMouseX < CURSOR_EDGE_THRESHOLD);
        BOOL leftCanMoveRight = (newOffsetX < 0);
        BOOL leftMovingTowardEdge = (mouseDeltaX <= 0);
        
        NSLog(@"🔍 [EdgeFollow] LEFT conditions: inThreshold=%d (x=%d<%d), canMove=%d (offset=%d<0), movingToward=%d (delta=%d<=0)", 
              leftEdgeInThreshold, screenMouseX, CURSOR_EDGE_THRESHOLD, leftCanMoveRight, newOffsetX, leftMovingTowardEdge, mouseDeltaX);
        
        if (leftEdgeInThreshold && leftCanMoveRight && leftMovingTowardEdge) {
            // 计算距离边缘的比例，越近移动越快
            // 对于负值坐标，使用绝对值计算距离比例
            float edgeDistance = (screenMouseX < 0) ? (float)(-screenMouseX) : (float)(CURSOR_EDGE_THRESHOLD - screenMouseX);
            float edgeRatio = MIN(1.0f, edgeDistance / CURSOR_EDGE_THRESHOLD);
            edgeRatio = powf(edgeRatio, CURSOR_FOLLOW_ACCELERATION); // 应用加速
            
            int moveDistance = (int)(CURSOR_FOLLOW_SPEED * edgeRatio);
            newOffsetX = MIN(0, newOffsetX + moveDistance);
            needsUpdate = YES;
            
            NSLog(@"🔄 [VNCRuntime] ✅ LEFT edge follow triggered: edgeRatio=%.2f, moving view right by %d", 
                  edgeRatio, moveDistance);
        } else {
            NSLog(@"🔍 [EdgeFollow] ❌ LEFT edge follow NOT triggered");
        }
        
        // 详细分析右边缘条件
        BOOL rightEdgeInThreshold = (screenMouseX > (renderWidth - CURSOR_EDGE_THRESHOLD));
        BOOL rightCanMoveLeft = ((newOffsetX + scaledWidth) > renderWidth);
        BOOL rightMovingTowardEdge = (mouseDeltaX >= 0);
        
        NSLog(@"🔍 [EdgeFollow] RIGHT conditions: inThreshold=%d (x=%d>%d), canMove=%d (%d+%d>%d), movingToward=%d (delta=%d>=0)", 
              rightEdgeInThreshold, screenMouseX, (renderWidth - CURSOR_EDGE_THRESHOLD), 
              rightCanMoveLeft, newOffsetX, scaledWidth, renderWidth, rightMovingTowardEdge, mouseDeltaX);
        
        if (rightEdgeInThreshold && rightCanMoveLeft && rightMovingTowardEdge) {
            // 计算距离边缘的比例，越近移动越快
            float edgeRatio = ((float)(screenMouseX - (renderWidth - CURSOR_EDGE_THRESHOLD))) / CURSOR_EDGE_THRESHOLD;
            edgeRatio = powf(edgeRatio, CURSOR_FOLLOW_ACCELERATION); // 应用加速
            
            int moveDistance = (int)(CURSOR_FOLLOW_SPEED * edgeRatio);
            newOffsetX = MAX(renderWidth - scaledWidth, newOffsetX - moveDistance);
            needsUpdate = YES;
            
            NSLog(@"🔄 [VNCRuntime] ✅ RIGHT edge follow triggered: edgeRatio=%.2f, moving view left by %d", 
                  edgeRatio, moveDistance);
        } else {
            NSLog(@"🔍 [EdgeFollow] ❌ RIGHT edge follow NOT triggered");
        }
    }
    
    // 检查垂直边缘跟随 - 连续性移动且考虑移动方向
    if (scaledHeight > renderHeight) {
        // 详细分析上边缘条件
        BOOL topEdgeInThreshold = (screenMouseY < CURSOR_EDGE_THRESHOLD);
        BOOL topCanMoveDown = (newOffsetY < 0);
        BOOL topMovingTowardEdge = (mouseDeltaY <= 0);
        
        NSLog(@"🔍 [EdgeFollow] TOP conditions: inThreshold=%d (y=%d<%d), canMove=%d (offset=%d<0), movingToward=%d (delta=%d<=0)", 
              topEdgeInThreshold, screenMouseY, CURSOR_EDGE_THRESHOLD, topCanMoveDown, newOffsetY, topMovingTowardEdge, mouseDeltaY);
        
        if (topEdgeInThreshold && topCanMoveDown && topMovingTowardEdge) {
            // 计算距离边缘的比例，越近移动越快
            // 对于负值坐标，使用绝对值计算距离比例
            float edgeDistance = (screenMouseY < 0) ? (float)(-screenMouseY) : (float)(CURSOR_EDGE_THRESHOLD - screenMouseY);
            float edgeRatio = MIN(1.0f, edgeDistance / CURSOR_EDGE_THRESHOLD);
            edgeRatio = powf(edgeRatio, CURSOR_FOLLOW_ACCELERATION); // 应用加速
            
            int moveDistance = (int)(CURSOR_FOLLOW_SPEED * edgeRatio);
            newOffsetY = MIN(0, newOffsetY + moveDistance);
            needsUpdate = YES;
            
            NSLog(@"🔄 [VNCRuntime] ✅ TOP edge follow triggered: edgeRatio=%.2f, moving view down by %d", 
                  edgeRatio, moveDistance);
        } else {
            NSLog(@"🔍 [EdgeFollow] ❌ TOP edge follow NOT triggered");
        }
        
        // 详细分析下边缘条件
        BOOL bottomEdgeInThreshold = (screenMouseY > (renderHeight - CURSOR_EDGE_THRESHOLD));
        BOOL bottomCanMoveUp = ((newOffsetY + scaledHeight) > renderHeight);
        BOOL bottomMovingTowardEdge = (mouseDeltaY >= 0);
        
        NSLog(@"🔍 [EdgeFollow] BOTTOM conditions: inThreshold=%d (y=%d>%d), canMove=%d (%d+%d>%d), movingToward=%d (delta=%d>=0)", 
              bottomEdgeInThreshold, screenMouseY, (renderHeight - CURSOR_EDGE_THRESHOLD), 
              bottomCanMoveUp, newOffsetY, scaledHeight, renderHeight, bottomMovingTowardEdge, mouseDeltaY);
        
        if (bottomEdgeInThreshold && bottomCanMoveUp && bottomMovingTowardEdge) {
            // 计算距离边缘的比例，越近移动越快
            float edgeRatio = ((float)(screenMouseY - (renderHeight - CURSOR_EDGE_THRESHOLD))) / CURSOR_EDGE_THRESHOLD;
            edgeRatio = powf(edgeRatio, CURSOR_FOLLOW_ACCELERATION); // 应用加速
            
            int moveDistance = (int)(CURSOR_FOLLOW_SPEED * edgeRatio);
            newOffsetY = MAX(renderHeight - scaledHeight, newOffsetY - moveDistance);
            needsUpdate = YES;
            
            NSLog(@"🔄 [VNCRuntime] ✅ BOTTOM edge follow triggered: edgeRatio=%.2f, moving view up by %d", 
                  edgeRatio, moveDistance);
        } else {
            NSLog(@"🔍 [EdgeFollow] ❌ BOTTOM edge follow NOT triggered");
        }
    }
    
    // 如果需要更新，应用新的偏移量
    if (needsUpdate) {
        *offsetX = newOffsetX;
        *offsetY = newOffsetY;
        
        NSLog(@"🔄 [VNCRuntime] View offset smoothly updated to (%d, %d) due to cursor edge follow", newOffsetX, newOffsetY);
    }
    
    // 更新上一帧位置 - 移到函数末尾确保delta计算正确
    g_lastScreenMouseX = screenMouseX;
    g_lastScreenMouseY = screenMouseY;
}

// 设置鼠标移动标记的函数，供外部调用
void VNCRuntimeSetMouseMoved(void) {
    g_mouseMovedThisFrame = YES;
    g_mouseIsMoving = YES;
    g_mouseStopCounter = 0;  // 重置停止计数器
    g_mouseJustStopped = NO; // 重置刚停止标记（鼠标重新开始移动）
    NSLog(@"🖱️ [MouseMoved] Flag set from drag handler - IsMoving: YES, reset justStopped");
}

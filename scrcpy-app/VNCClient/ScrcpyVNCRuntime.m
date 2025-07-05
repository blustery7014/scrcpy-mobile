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
    
    // 计算偏移量，考虑缩放中心
    int centerX = (int)(renderWidth * zoomCenterX);
    int centerY = (int)(renderHeight * zoomCenterY);
    
    int offsetX = centerX - (int)(scaledWidth * zoomCenterX);
    int offsetY = centerY - (int)(scaledHeight * zoomCenterY);
    
    // 边界检查
    if (scaledWidth <= renderWidth) {
        // 如果缩放后内容小于等于屏幕，居中显示
        offsetX = (renderWidth - scaledWidth) / 2;
    } else {
        // 如果缩放后内容大于屏幕，限制边界
        if (offsetX > 0) offsetX = 0;  // 不能超出左边界
        if (offsetX + scaledWidth < renderWidth) offsetX = renderWidth - scaledWidth;  // 不能超出右边界
    }
    
    if (scaledHeight <= renderHeight) {
        // 如果缩放后内容小于等于屏幕，居中显示
        offsetY = (renderHeight - scaledHeight) / 2;
    } else {
        // 如果缩放后内容大于屏幕，限制边界
        if (offsetY > 0) offsetY = 0;  // 不能超出上边界
        if (offsetY + scaledHeight < renderHeight) offsetY = renderHeight - scaledHeight;  // 不能超出下边界
    }
    
    SDL_Rect dstRect = {offsetX, offsetY, scaledWidth, scaledHeight};
    
    NSLog(@"[VNCScreenDebug] BaseScale: %.3f, UserZoom: %.2f, FinalScale: %.3f, Scaled: %dx%d, Offset: %d,%d", 
          baseScale, userZoomScale, finalScale, scaledWidth, scaledHeight, offsetX, offsetY);
    NSLog(@"[VNCScreenDebug] ZoomCenter: (%.3f, %.3f), ScreenCenter: (%d, %d)", 
          zoomCenterX, zoomCenterY, centerX, centerY);
    
    // 清除渲染器并绘制纹理（居中并保持比例）
    SDL_SetRenderDrawColor(sdlRenderer, 0, 0, 0, 255);
    SDL_RenderClear(sdlRenderer);
    SDL_RenderCopy(sdlRenderer, sdlTexture, NULL, &dstRect);
    
    // 绘制鼠标光标（已经获取了vncClient）
    if (vncClient && cl->appData.useRemoteCursor) {
        // 将远程鼠标坐标转换为屏幕坐标
        int remoteMouseX = vncClient.currentMouseX;
        int remoteMouseY = vncClient.currentMouseY;
        
        // 转换坐标：从远程屏幕坐标到本地屏幕坐标（考虑用户缩放）
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
    SDL_Surface* surface = SDL_CreateRGBSurface(0, 32, 32, 32, 
        0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);
    
    if (!surface) {
        free(cursor);
        return NULL;
    }
    
    // 清空背景（透明）
    SDL_FillRect(surface, NULL, SDL_MapRGBA(surface->format, 0, 0, 0, 0));
    
    Uint32* pixels = (Uint32*)surface->pixels;
    const int size = 32;
    const int centerX = size / 2;  // 中心点 X 坐标
    const int centerY = size / 2;  // 中心点 Y 坐标
    const int radius = 6;          // 圆点半径
    
    // 绘制黑色圆形光标
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            // 计算到圆心的距离
            int dx = x - centerX;
            int dy = y - centerY;
            double distance = sqrt(dx * dx + dy * dy);
            
            if (distance <= radius) {
                // 在圆内 - 绘制黑色
                if (distance <= radius - 1) {
                    // 内部：纯黑色
                    pixels[y * size + x] = SDL_MapRGBA(surface->format, 0, 0, 0, 255);
                } else {
                    // 边缘：添加轻微的抗锯齿效果
                    int alpha = (int)(255 * (radius - distance));
                    if (alpha > 255) alpha = 255;
                    if (alpha < 0) alpha = 0;
                    pixels[y * size + x] = SDL_MapRGBA(surface->format, 0, 0, 0, alpha);
                }
            } else if (distance <= radius + 1) {
                // 外边缘：白色边框用于提高可见性
                int alpha = (int)(128 * (radius + 1 - distance));
                if (alpha > 128) alpha = 128;
                if (alpha < 0) alpha = 0;
                pixels[y * size + x] = SDL_MapRGBA(surface->format, 255, 255, 255, alpha);
            }
        }
    }
    
    cursor->texture = SDL_CreateTextureFromSurface(renderer, surface);
    SDL_SetTextureBlendMode(cursor->texture, SDL_BLENDMODE_BLEND);
    
    cursor->width = 32;
    cursor->height = 32;
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
    
    // 计算光标尺寸 - 基于32x32基础尺寸的圆形光标
    const int baseSize = 16; // 基础尺寸适合圆形光标
    int cursorSize = (int)(baseSize * scale);
    
    // 确保光标尺寸在合理范围内
    if (cursorSize < 8) cursorSize = 8;
    if (cursorSize > 32) cursorSize = 32;
    
    // 设置透明度
    SDL_SetTextureAlphaMod(g_cursorTexture, (Uint8)(255));
    
    // 圆形光标热点在中心位置
    SDL_Rect destRect = {
        x - cursorSize / 2,  // 圆心对准实际点击位置
        y - cursorSize / 2,  // 圆心对准实际点击位置
        cursorSize,
        cursorSize
    };
    
    // 应用高质量渲染选项
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "best");
    
    SDL_RenderCopy(renderer, g_cursorTexture, NULL, &destRect);
    
    // 可选：添加调试信息显示当前鼠标位置（仅在调试模式下）
    #ifdef DEBUG_CURSOR
    SDL_SetRenderDrawColor(renderer, 255, 0, 0, 128);
    SDL_Rect debugPoint = {x - 1, y - 1, 2, 2};
    SDL_RenderFillRect(renderer, &debugPoint);
    #endif
}

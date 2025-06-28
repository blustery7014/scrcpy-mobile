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
    
    // 使用渲染尺寸计算缩放
    float scaleX = (float)renderWidth / textureWidth;
    float scaleY = (float)renderHeight / textureHeight;
    float scale = fminf(scaleX, scaleY);
    
    int scaledWidth = (int)(textureWidth * scale);
    int scaledHeight = (int)(textureHeight * scale);
    
    int offsetX = (renderWidth - scaledWidth) / 2;
    int offsetY = (renderHeight - scaledHeight) / 2;
    
    SDL_Rect dstRect = {offsetX, offsetY, scaledWidth, scaledHeight};
    
    NSLog(@"[VNCScreenDebug] RenderScale: %.3f, Scaled: %dx%d, Offset: %d,%d", 
          scale, scaledWidth, scaledHeight, offsetX, offsetY);
    NSLog(@"[VNCScreenDebug] Expected offset calculation: (%d-%d)/2=%d, (%d-%d)/2=%d", 
          renderWidth, scaledWidth, (renderWidth-scaledWidth)/2, 
          renderHeight, scaledHeight, (renderHeight-scaledHeight)/2);
    
    // 清除渲染器并绘制纹理（居中并保持比例）
    SDL_SetRenderDrawColor(sdlRenderer, 0, 0, 0, 255);
    SDL_RenderClear(sdlRenderer);
    SDL_RenderCopy(sdlRenderer, sdlTexture, NULL, &dstRect);
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

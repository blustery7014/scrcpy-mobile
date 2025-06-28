//
//  ScrcpyVNCClient.m
//  VNCClient
//
//  Created by Ethan on 6/28/25.
//

#import "ScrcpyVNCClient.h"
#import "ScrcpyBlockWrapper.h"
#import "ScrcpyCommon.h"
#import "ScrcpyConstants.h"
#import <SDL2/SDL.h>
#import <rfb/rfbclient.h>
#import <rfb/keysym.h>
#import <stdlib.h>
#import <arpa/inet.h>
#import <objc/runtime.h>


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


@interface ScrcpyVNCClient () <ScrcpyClientProtocol>

@property (nonatomic, strong) SDLUIKitDelegate *sdlDelegate;
@property (nonatomic, copy) void (^sessionCompletion)(enum ScrcpyStatus, NSString *);
@property (nonatomic, copy) NSDictionary *sessionArguments;

// VNC客户端状态
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) rfbClient *rfbClient;
@property (nonatomic, assign) enum ScrcpyStatus scrcpyStatus;

// VNC远程桌面的图像像素大小
@property (nonatomic, assign) CGSize imagePixelsSize;

// SDL渲染对象
@property (nonatomic, assign) SDL_Renderer *currentRenderer;
@property (nonatomic, assign) SDL_Texture *currentTexture;

@end

@implementation ScrcpyVNCClient

- (instancetype)init {
    self = [super init];
    if (self) {
        self.sdlDelegate = [[SDLUIKitDelegate alloc] init];
        self.imagePixelsSize = CGSizeZero;
        self.currentRenderer = NULL;
        self.currentTexture = NULL;
        self.connected = NO;
        self.scrcpyStatus = ScrcpyStatusDisconnected;
        
        // 监听断开连接通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDisconnectRequest:)
                                                     name:@"ScrcpyRequestDisconnectNotification"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopVNC];
}

- (UIWindowScene *)currentScene {
    for (UIWindowScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            return scene;
        }
    }
    return nil;
}

#pragma mark - VNC消息循环

- (void)vncMessageLoop {
    // 确保在后台线程中运行
    if ([NSThread isMainThread]) {
        NSLog(@"🔌 [ScrcpyVNCClient] vncMessageLoop called from main thread, switching to background thread");
        [NSThread detachNewThreadSelector:@selector(vncMessageLoop) toTarget:self withObject:nil];
        return;
    }
    
    while (self.connected) {
        int i = WaitForMessage(self.rfbClient, 500);
        
        if (i < 0) {
            NSLog(@"🔌 [ScrcpyVNCClient] VNC message wait failed, breaking loop");
            self.connected = NO;
            self.scrcpyStatus = ScrcpyStatusDisconnected;
            ScrcpyUpdateStatus(ScrcpyStatusDisconnected, "VNC message wait failed");
            return;
        }
        
        if (!HandleRFBServerMessage(self.rfbClient)) {
            NSLog(@"🔌 [ScrcpyVNCClient] VNC server message handling failed, breaking loop");
            self.connected = NO;
            self.scrcpyStatus = ScrcpyStatusDisconnected;
            ScrcpyUpdateStatus(ScrcpyStatusDisconnected, "VNC server message handling failed");
            return;
        }
    }
}

#pragma mark - SDL事件循环

- (void)SDLEventLoop {
    // 运行一小段时间等待其他UI事件
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, NO);
    
    SDL_iPhoneSetEventPump(SDL_TRUE);
    SDL_Event e;

    while (self.connected) {
        if (!SDL_PollEvent(&e)) {
            SDL_Delay(1);
            continue;
        }
        
        switch (e.type) {
            case SDL_DISPLAYEVENT:
                NSLog(@"SDL_DISPLAYEVENT: display %d, event %d", e.display.display, e.display.event);
                break;
                
            case SDL_WINDOWEVENT:
                switch (e.window.event) {
                    case SDL_WINDOWEVENT_EXPOSED:
                        if (self.rfbClient) {
                            SendFramebufferUpdateRequest(self.rfbClient, 0, 0, self.rfbClient->width, self.rfbClient->height, FALSE);
                        }
                        break;
                        
                    case SDL_WINDOWEVENT_RESIZED:
                        if (self.rfbClient) {
                            SendExtDesktopSize(self.rfbClient, e.window.data1, e.window.data2);
                        }
                        break;
                        
                    case SDL_WINDOWEVENT_FOCUS_GAINED:
                        if (SDL_HasClipboardText()) {
                            char *text = SDL_GetClipboardText();
                            if (text && self.rfbClient) {
                                rfbClientLog("sending clipboard text '%s'\n", text);
                                SendClientCutText(self.rfbClient, text, (int)strlen(text));
                                SDL_free(text);
                            }
                        }
                        break;
                        
                    case SDL_WINDOWEVENT_FOCUS_LOST:
                        NSLog(@"SDL_WINDOWEVENT_FOCUS_LOST");
                        break;
                }
                break;
                
            case SDL_QUIT:
                NSLog(@"🔌 [ScrcpyVNCClient] SDL_QUIT event received, breaking VNC loop");
                self.connected = NO;
                break;
                
            default:
                // 忽略其他事件，包括鼠标和键盘事件（由上层处理）
                break;
        }
    }

    // 清理VNC客户端
    if (self.rfbClient) {
        rfbClientCleanup(self.rfbClient);
        self.rfbClient = NULL;
    }
    
    // 清理block IMP
    GetSet_GetCredentialBlockIMP(self.rfbClient, nil);
    GetSet_GotFrameBufferUpdateBlockIMP(self.rfbClient, nil);
    
    // 退出SDL
    SDL_Quit();
    SDL_iPhoneSetEventPump(SDL_FALSE);

    NSLog(@"✅ [ScrcpyVNCClient] SDL main loop ended");
}

#pragma mark - VNC客户端主要方法

- (void)startWithArguments:(NSDictionary *)arguments completion:(void (^)(enum ScrcpyStatus, NSString *))completion {
    NSString *host = arguments[@"hostReal"];
    NSString *port = arguments[@"port"];
    NSString *user = arguments[@"vncOptions"][@"vncUser"];
    NSString *password = arguments[@"vncOptions"][@"vncPassword"];
    
    NSLog(@"✅ [ScrcpyVNCClient] Starting VNC client connection to %@:%@", host, port);
    
    // 保存完成回调
    self.sessionCompletion = completion;
    self.sessionArguments = arguments;
    
    // 模拟ApplicationDelegate方法
    [self.sdlDelegate application:[UIApplication sharedApplication] didFinishLaunchingWithOptions:@{}];

    // 初始化SDL
    SDL_Init(SDL_INIT_VIDEO);
    atexit(SDL_Quit);
    signal(SIGINT, exit);
    
    // 更新状态
    self.scrcpyStatus = ScrcpyStatusSDLInited;
    ScrcpyUpdateStatus(ScrcpyStatusSDLInited, "SDL initialized successfully");
    
    __block int sdlFlags = SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_FULLSCREEN;
    __block SDL_Texture *sdlTexture = NULL;
    __block SDL_Renderer *sdlRenderer = NULL;
    __block SDL_Window *sdlWindow = nil;

    // 初始化VNC客户端
    self.rfbClient = rfbGetClient(8, 3, 4);
    self.rfbClient->canHandleNewFBSize = true;
    self.rfbClient->listenPort = LISTEN_PORT_OFFSET;
    self.rfbClient->listen6Port = LISTEN_PORT_OFFSET;
    
    // 设置帧缓冲区分配回调
    GetSet_MallocFrameBufferBlockIMP(self.rfbClient, imp_implementationWithBlock(^rfbBool(rfbClient* client){
        int width = client->width, height = client->height, depth = client->format.bitsPerPixel;

        // 保存原始尺寸（仅在第一次时保存）
        if (self.imagePixelsSize.width == 0 && self.imagePixelsSize.height == 0) {
            self.imagePixelsSize = CGSizeMake(width, height);
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
        sdlWindow = SDL_CreateWindow(client->desktopName,
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
        SDL_GetWindowSize(sdlWindow, &actualWidth, &actualHeight);
        NSLog(@"[VNCScreenDebug] Actual SDL window size: %dx%d", actualWidth, actualHeight);
        
        // 检查窗口标志
        Uint32 windowFlags = SDL_GetWindowFlags(sdlWindow);
        NSLog(@"[VNCScreenDebug] Window flags: 0x%x (fullscreen: %s)", 
              windowFlags, (windowFlags & SDL_WINDOW_FULLSCREEN) ? "YES" : "NO");

        // 更新状态
        self.scrcpyStatus = ScrcpyStatusSDLWindowCreated;
        ScrcpyUpdateStatus(ScrcpyStatusSDLWindowCreated, "SDL window created successfully");

        // 创建渲染器
        sdlRenderer = SDL_CreateRenderer(sdlWindow, -1, SDL_RENDERER_ACCELERATED);
        if (!sdlRenderer) {
            rfbClientErr("resize: error creating renderer: %s\n", SDL_GetError());
            return FALSE;
        }
        SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");
        
        // 获取设备缩放因子并设置SDL渲染器缩放
        float deviceScale = UIScreen.mainScreen.nativeScale;
        NSLog(@"[VNCScreenDebug] Device scale factor: %.2f", deviceScale);
        SDL_RenderSetScale(sdlRenderer, deviceScale, deviceScale);
        
        // 保存渲染器
        self.currentRenderer = sdlRenderer;
        
        // 设置SDL窗口
        self.sdlDelegate.window.windowScene = self.currentScene;
        [self.sdlDelegate.window makeKeyWindow];

        // 创建纹理
        sdlTexture = SDL_CreateTexture(sdlRenderer, SDL_PIXELFORMAT_ARGB8888,
                                       SDL_TEXTUREACCESS_STREAMING, width, height);
        
        if (!sdlTexture) {
            rfbClientErr("resize: error creating texture: %s\n", SDL_GetError());
            return FALSE;
        }
        
        // 保存纹理
        self.currentTexture = sdlTexture;
        
        return TRUE;
    }));
    self.rfbClient->MallocFrameBuffer = MallocFrameBufferBlock;
    
    // 设置帧缓冲区更新回调
    self.rfbClient->GotFrameBufferUpdate = GotFrameBufferUpdateBlock;
    GetSet_GotFrameBufferUpdateBlockIMP(self.rfbClient, imp_implementationWithBlock(^void(rfbClient* cl, int x, int y, int w, int h){
        SDL_Surface *sdl = rfbClientGetClientData(cl, SDL_Init);
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
    }));
    
    // 设置认证回调
    self.rfbClient->GetPassword = GetPasswordBlock;
    GetSet_GetPasswordBlockIMP(self.rfbClient, imp_implementationWithBlock(^char *(rfbClient* cl){
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
    }));
    
    // 设置高级认证回调
    self.rfbClient->GetCredential = GetCredentialBlock;
    GetSet_GetCredentialBlockIMP(self.rfbClient, imp_implementationWithBlock(^rfbCredential *(rfbClient* cl, int credentialType){
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
    }));
    
    // 准备连接参数
    const char *argv[] = {"vnc", [NSString stringWithFormat:@"%@:%@", host, port].UTF8String};
    int argc = sizeof(argv) / sizeof(char *);
    
    // 更新状态为连接中
    self.scrcpyStatus = ScrcpyStatusConnecting;
    ScrcpyUpdateStatus(ScrcpyStatusConnecting, [[NSString stringWithFormat:@"Connecting to %@:%@", host, port] UTF8String]);
    
    // 初始化VNC客户端连接
    if (!rfbInitClient(self.rfbClient, &argc, (char **)argv)) {
        self.rfbClient = NULL;
        
        self.scrcpyStatus = ScrcpyStatusConnectingFailed;
        ScrcpyUpdateStatus(ScrcpyStatusConnectingFailed, [[NSString stringWithFormat:@"Failed to connect to VNC server %@:%@", host, port] UTF8String]);
        
        if (completion) {
            completion(ScrcpyStatusConnectingFailed, @"Failed to connect to VNC server");
        }
        return;
    }
    
    // 标记为已连接
    self.connected = YES;
    
    // 更新状态为已连接
    self.scrcpyStatus = ScrcpyStatusConnected;
    ScrcpyUpdateStatus(ScrcpyStatusConnected, "VNC client connected successfully");
    
    NSLog(@"✅ [ScrcpyVNCClient] VNC connection established successfully");
    
    // 请求初始帧缓冲更新
    if (self.rfbClient) {
        SendFramebufferUpdateRequest(self.rfbClient, 0, 0, self.rfbClient->width, self.rfbClient->height, FALSE);
    }
    
    if (completion) {
        completion(ScrcpyStatusConnected, @"VNC connected successfully");
    }
    
    // 在后台线程启动消息循环
    [self vncMessageLoop];

    // 启动SDL事件循环（异步，避免阻塞主线程）
    [self performSelector:@selector(SDLEventLoop) withObject:nil afterDelay:0];
}

- (void)stopVNC {
    NSLog(@"🔌 [ScrcpyVNCClient] stopVNC called");
    
    // 标记为断开连接
    self.connected = NO;
    
    // 更新状态
    self.scrcpyStatus = ScrcpyStatusDisconnected;
    ScrcpyUpdateStatus(ScrcpyStatusDisconnected, "VNC client disconnected");
    
    // 清理VNC客户端（在SDL事件循环中处理）
    
    NSLog(@"🔌 [ScrcpyVNCClient] VNC connection stopped");
}

#pragma mark - 通知处理

- (void)handleDisconnectRequest:(NSNotification *)notification {
    NSLog(@"🔔 [ScrcpyVNCClient] Received disconnect request notification");
    
    if (self.connected && self.scrcpyStatus != ScrcpyStatusDisconnected) {
        NSLog(@"🔌 [ScrcpyVNCClient] Stopping VNC connection due to disconnect request");
        [self stopVNC];
    } else {
        NSLog(@"ℹ️ [ScrcpyVNCClient] No active VNC connection to disconnect");
    }
}

@end

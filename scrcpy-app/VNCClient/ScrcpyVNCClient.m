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
#import "ScrcpyVNCRuntime.h"


@interface ScrcpyVNCClient () <ScrcpyClientProtocol>
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
        
        // 初始化鼠标坐标（屏幕中心）
        self.currentMouseX = 0;
        self.currentMouseY = 0;
        
        // 监听断开连接通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDisconnectRequest:)
                                                     name:@"ScrcpyRequestDisconnectNotification"
                                                   object:nil];
        
        // 监听VNC鼠标事件通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleVNCMouseEvent:)
                                                     name:kNotificationVNCMouseEvent
                                                   object:nil];
        
        // 监听VNC拖拽偏移量通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleVNCDragOffset:)
                                                     name:kNotificationVNCDragOffset
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
    
    // 清理VNC运行时回调
    VNCRuntimeCleanupCallbacks(self.rfbClient);
    
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
    
    __block SDL_Texture *sdlTexture = NULL;
    __block SDL_Renderer *sdlRenderer = NULL;
    __block SDL_Window *sdlWindow = nil;

    // 初始化VNC客户端
    self.rfbClient = rfbGetClient(8, 3, 4);
    self.rfbClient->canHandleNewFBSize = true;
    self.rfbClient->listenPort = LISTEN_PORT_OFFSET;
    self.rfbClient->listen6Port = LISTEN_PORT_OFFSET;
    // 使用远程指针:
    // - 不使用的话, 无法获取远程鼠标的位置变化, 导致发送点击事件时无法正确定位, 但好处是远程的鼠标指针会正确展示
    // - 使用的话, 可以正确获取鼠标位置, 但远程鼠标指针会被隐藏, 需要自己绘制
    self.rfbClient->appData.useRemoteCursor = SDL_TRUE;
    
    // 设置帧缓冲区分配回调
    GetSet_MallocFrameBufferBlockIMP(self.rfbClient, imp_implementationWithBlock(^rfbBool(rfbClient* client){
        return VNCRuntimeMallocFrameBuffer(client, self, &sdlWindow, &sdlRenderer, &sdlTexture);
    }));
    self.rfbClient->MallocFrameBuffer = MallocFrameBufferBlock;
    
    // 设置鼠标指针位置更新回调
    self.rfbClient->HandleCursorPos = HandleCursorPosBlock;
    VNCRuntimeSetupHandleCursorPosCallback(self.rfbClient, &_currentMouseX, &_currentMouseY);
    
    // 设置认证回调
    self.rfbClient->GetPassword = GetPasswordBlock;
    VNCRuntimeSetupGetPasswordCallback(self.rfbClient, password);
    
    // 设置高级认证回调
    self.rfbClient->GetCredential = GetCredentialBlock;
    VNCRuntimeSetupGetCredentialCallback(self.rfbClient, user, password);
    
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
    
    // 初始化鼠标坐标到屏幕中心（作为默认值）
    if (self.rfbClient) {
        self.currentMouseX = self.rfbClient->width / 2;
        self.currentMouseY = self.rfbClient->height / 2;
        NSLog(@"🐭 [ScrcpyVNCClient] Initialized default mouse position to center: (%d,%d)", self.currentMouseX, self.currentMouseY);
        
        // 请求当前光标位置（如果服务器支持）
        // 这将触发 GotCursorPos 回调来获取真实的光标位置
        if (self.rfbClient->canHandleNewFBSize) {
            NSLog(@"🔍 [ScrcpyVNCClient] Requesting current cursor position from VNC server");
        }
        
        // 发送一个轻微的鼠标移动来获取当前位置（某些VNC服务器需要这样做）
        SendPointerEvent(self.rfbClient, self.currentMouseX, self.currentMouseY, 0);
        
        // 延迟500ms后再次请求，确保服务器有时间响应
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (self.rfbClient && self.connected) {
                NSLog(@"🖱️ [ScrcpyVNCClient] Sending additional framebuffer update request for cursor");
                SendFramebufferUpdateRequest(self.rfbClient, 0, 0, self.rfbClient->width, self.rfbClient->height, TRUE);
            }
        });
    }
    
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

- (void)moveMouseToX:(int)x y:(int)y {
    if (!self.connected || !self.rfbClient) {
        NSLog(@"❌ [ScrcpyVNCClient] Cannot move mouse: VNC not connected");
        return;
    }
    
    // 确保坐标在远程屏幕范围内
    int maxX = self.rfbClient->width - 1;
    int maxY = self.rfbClient->height - 1;
    
    int clampedX = MAX(0, MIN(x, maxX));
    int clampedY = MAX(0, MIN(y, maxY));
    
    if (clampedX != x || clampedY != y) {
        NSLog(@"⚠️ [ScrcpyVNCClient] Mouse coordinates clamped from (%d,%d) to (%d,%d) for screen size %dx%d", 
              x, y, clampedX, clampedY, self.rfbClient->width, self.rfbClient->height);
    }
    
    // 发送鼠标指针事件到VNC服务器
    if (!SendPointerEvent(self.rfbClient, clampedX, clampedY, 0)) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send mouse move event to (%d,%d)", clampedX, clampedY);
        return;
    }
    
    // 更新存储的鼠标坐标
    self.currentMouseX = clampedX;
    self.currentMouseY = clampedY;
    
    NSLog(@"🐭 [ScrcpyVNCClient] Mouse moved to position (%d,%d)", clampedX, clampedY);
}

- (void)sendMouseClickAtX:(int)x y:(int)y isRightClick:(BOOL)isRightClick {
    if (!self.connected || !self.rfbClient) {
        NSLog(@"❌ [ScrcpyVNCClient] Cannot send mouse click: VNC not connected");
        return;
    }
    
    // 确保坐标在远程屏幕范围内
    int maxX = self.rfbClient->width - 1;
    int maxY = self.rfbClient->height - 1;
    
    int clampedX = MAX(0, MIN(x, maxX));
    int clampedY = MAX(0, MIN(y, maxY));
    
    if (clampedX != x || clampedY != y) {
        NSLog(@"⚠️ [ScrcpyVNCClient] Mouse click coordinates clamped from (%d,%d) to (%d,%d) for screen size %dx%d", 
              x, y, clampedX, clampedY, self.rfbClient->width, self.rfbClient->height);
    }
    
    // 确定鼠标按钮掩码
    int buttonMask = isRightClick ? rfbButton3Mask : rfbButton1Mask;
    
    // 发送鼠标按下事件
    if (!SendPointerEvent(self.rfbClient, clampedX, clampedY, buttonMask)) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send mouse button down event");
        return;
    }
    
    // 发送鼠标松开事件
    if (!SendPointerEvent(self.rfbClient, clampedX, clampedY, 0)) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send mouse button up event");
        return;
    }
    
    NSLog(@"🖱️ [ScrcpyVNCClient] %@ mouse click sent at position (%d,%d)", 
          isRightClick ? @"Right" : @"Left", clampedX, clampedY);
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

- (void)handleVNCMouseEvent:(NSNotification *)notification {
    if (!self.connected || !self.rfbClient) {
        NSLog(@"❌ [ScrcpyVNCClient] Cannot handle mouse event: VNC not connected");
        return;
    }
    
    NSDictionary *userInfo = notification.userInfo;
    if (!userInfo) {
        NSLog(@"❌ [ScrcpyVNCClient] Mouse event notification missing userInfo");
        return;
    }
    
    NSString *eventType = userInfo[kKeyType];
    
    if (!eventType) {
        NSLog(@"❌ [ScrcpyVNCClient] Mouse event notification missing event type");
        return;
    }
    
    NSLog(@"🎯 [ScrcpyVNCClient] Mouse event: %@, using stored coordinates: (%d,%d) on %dx%d screen", 
          eventType, self.currentMouseX, self.currentMouseY, self.rfbClient->width, self.rfbClient->height);
    
    if ([eventType isEqualToString:kMouseEventTypeClick]) {
        // 处理点击事件 - 忽略传入的坐标，使用存储的鼠标坐标
        NSNumber *isRightClickNumber = userInfo[kKeyIsRightClick];
        BOOL isRightClick = [isRightClickNumber boolValue];
        
        [self sendMouseClickAtX:self.currentMouseX y:self.currentMouseY isRightClick:isRightClick];
    } else if ([eventType isEqualToString:kMouseEventTypeMove]) {
        // 处理鼠标移动事件 - 可以根据需要实现额外的鼠标移动逻辑
        // 这里可以添加基于其他输入源的鼠标移动逻辑
        NSLog(@"🐭 [ScrcpyVNCClient] Mouse move event received - current position maintained at (%d,%d)", 
              self.currentMouseX, self.currentMouseY);
    }
    // 其他事件类型（拖拽等）可以在此处添加处理
}

- (void)handleVNCDragOffset:(NSNotification *)notification {
    if (!self.connected || !self.rfbClient) {
        NSLog(@"❌ [ScrcpyVNCClient] Cannot handle drag offset: VNC not connected");
        return;
    }
    
    NSDictionary *userInfo = notification.userInfo;
    if (!userInfo) {
        NSLog(@"❌ [ScrcpyVNCClient] Drag offset notification missing userInfo");
        return;
    }
    
    NSValue *normalizedOffsetValue = userInfo[kKeyNormalizedOffset];
    NSValue *viewSizeValue = userInfo[kKeyViewSize];
    NSNumber *zoomScaleNumber = userInfo[kKeyZoomScale];
    
    if (!normalizedOffsetValue || !viewSizeValue) {
        NSLog(@"❌ [ScrcpyVNCClient] Drag offset notification missing required data");
        return;
    }
    
    CGPoint normalizedOffset = [normalizedOffsetValue CGPointValue];
    CGSize viewSize = [viewSizeValue CGSizeValue];
    CGFloat zoomScale = zoomScaleNumber ? [zoomScaleNumber floatValue] : 1.0;
    
    // 计算远程内容在本地屏幕上的实际显示比例
    // 这样可以保持拖拽距离与鼠标移动距离在视觉上的一致性
    
    // 获取远程屏幕尺寸
    int remoteWidth = self.rfbClient->width;
    int remoteHeight = self.rfbClient->height;
    
    // 计算远程内容在本地的显示缩放比例（保持宽高比）
    CGFloat scaleX = viewSize.width / (CGFloat)remoteWidth;
    CGFloat scaleY = viewSize.height / (CGFloat)remoteHeight;
    CGFloat displayScale = MIN(scaleX, scaleY);  // 取较小值保持比例
    
    // 计算远程内容在本地的实际显示尺寸
    CGFloat displayedRemoteWidth = remoteWidth * displayScale;
    CGFloat displayedRemoteHeight = remoteHeight * displayScale;
    
    // 计算拖拽偏移量相对于远程内容显示区域的比例
    CGFloat relativeOffsetX = (normalizedOffset.x * viewSize.width) / displayedRemoteWidth;
    CGFloat relativeOffsetY = (normalizedOffset.y * viewSize.height) / displayedRemoteHeight;
    
    // 考虑用户缩放倍数进行精细控制调整
    CGFloat finalOffsetX = relativeOffsetX / zoomScale;
    CGFloat finalOffsetY = relativeOffsetY / zoomScale;
    
    // 转换为远程屏幕像素偏移量
    int offsetX = (int)(finalOffsetX * remoteWidth);
    int offsetY = (int)(finalOffsetY * remoteHeight);
    
    // 计算新的鼠标位置
    int newMouseX = self.currentMouseX + offsetX;
    int newMouseY = self.currentMouseY + offsetY;
    
    NSLog(@"🎯 [ScrcpyVNCClient] Drag offset calculation:");
    NSLog(@"   Remote: %dx%d, View: %.0fx%.0f, DisplayScale: %.3f", 
          remoteWidth, remoteHeight, viewSize.width, viewSize.height, displayScale);
    NSLog(@"   DisplayedRemoteSize: %.1fx%.1f", displayedRemoteWidth, displayedRemoteHeight);
    NSLog(@"   Normalized: (%.3f,%.3f) -> Relative: (%.3f,%.3f) -> Final: (%.3f,%.3f) / Zoom: %.2f", 
          normalizedOffset.x, normalizedOffset.y, relativeOffsetX, relativeOffsetY, finalOffsetX, finalOffsetY, zoomScale);
    NSLog(@"   Pixel offset: (%d,%d), Mouse: (%d,%d) -> (%d,%d)", 
          offsetX, offsetY, self.currentMouseX, self.currentMouseY, newMouseX, newMouseY);
    
    // 移动鼠标到新位置
    [self moveMouseToX:newMouseX y:newMouseY];
}

@end

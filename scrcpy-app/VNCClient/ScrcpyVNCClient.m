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
        
        // 初始化滚动累积器和上一次偏移量
        self.scrollAccumulatorY = 0.0;
        self.lastScrollOffset = CGPointZero;
        
        // 初始化缩放相关属性
        self.currentZoomScale = 1.0;
        self.zoomCenterX = 0.5;
        self.zoomCenterY = 0.5;
        self.zoomUpdatePending = NO;
        
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
        
        // 监听VNC拖拽状态通知（用于记录拖拽开始位置）
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleVNCDragState:)
                                                     name:kNotificationVNCDrag
                                                   object:nil];
        
        // 监听VNC滚动事件通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleVNCScrollEvent:)
                                                     name:kNotificationVNCScrollEvent
                                                   object:nil];
        
        // 监听VNC缩放事件通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleVNCZoomEvent:)
                                                     name:@"ScrcpyVNCZoomNotification"
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
    
    // 直接将手势移动距离乘以远程桌面的缩放系数
    // 这样可以保持手势移动距离与远程鼠标移动距离的1:1对应关系
    
    // 获取远程屏幕尺寸
    int remoteWidth = self.rfbClient->width;
    int remoteHeight = self.rfbClient->height;
    
    // 计算远程内容在本地的显示缩放比例（保持宽高比）
    CGFloat scaleX = viewSize.width / (CGFloat)remoteWidth;
    CGFloat scaleY = viewSize.height / (CGFloat)remoteHeight;
    CGFloat displayScale = MIN(scaleX, scaleY);  // 取较小值保持比例
    
    // 将归一化偏移量转换为实际像素距离
    CGFloat pixelOffsetX = normalizedOffset.x * viewSize.width;
    CGFloat pixelOffsetY = normalizedOffset.y * viewSize.height;
    
    // 将手势移动距离乘以远程桌面的缩放系数（displayScale的倒数）
    // 这样手势在屏幕上移动的距离就等于远程鼠标移动的距离
    CGFloat remoteOffsetX = pixelOffsetX / displayScale;
    CGFloat remoteOffsetY = pixelOffsetY / displayScale;
    
    // 考虑用户缩放倍数进行精细控制调整
    CGFloat finalOffsetX = remoteOffsetX / zoomScale;
    CGFloat finalOffsetY = remoteOffsetY / zoomScale;
    
    // 转换为整数像素偏移量
    int offsetX = (int)round(finalOffsetX);
    int offsetY = (int)round(finalOffsetY);
    
    // 使用拖拽开始时的鼠标位置作为起点计算新的鼠标位置
    int newMouseX = self.dragStartMouseX + offsetX;
    int newMouseY = self.dragStartMouseY + offsetY;
    
    NSLog(@"🎯 [ScrcpyVNCClient] Drag offset calculation (1:1 scale):");
    NSLog(@"   Remote: %dx%d, View: %.0fx%.0f, DisplayScale: %.3f", 
          remoteWidth, remoteHeight, viewSize.width, viewSize.height, displayScale);
    NSLog(@"   Normalized: (%.3f,%.3f) -> Pixel: (%.1f,%.1f) -> Remote: (%.1f,%.1f) -> Final: (%.1f,%.1f) / Zoom: %.2f", 
          normalizedOffset.x, normalizedOffset.y, pixelOffsetX, pixelOffsetY, remoteOffsetX, remoteOffsetY, finalOffsetX, finalOffsetY, zoomScale);
    NSLog(@"   Pixel offset: (%d,%d), DragStart: (%d,%d) -> New: (%d,%d)", 
          offsetX, offsetY, self.dragStartMouseX, self.dragStartMouseY, newMouseX, newMouseY);
    
    // 移动鼠标到新位置
    [self moveMouseToX:newMouseX y:newMouseY];
}

- (void)handleVNCDragState:(NSNotification *)notification {
    if (!self.connected || !self.rfbClient) {
        NSLog(@"❌ [ScrcpyVNCClient] Cannot handle drag state: VNC not connected");
        return;
    }
    
    NSDictionary *userInfo = notification.userInfo;
    if (!userInfo) {
        NSLog(@"❌ [ScrcpyVNCClient] Drag state notification missing userInfo");
        return;
    }
    
    NSString *state = userInfo[kKeyState];
    if (!state) {
        NSLog(@"❌ [ScrcpyVNCClient] Drag state notification missing state");
        return;
    }
    
    if ([state isEqualToString:kDragStateBegan]) {
        // 拖拽开始时记录当前鼠标位置作为起点
        self.dragStartMouseX = self.currentMouseX;
        self.dragStartMouseY = self.currentMouseY;
        
        NSLog(@"🎯 [ScrcpyVNCClient] Drag began - recorded start position: (%d,%d)", 
              self.dragStartMouseX, self.dragStartMouseY);
    } else if ([state isEqualToString:kDragStateEnded] || [state isEqualToString:kDragStateCancelled]) {
        // 拖拽结束时可以进行清理（如果需要）
        NSLog(@"🎯 [ScrcpyVNCClient] Drag %@ - start position was: (%d,%d), final position: (%d,%d)", 
              state, self.dragStartMouseX, self.dragStartMouseY, self.currentMouseX, self.currentMouseY);
    }
}

- (void)handleVNCScrollEvent:(NSNotification *)notification {
    if (!self.connected || !self.rfbClient) {
        NSLog(@"❌ [ScrcpyVNCClient] Cannot handle scroll event: VNC not connected");
        return;
    }
    
    NSDictionary *userInfo = notification.userInfo;
    if (!userInfo) {
        NSLog(@"❌ [ScrcpyVNCClient] Scroll event notification missing userInfo");
        return;
    }
    
    NSString *state = userInfo[kKeyState];
    NSValue *offsetValue = userInfo[kKeyOffset];
    NSValue *viewSizeValue = userInfo[kKeyViewSize];
    NSNumber *zoomScaleNumber = userInfo[kKeyZoomScale];
    
    if (!state || !offsetValue || !viewSizeValue) {
        NSLog(@"❌ [ScrcpyVNCClient] Scroll event notification missing required data");
        return;
    }
    
    CGPoint offset = [offsetValue CGPointValue];
    CGSize viewSize = [viewSizeValue CGSizeValue];
    CGFloat zoomScale = zoomScaleNumber ? [zoomScaleNumber floatValue] : 1.0;
    
    if ([state isEqualToString:kDragStateBegan]) {
        // 滚动开始，记录起点位置并重置累积器
        self.dragStartMouseX = self.currentMouseX;
        self.dragStartMouseY = self.currentMouseY;
        self.scrollAccumulatorY = 0.0;  // 重置滚动累积器
        self.lastScrollOffset = CGPointZero;  // 重置上一次偏移量
        
        NSLog(@"📜 [ScrcpyVNCClient] Scroll began - recorded start position: (%d,%d), reset accumulator and last offset", 
              self.dragStartMouseX, self.dragStartMouseY);
    } else if ([state isEqualToString:kDragStateChanged]) {
        // 滚动过程中，计算滚动量并发送滚动事件
        [self sendMouseScrollWithOffset:offset viewSize:viewSize zoomScale:zoomScale];
    } else if ([state isEqualToString:kDragStateEnded]) {
        // 滚动结束，发送最终滚动事件并重置累积器
        [self sendMouseScrollWithOffset:offset viewSize:viewSize zoomScale:zoomScale];
        
        NSLog(@"📜 [ScrcpyVNCClient] Scroll ended - final offset: (%.1f,%.1f), final accumulator: %.2f", 
              offset.x, offset.y, self.scrollAccumulatorY);
        
        // 滚动结束后重置累积器和上一次偏移量
        self.scrollAccumulatorY = 0.0;
        self.lastScrollOffset = CGPointZero;
    } else if ([state isEqualToString:kDragStateCancelled]) {
        NSLog(@"📜 [ScrcpyVNCClient] Scroll cancelled - resetting accumulator and last offset");
        // 滚动取消时也重置累积器
        self.scrollAccumulatorY = 0.0;
        self.lastScrollOffset = CGPointZero;
    }
}

- (void)sendMouseScrollWithOffset:(CGPoint)offset viewSize:(CGSize)viewSize zoomScale:(CGFloat)zoomScale {
    if (!self.connected || !self.rfbClient) {
        NSLog(@"❌ [ScrcpyVNCClient] Cannot send mouse scroll: VNC not connected");
        return;
    }
    
    // 获取远程屏幕尺寸
    int remoteWidth = self.rfbClient->width;
    int remoteHeight = self.rfbClient->height;
    
    // 计算远程内容在本地的显示缩放比例（保持宽高比）
    CGFloat scaleX = viewSize.width / (CGFloat)remoteWidth;
    CGFloat scaleY = viewSize.height / (CGFloat)remoteHeight;
    CGFloat displayScale = MIN(scaleX, scaleY);  // 取较小值保持比例
    
    // 优化滚动偏移量计算，使用增量计算和累积器实现平滑滚动
    // 基础滚动敏感度系数
    static const CGFloat kScrollSensitivity = 0.5;  // 滚动敏感度
    static const CGFloat kScrollThreshold = 12.0;   // 滚动阈值（累积到这个值才触发滚动）
    
    // 计算增量偏移（当前偏移 - 上一次偏移）
    CGFloat deltaY = offset.y - self.lastScrollOffset.y;
    
    // 将增量手势偏移转换为远程坐标偏移（考虑显示缩放）
    CGFloat remoteDeltaY = deltaY / displayScale;
    
    // 考虑用户缩放倍数（zoomScale越大，滚动越精细）
    CGFloat adjustedDeltaY = remoteDeltaY / zoomScale;
    
    // 应用滚动敏感度并累积到累积器中（只累积增量）
    self.scrollAccumulatorY += adjustedDeltaY * kScrollSensitivity;
    
    // 更新上一次偏移量
    self.lastScrollOffset = offset;
    
    // 计算需要执行的滚动步数
    int scrollSteps = 0;
    int scrollButton = 0;
    int scrollButtonMask = 0;
    
    if (fabs(self.scrollAccumulatorY) >= kScrollThreshold) {
        // 确定滚动方向, Nature 自然滚动方向, 跟着手势方向滚动
        BOOL scrollUp = (self.scrollAccumulatorY > 0);
        scrollButton = scrollUp ? 4 : 5;  // 按钮4：向上滚动，按钮5：向下滚动
        scrollButtonMask = scrollUp ? (1 << 3) : (1 << 4);  // rfbButton4Mask or rfbButton5Mask
        
        // 计算滚动步数
        scrollSteps = (int)(fabs(self.scrollAccumulatorY) / kScrollThreshold);
        scrollSteps = MIN(scrollSteps, 5);  // 限制最大滚动步数
        
        // 从累积器中减去已处理的滚动量
        CGFloat processedScroll = scrollSteps * kScrollThreshold;
        if (self.scrollAccumulatorY > 0) {
            self.scrollAccumulatorY -= processedScroll;
        } else {
            self.scrollAccumulatorY += processedScroll;
        }
    }
    
    NSLog(@"📜 [ScrcpyVNCClient] Incremental scroll calculation:");
    NSLog(@"   Remote: %dx%d, View: %.0fx%.0f, DisplayScale: %.3f, ZoomScale: %.3f", 
          remoteWidth, remoteHeight, viewSize.width, viewSize.height, displayScale, zoomScale);
    NSLog(@"   CurrentOffset: %.1f, LastOffset: %.1f -> DeltaY: %.1f", 
          offset.y, self.lastScrollOffset.y, deltaY);
    NSLog(@"   RemoteDelta: %.1f -> AdjustedDelta: %.1f -> Accumulator: %.2f", 
          remoteDeltaY, adjustedDeltaY, self.scrollAccumulatorY);
    NSLog(@"   Threshold: %.1f, Steps: %d, Button: %d", 
          kScrollThreshold, scrollSteps, scrollButton);
    
    // 只在累积器超过阈值时才发送滚动事件
    if (scrollSteps > 0) {
        // 发送滚动事件（使用当前鼠标位置）
        for (int i = 0; i < scrollSteps; i++) {
            // 发送滚动按钮按下事件
            if (!SendPointerEvent(self.rfbClient, self.currentMouseX, self.currentMouseY, scrollButtonMask)) {
                NSLog(@"❌ [ScrcpyVNCClient] Failed to send scroll button down event (step %d)", i + 1);
                return;
            }
            
            // 发送滚动按钮松开事件
            if (!SendPointerEvent(self.rfbClient, self.currentMouseX, self.currentMouseY, 0)) {
                NSLog(@"❌ [ScrcpyVNCClient] Failed to send scroll button up event (step %d)", i + 1);
                return;
            }
            
            // 滚动事件之间的小延迟，保证服务器能正确处理
            usleep(8000);  // 8ms延迟，提高响应速度
        }
        
        NSLog(@"📜 [ScrcpyVNCClient] Scroll event sent: %d steps %@ at position (%d,%d), remaining accumulator: %.2f", 
              scrollSteps, (scrollButton == 4) ? @"UP" : @"DOWN", self.currentMouseX, self.currentMouseY, self.scrollAccumulatorY);
    } else {
        NSLog(@"📜 [ScrcpyVNCClient] Scroll accumulating: %.2f (threshold: %.1f)", 
              self.scrollAccumulatorY, kScrollThreshold);
    }
}

- (void)handleVNCZoomEvent:(NSNotification *)notification {
    if (!self.connected || !self.rfbClient) {
        NSLog(@"❌ [ScrcpyVNCClient] Cannot handle zoom event: VNC not connected");
        return;
    }
    
    NSDictionary *userInfo = notification.userInfo;
    if (!userInfo) {
        NSLog(@"❌ [ScrcpyVNCClient] Zoom event notification missing userInfo");
        return;
    }
    
    NSNumber *scaleNumber = userInfo[@"scale"];
    NSNumber *centerXNumber = userInfo[@"centerX"];
    NSNumber *centerYNumber = userInfo[@"centerY"];
    NSNumber *isFinishedNumber = userInfo[@"isFinished"];
    
    if (!scaleNumber || !centerXNumber || !centerYNumber || !isFinishedNumber) {
        NSLog(@"❌ [ScrcpyVNCClient] Zoom event notification missing required data");
        return;
    }
    
    CGFloat scale = [scaleNumber floatValue];
    CGFloat centerX = [centerXNumber floatValue];
    CGFloat centerY = [centerYNumber floatValue];
    BOOL isFinished = [isFinishedNumber boolValue];
    
    NSLog(@"🔍 [ScrcpyVNCClient] Zoom event - scale: %.2f, center: (%.3f, %.3f), finished: %@", 
          scale, centerX, centerY, isFinished ? @"YES" : @"NO");
    
    // 这里应该实现实际的缩放逻辑，比如调整SDL视图的缩放
    // 由于VNC协议本身不支持缩放，这里需要在客户端实现视图缩放
    // 可以通过修改SDL渲染的视口和缩放来实现
    
    // 发送缩放更新到SDL渲染层
    [self applyZoomScale:scale withCenterX:centerX centerY:centerY isFinished:isFinished];
}

- (void)applyZoomScale:(CGFloat)scale withCenterX:(CGFloat)centerX centerY:(CGFloat)centerY isFinished:(BOOL)isFinished {
    NSLog(@"🔍 [ScrcpyVNCClient] Setting zoom scale: %.2f at center (%.3f, %.3f), finished: %@", 
          scale, centerX, centerY, isFinished ? @"YES" : @"NO");
    
    // 更新缩放参数
    self.currentZoomScale = scale;
    self.zoomCenterX = centerX;
    self.zoomCenterY = centerY;
    self.zoomUpdatePending = YES;
    
    // 请求帧缓冲更新以触发重新渲染
    if (self.rfbClient && self.connected) {
        SendFramebufferUpdateRequest(self.rfbClient, 0, 0, self.rfbClient->width, self.rfbClient->height, FALSE);
        NSLog(@"🔍 [ScrcpyVNCClient] Requested framebuffer update for zoom application");
    }
}

@end

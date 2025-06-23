//
//  SDLVNCClient.m
//  VNCClient
//
//  Created by Ethan on 12/16/24.
//

#import "ScrcpyVNCClient.h"
#import "ScrcpyBlockWrapper.h"
#import "ScrcpyMenuView.h"
#import "ScrcpyCommon.h"
#import "RenderRegionCalculator.h"
#import "ScrcpyConstants.h"

#import <objc/runtime.h>
#import <SDL2/SDL.h>
#import <SDL2/SDL_mouse.h>
#import <rfb/rfbclient.h>
#import <rfb/keysym.h>
#import <stdlib.h>
#import <arpa/inet.h>

#define CFRunLoopNormalInterval     0.5f
#define CFRunLoopHandledSourceInterval 0.0002f

CFRunLoopRunResult CFRunLoopRunInMode_fix(CFRunLoopMode mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {
    static CFTimeInterval nextLoopInterval = CFRunLoopNormalInterval;
    CFRunLoopRunResult result = CFRunLoopRunInMode(mode, nextLoopInterval, returnAfterSourceHandled);
    if (result == kCFRunLoopRunHandledSource) {
        nextLoopInterval = CFRunLoopHandledSourceInterval;
    } else {
        nextLoopInterval = CFRunLoopNormalInterval;
    }
    return result;
}

@interface ScrcpyVNCClient () <ScrcpyClientProtocol>

@property (nonatomic, strong) SDLUIKitDelegate *sdlDelegate;
@property (nonatomic, copy) void (^sessionCompletion)(enum ScrcpyStatus, NSString *);
@property (nonatomic, copy) NSDictionary  *sessionArguments;

// Property for scrcpy status
@property (nonatomic, assign) enum ScrcpyStatus scrcpyStatus;

// VNC 远程桌面的图像像素大小
@property (nonatomic, assign) CGSize imagePixelsSize;

// 本机渲染屏幕区域大小
@property (nonatomic, assign) CGSize renderScreenSize;

// SDL rendering objects (need to access from zoom methods)
@property (nonatomic, assign) SDL_Renderer *currentRenderer;
@property (nonatomic, assign) SDL_Texture *currentTexture;

// VNC 光标相关属性
@property (nonatomic, assign) SDL_Cursor *vncCursor;
@property (nonatomic, assign) int cursorX;
@property (nonatomic, assign) int cursorY;
@property (nonatomic, assign) BOOL cursorVisible;

// VNC 拖拽手势相关属性
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) CGPoint lastDragLocation;
@property (nonatomic, assign) int currentMouseX;
@property (nonatomic, assign) int currentMouseY;
@property (nonatomic, assign) int buttonMask;

// VNC 拖拽偏移量相关属性
@property (nonatomic, assign) CGPoint currentDragOffset;
@property (nonatomic, assign) CGPoint totalDragOffset;
@property (nonatomic, assign) CGPoint normalizedDragOffset;

// Scale render properties
@property (nonatomic, strong) RenderRegionResult *currentRenderingRegion;

@end

@implementation ScrcpyVNCClient
{
    BOOL _connected;
    rfbClient *_rfbClient;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.sdlDelegate = [[SDLUIKitDelegate alloc] init];
        
        // 初始化缩放相关属性
        self.imagePixelsSize = CGSizeZero; // 初始图像像素大小
        self.currentRenderer = NULL;
        self.currentTexture = NULL;
        
        // 初始化光标相关属性
        self.vncCursor = NULL;
        self.cursorX = 0;
        self.cursorY = 0;
        self.cursorVisible = NO;
        
        // 监听断开连接通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDisconnectRequest:)
                                                     name:@"ScrcpyRequestDisconnectNotification"
                                                   object:nil];
        
        // 监听VNC缩放通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleVNCZoomNotification:)
                                                     name:@"ScrcpyVNCZoomNotification"
                                                   object:nil];
        
        // 监听VNC拖拽通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleVNCDragNotification:)
                                                     name:@"ScrcpyVNCDragNotification"
                                                   object:nil];
        
        // 监听VNC拖拽偏移量通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleVNCDragOffsetNotification:)
                                                     name:@"ScrcpyVNCDragOffsetNotification"
                                                   object:nil];
        
        // 监听VNC鼠标事件通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleVNCMouseEventNotification:)
                                                     name:@"ScrcpyVNCMouseEventNotification"
                                                   object:nil];
        
        // 初始化拖拽相关属性
        self.isDragging = NO;
        self.lastDragLocation = CGPointZero;
        self.currentMouseX = 0;
        self.currentMouseY = 0;
        self.buttonMask = 0; // 初始化按钮状态为无按钮按下
        
        // 初始化拖拽偏移量相关属性
        self.currentDragOffset = CGPointZero;
        self.totalDragOffset = CGPointZero;
        self.normalizedDragOffset = CGPointZero;
    }
    return self;
}

-(void)dealloc {
    // 清理光标资源
    if (self.vncCursor) {
        SDL_FreeCursor(self.vncCursor);
        self.vncCursor = NULL;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIWindowScene *)currentScene {
    for (UIWindowScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
        if (scene.activationState == UISceneActivationStateForegroundActive) { // 找到活跃状态的 Scene
            return scene;
        }
    }
    return nil;
}

-(void)vncMessageLoop
{
    // Ensure running in background thread
    if ([NSThread isMainThread]) {
        NSLog(@"🔌 [ScrcpyVNCClient] vncMessageLoop called from non-main thread, switching to main thread");
        [NSThread detachNewThreadSelector:@selector(vncMessageLoop) toTarget:self withObject:nil];
        return;
    }
    
    while(_connected) {
        int i = WaitForMessage(_rfbClient, 500);
        
        if (i < 0) {
            NSLog(@"🔌 [ScrcpyVNCClient] VNC message wait failed, breaking loop");
            _connected = NO;
            self.scrcpyStatus = ScrcpyStatusDisconnected;
            ScrcpyUpdateStatus(ScrcpyStatusDisconnected, "VNC message wait failed");
            return;
        }
        
        if (!HandleRFBServerMessage(_rfbClient)) {
            NSLog(@"🔌 [ScrcpyVNCClient] VNC server message handling failed, breaking loop");
            _connected = NO;
            self.scrcpyStatus = ScrcpyStatusDisconnected;
            ScrcpyUpdateStatus(ScrcpyStatusDisconnected, "VNC server message handling failed");
            return;
        }
    }
}

-(void)SDLEventLoop
{
    // Run a while for wait other UI events
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, NO);
    
    SDL_iPhoneSetEventPump(SDL_TRUE);
    SDL_Event e;

    while(_connected) {
        if(!SDL_PollEvent(&e)) {
            SDL_Delay(1);
            continue;
        }
        
        NSLog(@"SDL Event Type: %d", e.type);
       
        switch(e.type) {
        case SDL_DISPLAYEVENT:
            NSLog(@"SDL_DISPLAYEVENT: display %d, event %d", e.display.display, e.display.event);
            break;
        case SDL_WINDOWEVENT:
            switch (e.window.event) {
                case SDL_WINDOWEVENT_EXPOSED:
                    SendFramebufferUpdateRequest(_rfbClient, 0, 0, _rfbClient->width, _rfbClient->height, FALSE);
                    break;
                
                case SDL_WINDOWEVENT_RESIZED:
                    SendExtDesktopSize(_rfbClient, e.window.data1, e.window.data2);
                    break;
                    
                case SDL_WINDOWEVENT_FOCUS_GAINED:
                    if (SDL_HasClipboardText()) {
                        char *text = SDL_GetClipboardText();
                        if(text) {
                            rfbClientLog("sending clipboard text '%s'\n", text);
                            SendClientCutText(_rfbClient, text, (int)strlen(text));
                        }
                    }
                    break;
                    
                case SDL_WINDOWEVENT_FOCUS_LOST:
                    NSLog(@"SDL_WINDOWEVENT_FOCUS_LOST");
                    break;
            }
            break;
        case SDL_MOUSEWHEEL:
            // 屏蔽鼠标滚轮事件，统一由上层手势接口控制
            NSLog(@"🖱️ [ScrcpyVNCClient] Mouse wheel event blocked, handled by upper layer gesture interface");
            break;
        case SDL_MOUSEBUTTONDOWN:
        case SDL_MOUSEBUTTONUP:
        case SDL_MOUSEMOTION:
            // 屏蔽所有鼠标按钮和移动事件，统一由上层手势接口控制
            NSLog(@"🖱️ [ScrcpyVNCClient] Mouse event blocked (type: %d), handled by upper layer gesture interface", e.type);
            break;
                
        case SDL_KEYUP:
        case SDL_KEYDOWN: {
            if (!_rfbClient || !_connected) {
                NSLog(@"⚠️ [ScrcpyVNCClient] Cannot send key event - VNC client not connected");
                break;
            }
            
            SDL_Scancode scancode = e.key.keysym.scancode;
            uint32_t keysym = [self sdlScancodeToKeysym:scancode];
            
            if (keysym == 0) {
                // Skip unmapped keys
                break;
            }
            
            BOOL pressed = (e.type == SDL_KEYDOWN);
            
            NSLog(@"🎮 [ScrcpyVNCClient] %@ key - scancode: %d, keysym: 0x%x",
                  pressed ? @"Pressed" : @"Released", scancode, keysym);
            
            // Send key event to VNC server
            SendKeyEvent(_rfbClient, keysym, pressed ? SDL_TRUE : SDL_FALSE);
            
            break;
        }
        case SDL_TEXTINPUT:
            // Handle text input for character composition
            if (_rfbClient && _connected) {
                const char* text = e.text.text;
                NSLog(@"📝 [ScrcpyVNCClient] Text input: %s", text);
                
                // Convert UTF-8 text to individual key events
                NSString *inputString = [NSString stringWithUTF8String:text];
                for (NSUInteger i = 0; i < inputString.length; i++) {
                    unichar character = [inputString characterAtIndex:i];
                    
                    // Convert Unicode character to keysym
                    uint32_t keysym = 0;
                    if (character < 0x100) {
                        // ASCII range
                        keysym = character;
                    } else {
                        // Unicode range (simplified mapping)
                        keysym = 0x01000000 | character;
                    }
                    
                    if (keysym <= 0) continue;
                    
                    // Send key press and release for each character
                    SendKeyEvent(_rfbClient, keysym, SDL_TRUE);
                    usleep(10000); // 10ms delay between press and release
                    SendKeyEvent(_rfbClient, keysym, SDL_FALSE);
                }
            }
            break;
        case SDL_QUIT:
            NSLog(@"🔌 [ScrcpyVNCClient] SDL_QUIT event received, breaking VNC loop");
            _connected = NO;
            break;
        default:
            rfbClientLog("ignore SDL event: 0x%x\n", e.type);
        }
    }

    // Cleanup VNC client
    if (_rfbClient) rfbClientCleanup(_rfbClient);
    _rfbClient = NULL;
    
    // Clear block IMP to free entry for next client
    GetSet_GetCredentialBlockIMP(_rfbClient, nil);
    GetSet_GotFrameBufferUpdateBlockIMP(_rfbClient, nil);
    
    // Quit
    SDL_Quit();
    
    SDL_iPhoneSetEventPump(SDL_FALSE);

    NSLog(@"✅ SDL_main end");
}

-(void)startWithArguments:(NSDictionary *)arguments completion:(void (^)(enum ScrcpyStatus, NSString *))completion
{
    NSString *host = arguments[@"hostReal"];
    NSString *port = arguments[@"port"];
    NSString *user = arguments[@"vncOptions"][@"vncUser"];
    NSString *password = arguments[@"vncOptions"][@"vncPassword"];
    
    NSLog(@"✅ SDL_main start vnc client");
    
    // Mock ApplicationDelegate methods
    [self.sdlDelegate application:[UIApplication sharedApplication] didFinishLaunchingWithOptions:@{}];

    // Execute SDL main
    SDL_Init(SDL_INIT_VIDEO);
    atexit(SDL_Quit);
    signal(SIGINT, exit);
    
    // Update status after SDL initialization
    self.scrcpyStatus = ScrcpyStatusSDLInited;
    ScrcpyUpdateStatus(ScrcpyStatusSDLInited, "SDL initialized successfully");
    
    __block int sdlFlags = SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_FULLSCREEN;

    __block SDL_Texture *sdlTexture = NULL;
    __block SDL_Renderer *sdlRenderer = NULL;
    __block SDL_Window *sdlWindow = nil;

    _rfbClient = rfbGetClient(8, 3, 4);
    _rfbClient->canHandleNewFBSize = true;
    _rfbClient->listenPort = LISTEN_PORT_OFFSET;
    _rfbClient->listen6Port = LISTEN_PORT_OFFSET;
    
    _rfbClient->MallocFrameBuffer = (MallocFrameBufferProc)imp_implementationWithBlock(^rfbBool(rfbClient* client){
        int width=client->width, height=client->height, depth=client->format.bitsPerPixel;

        // 保存原始尺寸（仅在第一次时保存）
        if (self.imagePixelsSize.width == 0 && self.imagePixelsSize.height == 0) {
            self.imagePixelsSize = CGSizeMake(width, height);
            NSLog(@"🔍 [ScrcpyVNCClient] Saved original VNC size: %.0dx%.0d", width, height);
        }
        
        SDL_FreeSurface(rfbClientGetClientData(client, SDL_Init));
        SDL_Surface* sdl=SDL_CreateRGBSurface(0, width, height, depth, 0, 0, 0, 0);
        if(!sdl) rfbClientErr("resize: error creating surface: %s\n", SDL_GetError());

        rfbClientSetClientData(client, SDL_Init, sdl);
        client->width = sdl->pitch / (depth / 8);
        client->frameBuffer = sdl->pixels;

        client->format.bitsPerPixel = depth;
        client->format.redShift = sdl->format->Rshift;
        client->format.greenShift = sdl->format->Gshift;
        client->format.blueShift = sdl->format->Bshift;
        client->format.redMax = sdl->format->Rmask>>client->format.redShift;
        client->format.greenMax = sdl->format->Gmask>>client->format.greenShift;
        client->format.blueMax = sdl->format->Bmask>>client->format.blueShift;
        
        // 启用远程光标支持
        client->appData.useRemoteCursor = true;
        
        // 启用本地光标显示
        client->appData.viewOnly = false;
        
        CustomSetFormatAndEncodings(client);

        /* create or resize the window */
        sdlWindow = SDL_CreateWindow(client->desktopName,
                                     SDL_WINDOWPOS_UNDEFINED,
                                     SDL_WINDOWPOS_UNDEFINED,
                                     width,
                                     height,
                                     sdlFlags);
        if(!sdlWindow) rfbClientErr("resize: error creating window: %s\n", SDL_GetError());

        // Update status after SDL window creation
        self.scrcpyStatus = ScrcpyStatusSDLWindowCreated;
        ScrcpyUpdateStatus(ScrcpyStatusSDLWindowCreated, "SDL window created successfully");

        /* create the renderer if it does not already exist */
        sdlRenderer = SDL_CreateRenderer(sdlWindow, -1, SDL_RENDERER_ACCELERATED);
        if(!sdlRenderer) rfbClientErr("resize: error creating renderer: %s\n", SDL_GetError());
        SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");  /* make the scaled rendering look smoother. */
        
        // Store renderer for zoom functionality
        self.currentRenderer = sdlRenderer;
        
        NSLog(@"SDL Window: %@", self.sdlDelegate.window);
        self.sdlDelegate.window.windowScene = self.currentScene;
        NSLog(@"SDL Window Scene: %@", self.sdlDelegate.window.windowScene);
        [self.sdlDelegate.window makeKeyWindow];
        NSLog(@"SDL Window RootController: %@", self.sdlDelegate.window.rootViewController);

        NSLog(@"🔍 [ScrcpyVNCClient] Skipping logical size setup, using manual aspect ratio calculation");

        sdlTexture = SDL_CreateTexture(sdlRenderer, SDL_PIXELFORMAT_ARGB8888,
                                       SDL_TEXTUREACCESS_STREAMING, width, height);
        
        if(!sdlTexture) rfbClientErr("resize: error creating texture: %s\n", SDL_GetError());
        
        // Store texture for zoom functionality
        self.currentTexture = sdlTexture;
        
        // 初始化渲染到屏幕中央, 并填充满屏幕
        int windowWidth, windowHeight;
        SDL_GetRendererOutputSize(sdlRenderer, &windowWidth, &windowHeight);
        self.currentRenderingRegion = [RenderRegionCalculator calculateRenderRegionWithScreenSize:self.renderScreenSize
                                                                                        imageSize:self.imagePixelsSize
                                                                                      scaleFactor:1.0 centerX:0.5 centerY:0.5];
        return true;
    });
    
    _rfbClient->GotFrameBufferUpdate = GotFrameBufferUpdateBlock;
    GetSet_GotFrameBufferUpdateBlockIMP(_rfbClient, imp_implementationWithBlock(^void(rfbClient* cl, int x, int y, int w, int h){
        SDL_Surface *sdl = rfbClientGetClientData(cl, SDL_Init);
        SDL_Rect r = {x, y, w, h};
        
        if(SDL_UpdateTexture(sdlTexture, &r, sdl->pixels + y*sdl->pitch + x*4, sdl->pitch) < 0) {
            rfbClientErr("update: failed to update texture: %s\n", SDL_GetError());
        }
        
        // 设置黑色背景并清除
        SDL_SetRenderDrawColor(sdlRenderer, 0, 0, 0, 255);
        if(SDL_RenderClear(sdlRenderer) < 0) {
            rfbClientErr("update: failed to clear renderer: %s\n", SDL_GetError());
        }
        
        // 重置渲染器缩放为1.0（我们现在使用源矩形来实现缩放）
        SDL_RenderSetScale(sdlRenderer, 1.0, 1.0);
        
        // 获取窗口尺寸
        int windowWidth = self.renderScreenSize.width, windowHeight = self.renderScreenSize.height;
        SDL_GetRendererOutputSize(sdlRenderer, &windowWidth, &windowHeight);
        
        SDL_Rect srcRect, targetRect;
        if (self.currentRenderingRegion) {
            // 应用拖拽偏移量到源矩形（方向相反：用户向右拖拽时，视图向左移动）
            CGFloat normalizedDragX = self.normalizedDragOffset.x;
            CGFloat normalizedDragY = self.normalizedDragOffset.y;
            
            // 平滑插值处理拖拽偏移
            static CGFloat lastNormalizedDragX = 0.0;
            static CGFloat lastNormalizedDragY = 0.0;
            
            // 应用平滑插值因子
            CGFloat smoothingFactor = 0.8; // 平滑系数：值越小越平滑
            normalizedDragX = lastNormalizedDragX + (normalizedDragX - lastNormalizedDragX) * smoothingFactor;
            normalizedDragY = lastNormalizedDragY + (normalizedDragY - lastNormalizedDragY) * smoothingFactor;
            
            lastNormalizedDragX = normalizedDragX;
            lastNormalizedDragY = normalizedDragY;
            
            CGFloat dragOffsetX = -normalizedDragX * self.imagePixelsSize.width;
            CGFloat dragOffsetY = -normalizedDragY * self.imagePixelsSize.height;
            
            srcRect.x = self.currentRenderingRegion.sourceRect.origin.x + dragOffsetX;
            srcRect.y = self.currentRenderingRegion.sourceRect.origin.y + dragOffsetY;
            srcRect.w = self.currentRenderingRegion.sourceRect.size.width;
            srcRect.h = self.currentRenderingRegion.sourceRect.size.height;
            
            // 确保源矩形不超出图像边界
            srcRect.x = MAX(0, MIN(self.imagePixelsSize.width - srcRect.w, srcRect.x));
            srcRect.y = MAX(0, MIN(self.imagePixelsSize.height - srcRect.h, srcRect.y));
            
            targetRect.x = self.currentRenderingRegion.targetRect.origin.x;
            targetRect.y = self.currentRenderingRegion.targetRect.origin.y;
            targetRect.w = self.currentRenderingRegion.targetRect.size.width;
            targetRect.h = self.currentRenderingRegion.targetRect.size.height;
        }

        // 统一渲染调用
        if(SDL_RenderCopy(sdlRenderer, sdlTexture, &srcRect, &targetRect) < 0) {
            rfbClientErr("update: failed to copy texture to renderer: %s\n", SDL_GetError());
        }
        
        // 检查纹理信息
        Uint32 format;
        int access;
        SDL_QueryTexture(sdlTexture, &format, &access, &w, &h);
        
        // 更新光标位置（如果光标可见）
        if (self.cursorVisible && self.vncCursor) {
            // 获取当前鼠标位置
            int mouseX, mouseY;
            SDL_GetMouseState(&mouseX, &mouseY);
            
            // 更新光标位置
            self.cursorX = mouseX;
            self.cursorY = mouseY;
        }
        
        SDL_RenderPresent(sdlRenderer);
        
        // 当开始更新图像后, 才认为 SDLWindow 已经出现
        if (self.scrcpyStatus >= ScrcpyStatusSDLWindowAppeared) {
            return;
        }
        // Update status when SDL window appears, delay 1s to ensure window is ready
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.scrcpyStatus = ScrcpyStatusSDLWindowAppeared;
            ScrcpyUpdateStatus(ScrcpyStatusSDLWindowAppeared, "VNC connection established and window appeared");
        });
    }));
    
    // 设置光标形状处理回调
    _rfbClient->GotCursorShape = (GotCursorShapeProc)imp_implementationWithBlock(^void(rfbClient* cl, int xhot, int yhot, int width, int height, int bytesPerPixel){
        NSLog(@"🖱️ [ScrcpyVNCClient] Received cursor shape: %dx%d, hot spot: (%d,%d), bpp: %d", width, height, xhot, yhot, bytesPerPixel);
        
        // 清理之前的光标
        if (self.vncCursor) {
            SDL_FreeCursor(self.vncCursor);
            self.vncCursor = NULL;
        }
        
        // 检查光标数据是否有效
        if (!cl->rcSource || !cl->rcMask || width <= 0 || height <= 0) {
            NSLog(@"⚠️ [ScrcpyVNCClient] Invalid cursor data, using default cursor");
            self.vncCursor = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW);
            self.cursorVisible = YES;
            SDL_SetCursor(self.vncCursor);
            return;
        }
        
        // 创建光标数据数组
        int dataSize = width * height;
        Uint8 *cursorData = malloc(dataSize);
        Uint8 *cursorMask = malloc(dataSize);
        
        if (!cursorData || !cursorMask) {
            NSLog(@"❌ [ScrcpyVNCClient] Failed to allocate cursor memory");
            if (cursorData) free(cursorData);
            if (cursorMask) free(cursorMask);
            return;
        }
        
        // 转换光标数据格式
        if (bytesPerPixel == 4) {
            // 32位颜色数据，需要转换为黑白
            uint32_t *sourceData = (uint32_t *)cl->rcSource;
            for (int i = 0; i < dataSize; i++) {
                uint32_t pixel = sourceData[i];
                // 简单的亮度计算
                uint8_t brightness = ((pixel & 0xFF) + ((pixel >> 8) & 0xFF) + ((pixel >> 16) & 0xFF)) / 3;
                cursorData[i] = (brightness > 128) ? 1 : 0;
            }
        } else if (bytesPerPixel == 1) {
            // 8位灰度数据
            memcpy(cursorData, cl->rcSource, dataSize);
        } else {
            // 其他格式，使用默认光标
            NSLog(@"⚠️ [ScrcpyVNCClient] Unsupported cursor format: %d bpp", bytesPerPixel);
            free(cursorData);
            free(cursorMask);
            self.vncCursor = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW);
            self.cursorVisible = YES;
            SDL_SetCursor(self.vncCursor);
            return;
        }
        
        // 复制掩码数据
        memcpy(cursorMask, cl->rcMask, dataSize);
        
        // 创建SDL光标
        self.vncCursor = SDL_CreateCursor(cursorData, cursorMask, width, height, xhot, yhot);
        
        if (self.vncCursor) {
            NSLog(@"✅ [ScrcpyVNCClient] VNC cursor created successfully");
            self.cursorVisible = YES;
            SDL_SetCursor(self.vncCursor);
        } else {
            NSLog(@"❌ [ScrcpyVNCClient] Failed to create VNC cursor: %s", SDL_GetError());
            self.vncCursor = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW);
            self.cursorVisible = YES;
            SDL_SetCursor(self.vncCursor);
        }
        
        // 清理临时数据
        free(cursorData);
        free(cursorMask);
    });
    
    // 设置光标位置处理回调
    _rfbClient->HandleCursorPos = (HandleCursorPosProc)imp_implementationWithBlock(^rfbBool(rfbClient* cl, int x, int y){
        NSLog(@"🖱️ [ScrcpyVNCClient] Received cursor position: (%d, %d)", x, y);
        
        // 更新光标位置
        self.cursorX = x;
        self.cursorY = y;
        
        // 显示光标并更新光标位置
        if (self.vncCursor) {
            self.cursorVisible = YES;
            SDL_SetCursor(self.vncCursor);
            
            // 将VNC坐标转换为SDL窗口坐标
            int sdlX = x;
            int sdlY = y;
            
            // 应用缩放和偏移转换
            if (self.currentRenderingRegion) {
                CGFloat scaleX = self.currentRenderingRegion.targetRect.size.width / self.currentRenderingRegion.sourceRect.size.width;
                CGFloat scaleY = self.currentRenderingRegion.targetRect.size.height / self.currentRenderingRegion.sourceRect.size.height;
                
                sdlX = (x - self.currentRenderingRegion.sourceRect.origin.x) * scaleX + self.currentRenderingRegion.targetRect.origin.x;
                sdlY = (y - self.currentRenderingRegion.sourceRect.origin.y) * scaleY + self.currentRenderingRegion.targetRect.origin.y;
                
                // 确保坐标在屏幕范围内
                sdlX = MAX(0, MIN(self.renderScreenSize.width - 1, sdlX));
                sdlY = MAX(0, MIN(self.renderScreenSize.height - 1, sdlY));
            }
            
            NSLog(@"🖱️ [ScrcpyVNCClient] Setting cursor position: VNC(%d, %d) -> SDL(%d, %d)", x, y, sdlX, sdlY);
            SDL_WarpMouseInWindow(NULL, sdlX, sdlY);
        } else {
            NSLog(@"⚠️ [ScrcpyVNCClient] No VNC cursor available to display");
        }
        
        return TRUE;
    });
    
    // Set up GetPassword callback for simple password-only VNC authentication (rfbVncAuth)
    _rfbClient->GetPassword = (GetPasswordProc)imp_implementationWithBlock(^char *(rfbClient* cl){
        NSLog(@"🔐 [ScrcpyVNCClient] GetPassword callback invoked for password-only VNC authentication");
        
        if (!password || password.length == 0) {
            NSLog(@"❌ [ScrcpyVNCClient] Password is empty for VNC authentication");
            return NULL;
        }
        
        // Allocate memory for password (library will free it after use)
        size_t passwordLength = password.length + 1;
        char *passwordCStr = malloc(passwordLength);
        if (!passwordCStr) {
            NSLog(@"❌ [ScrcpyVNCClient] Failed to allocate memory for VNC password");
            return NULL;
        }
        
        // Copy password and ensure null termination
        strncpy(passwordCStr, password.UTF8String, passwordLength - 1);
        passwordCStr[passwordLength - 1] = '\0';
        
        // Remove trailing newlines if any
        passwordCStr[strcspn(passwordCStr, "\n")] = '\0';
        
        NSLog(@"🔐 [ScrcpyVNCClient] Password provided for VNC authentication (length: %zu)", strlen(passwordCStr));
        return passwordCStr;
    });
    
    // Set up GetCredential callback for advanced authentication (VeNCrypt, MSLogon, etc.)
    _rfbClient->GetCredential = GetCredentialBlock;
    GetSet_GetCredentialBlockIMP(_rfbClient, imp_implementationWithBlock(^rfbCredential *(rfbClient* cl, int credentialType){
        NSLog(@"🔐 [ScrcpyVNCClient] GetCredential callback invoked for advanced VNC authentication, type: %d", credentialType);
        
        rfbCredential *c = malloc(sizeof(rfbCredential));
        if (!c) {
            NSLog(@"❌ [ScrcpyVNCClient] Failed to allocate memory for VNC credential");
            return NULL;
        }
        
        if(credentialType != rfbCredentialTypeUser) {
            NSLog(@"❌ [ScrcpyVNCClient] Unsupported credential type: %d (only rfbCredentialTypeUser is supported)", credentialType);
            free(c);
            return NULL;
        }
        
        // Allocate and copy username
        c->userCredential.username = malloc(RFB_BUF_SIZE);
        if (!c->userCredential.username) {
            NSLog(@"❌ [ScrcpyVNCClient] Failed to allocate memory for VNC username");
            free(c);
            return NULL;
        }
        strncpy(c->userCredential.username, user ? user.UTF8String : "", RFB_BUF_SIZE - 1);
        c->userCredential.username[RFB_BUF_SIZE - 1] = '\0';
        
        // Allocate and copy password
        c->userCredential.password = malloc(RFB_BUF_SIZE);
        if (!c->userCredential.password) {
            NSLog(@"❌ [ScrcpyVNCClient] Failed to allocate memory for VNC password");
            free(c->userCredential.username);
            free(c);
            return NULL;
        }
        strncpy(c->userCredential.password, password ? password.UTF8String : "", RFB_BUF_SIZE - 1);
        c->userCredential.password[RFB_BUF_SIZE - 1] = '\0';

        NSLog(@"🔐 [ScrcpyVNCClient] VNC credentials prepared - username: %s, password: [HIDDEN]", c->userCredential.username);

        /* remove trailing newlines */
        c->userCredential.username[strcspn(c->userCredential.username, "\n")] = '\0';
        c->userCredential.password[strcspn(c->userCredential.password, "\n")] = '\0';

        return c;
    }));
    
    const char *argv[] = {"vnc", [NSString stringWithFormat:@"%@:%@", host, port].UTF8String};
    int argc = sizeof(argv) / sizeof(char *);
    
    // Update status to indicate connecting
    self.scrcpyStatus = ScrcpyStatusConnecting;
    ScrcpyUpdateStatus(ScrcpyStatusConnecting, [[NSString stringWithFormat:@"Connecting to %@:%@", host, port] UTF8String]);
    
    if(!rfbInitClient(_rfbClient, &argc, (char **)argv)) {
        _rfbClient = NULL;
        
        // Update status on connection failure
        self.scrcpyStatus = ScrcpyStatusConnectingFailed;
        ScrcpyUpdateStatus(ScrcpyStatusConnectingFailed, [[NSString stringWithFormat:@"Failed to connect to VNC server %@:%@", host, port] UTF8String]);
        return;
    }
    
    // Mark as connected
    _connected = YES;
    
    // Update status on successful connection
    self.scrcpyStatus = ScrcpyStatusConnected;
    ScrcpyUpdateStatus(ScrcpyStatusConnected, "VNC client connected successfully");
    
    // Start message loop in background thread
    [self vncMessageLoop];

    // Start SDL event loop
    // Caution: must call this method async, otherwise it will block the main thread
    [self performSelector:@selector(SDLEventLoop) withObject:nil afterDelay:0];
}

-(void)stopVNC {
    NSLog(@"🔌 [ScrcpyVNCClient] stopVNC called");
    
    // Mark as disconnected
    _connected = NO;
    
    // Reset zoom properties
    self.imagePixelsSize = CGSizeZero;
    self.currentRenderer = NULL;
    self.currentTexture = NULL;
    
    // 清理光标资源
    if (self.vncCursor) {
        SDL_FreeCursor(self.vncCursor);
        self.vncCursor = NULL;
    }
    self.cursorVisible = NO;
    self.cursorX = 0;
    self.cursorY = 0;
    
    // Reset drag properties
    self.isDragging = NO;
    self.lastDragLocation = CGPointZero;
    self.currentDragOffset = CGPointZero;
    self.totalDragOffset = CGPointZero;
    self.normalizedDragOffset = CGPointZero;
    self.buttonMask = 0; // 重置按钮状态
    
    // Update status to disconnected
    self.scrcpyStatus = ScrcpyStatusDisconnected;
    ScrcpyUpdateStatus(ScrcpyStatusDisconnected, "VNC connection stopped by user");
    
    // Call SDL_Quit to send Quit Event
    SDL_Event event;
    event.type = SDL_QUIT;
    SDL_PushEvent(&event);
}

#pragma mark - ScrcpyClientProtocol

-(void)disconnect {
    NSLog(@"🔌 [ScrcpyVNCClient] disconnect method called");
    [self stopVNC];
}

#pragma mark - ScrcpyMenuViewDelegate

- (void)didTapBackButton {
    NSLog(@"🎮 [ScrcpyVNCClient] Back button tapped");
    // VNC equivalent: Send escape key or back gesture
    if (_rfbClient && _connected) {
        // Send Android back key (keycode 4)
        SendKeyEvent(_rfbClient, XK_Escape, SDL_TRUE);
        usleep(50000); // 50ms delay
        SendKeyEvent(_rfbClient, XK_Escape, SDL_FALSE);
    }
}

- (void)didTapHomeButton {
    NSLog(@"🎮 [ScrcpyVNCClient] Home button tapped");
    // VNC equivalent: Send home key
    if (_rfbClient && _connected) {
        // Send Android home key (Meta key)
        SendKeyEvent(_rfbClient, XK_Super_L, SDL_TRUE);
        usleep(50000); // 50ms delay
        SendKeyEvent(_rfbClient, XK_Super_L, SDL_FALSE);
    }
}

- (void)didTapSwitchButton {
    NSLog(@"🎮 [ScrcpyVNCClient] Switch button tapped");
    // VNC equivalent: Send recent apps key
    if (_rfbClient && _connected) {
        // Send Alt+Tab for recent apps
        SendKeyEvent(_rfbClient, XK_Alt_L, SDL_TRUE);
        SendKeyEvent(_rfbClient, XK_Tab, SDL_TRUE);
        usleep(50000); // 50ms delay
        SendKeyEvent(_rfbClient, XK_Tab, SDL_FALSE);
        SendKeyEvent(_rfbClient, XK_Alt_L, SDL_FALSE);
    }
}

- (void)didTapKeyboardButton {
    NSLog(@"🎮 [ScrcpyVNCClient] Keyboard button tapped");
    // Start text input for VNC
    SDL_StartTextInput();
}

- (void)didTapActionsButton {
    NSLog(@"🎮 [ScrcpyVNCClient] Actions button tapped");
    // Additional actions can be implemented here
    // For now, just log the action
}

- (void)didTapDisconnectButton {
    NSLog(@"🎮 [ScrcpyVNCClient] Disconnect button tapped");
    // Initiate VNC disconnection
    [self stopVNC];
}

#pragma mark - VNC Key Event Handler

- (void)handleVNCKeyEvent:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    uint32_t keysym = [userInfo[@"keysym"] unsignedIntValue];
    BOOL pressed = [userInfo[@"pressed"] boolValue];
    
    NSLog(@"🎮 [ScrcpyVNCClient] Handling VNC key event - keysym: 0x%x, pressed: %@", keysym, pressed ? @"YES" : @"NO");
    
    if (_rfbClient && _connected) {
        SendKeyEvent(_rfbClient, keysym, pressed ? SDL_TRUE : SDL_FALSE);
    } else {
        NSLog(@"⚠️ [ScrcpyVNCClient] Cannot send key event - VNC client not connected");
    }
}

- (uint32_t)sdlScancodeToKeysym:(SDL_Scancode)scancode {
    // Convert SDL scancode to X11 keysym for VNC
    switch (scancode) {
        case SDL_SCANCODE_A: return XK_a;
        case SDL_SCANCODE_B: return XK_b;
        case SDL_SCANCODE_C: return XK_c;
        case SDL_SCANCODE_D: return XK_d;
        case SDL_SCANCODE_E: return XK_e;
        case SDL_SCANCODE_F: return XK_f;
        case SDL_SCANCODE_G: return XK_g;
        case SDL_SCANCODE_H: return XK_h;
        case SDL_SCANCODE_I: return XK_i;
        case SDL_SCANCODE_J: return XK_j;
        case SDL_SCANCODE_K: return XK_k;
        case SDL_SCANCODE_L: return XK_l;
        case SDL_SCANCODE_M: return XK_m;
        case SDL_SCANCODE_N: return XK_n;
        case SDL_SCANCODE_O: return XK_o;
        case SDL_SCANCODE_P: return XK_p;
        case SDL_SCANCODE_Q: return XK_q;
        case SDL_SCANCODE_R: return XK_r;
        case SDL_SCANCODE_S: return XK_s;
        case SDL_SCANCODE_T: return XK_t;
        case SDL_SCANCODE_U: return XK_u;
        case SDL_SCANCODE_V: return XK_v;
        case SDL_SCANCODE_W: return XK_w;
        case SDL_SCANCODE_X: return XK_x;
        case SDL_SCANCODE_Y: return XK_y;
        case SDL_SCANCODE_Z: return XK_z;
        
        // Numbers
        case SDL_SCANCODE_1: return XK_1;
        case SDL_SCANCODE_2: return XK_2;
        case SDL_SCANCODE_3: return XK_3;
        case SDL_SCANCODE_4: return XK_4;
        case SDL_SCANCODE_5: return XK_5;
        case SDL_SCANCODE_6: return XK_6;
        case SDL_SCANCODE_7: return XK_7;
        case SDL_SCANCODE_8: return XK_8;
        case SDL_SCANCODE_9: return XK_9;
        case SDL_SCANCODE_0: return XK_0;
        
        // Function keys
        case SDL_SCANCODE_F1: return XK_F1;
        case SDL_SCANCODE_F2: return XK_F2;
        case SDL_SCANCODE_F3: return XK_F3;
        case SDL_SCANCODE_F4: return XK_F4;
        case SDL_SCANCODE_F5: return XK_F5;
        case SDL_SCANCODE_F6: return XK_F6;
        case SDL_SCANCODE_F7: return XK_F7;
        case SDL_SCANCODE_F8: return XK_F8;
        case SDL_SCANCODE_F9: return XK_F9;
        case SDL_SCANCODE_F10: return XK_F10;
        case SDL_SCANCODE_F11: return XK_F11;
        case SDL_SCANCODE_F12: return XK_F12;
        
        // Modifiers
        case SDL_SCANCODE_LSHIFT: return XK_Shift_L;
        case SDL_SCANCODE_RSHIFT: return XK_Shift_R;
        case SDL_SCANCODE_LCTRL: return XK_Control_L;
        case SDL_SCANCODE_RCTRL: return XK_Control_R;
        case SDL_SCANCODE_LALT: return XK_Alt_L;
        case SDL_SCANCODE_RALT: return XK_Alt_R;
        case SDL_SCANCODE_LGUI: return XK_Super_L;
        case SDL_SCANCODE_RGUI: return XK_Super_R;
        
        // Special keys
        case SDL_SCANCODE_RETURN: return XK_Return;
        case SDL_SCANCODE_ESCAPE: return XK_Escape;
        case SDL_SCANCODE_BACKSPACE: return XK_BackSpace;
        case SDL_SCANCODE_TAB: return XK_Tab;
        case SDL_SCANCODE_SPACE: return XK_space;
        case SDL_SCANCODE_DELETE: return XK_Delete;
        case SDL_SCANCODE_INSERT: return XK_Insert;
        case SDL_SCANCODE_HOME: return XK_Home;
        case SDL_SCANCODE_END: return XK_End;
        case SDL_SCANCODE_PAGEUP: return XK_Page_Up;
        case SDL_SCANCODE_PAGEDOWN: return XK_Page_Down;
        
        // Arrow keys
        case SDL_SCANCODE_RIGHT: return XK_Right;
        case SDL_SCANCODE_LEFT: return XK_Left;
        case SDL_SCANCODE_DOWN: return XK_Down;
        case SDL_SCANCODE_UP: return XK_Up;
        
        // Symbols
        case SDL_SCANCODE_MINUS: return XK_minus;
        case SDL_SCANCODE_EQUALS: return XK_equal;
        case SDL_SCANCODE_LEFTBRACKET: return XK_bracketleft;
        case SDL_SCANCODE_RIGHTBRACKET: return XK_bracketright;
        case SDL_SCANCODE_BACKSLASH: return XK_backslash;
        case SDL_SCANCODE_SEMICOLON: return XK_semicolon;
        case SDL_SCANCODE_APOSTROPHE: return XK_apostrophe;
        case SDL_SCANCODE_GRAVE: return XK_grave;
        case SDL_SCANCODE_COMMA: return XK_comma;
        case SDL_SCANCODE_PERIOD: return XK_period;
        case SDL_SCANCODE_SLASH: return XK_slash;
        
        // Keypad
        case SDL_SCANCODE_KP_DIVIDE: return XK_KP_Divide;
        case SDL_SCANCODE_KP_MULTIPLY: return XK_KP_Multiply;
        case SDL_SCANCODE_KP_MINUS: return XK_KP_Subtract;
        case SDL_SCANCODE_KP_PLUS: return XK_KP_Add;
        case SDL_SCANCODE_KP_ENTER: return XK_KP_Enter;
        case SDL_SCANCODE_KP_1: return XK_KP_1;
        case SDL_SCANCODE_KP_2: return XK_KP_2;
        case SDL_SCANCODE_KP_3: return XK_KP_3;
        case SDL_SCANCODE_KP_4: return XK_KP_4;
        case SDL_SCANCODE_KP_5: return XK_KP_5;
        case SDL_SCANCODE_KP_6: return XK_KP_6;
        case SDL_SCANCODE_KP_7: return XK_KP_7;
        case SDL_SCANCODE_KP_8: return XK_KP_8;
        case SDL_SCANCODE_KP_9: return XK_KP_9;
        case SDL_SCANCODE_KP_0: return XK_KP_0;
        case SDL_SCANCODE_KP_PERIOD: return XK_KP_Decimal;
        
        // Lock keys
        case SDL_SCANCODE_CAPSLOCK: return XK_Caps_Lock;
        case SDL_SCANCODE_NUMLOCKCLEAR: return XK_Num_Lock;
        case SDL_SCANCODE_SCROLLLOCK: return XK_Scroll_Lock;
        
        default:
        NSLog(@"⚠️ [ScrcpyVNCClient] Unmapped SDL scancode: %d", scancode);
        return 0;
    }
}

#pragma mark - Notification Handlers

/// 处理断开连接请求通知
/// - Parameter notification: 通知对象
- (void)handleDisconnectRequest:(NSNotification *)notification {
    NSLog(@"🔔 [ScrcpyVNCClient] Received disconnect request notification");
    
    // 检查当前是否有活跃连接
    if (_connected && self.scrcpyStatus != ScrcpyStatusDisconnected) {
        NSLog(@"🔌 [ScrcpyVNCClient] Stopping VNC connection due to disconnect request");
        [self stopVNC];
    } else {
        NSLog(@"ℹ️ [ScrcpyVNCClient] No active VNC connection to disconnect");
    }
}

#pragma mark - VNC Zoom Handling

- (CGSize)renderScreenSize {
    if (_renderScreenSize.width > 0 && _renderScreenSize.height > 0) {
        return _renderScreenSize;
    }
    
    // 获取当前渲染器输出的实际尺寸
    int width, height;
    SDL_GetRendererOutputSize(self.currentRenderer, &width, &height);
    _renderScreenSize = CGSizeMake(width, height);
    return _renderScreenSize;
}

/// 处理VNC缩放通知
/// - Parameter notification: 通知对象，包含缩放比例和是否完成的信息
- (void)handleVNCZoomNotification:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGFloat rawScale = [userInfo[@"scale"] floatValue];
    CGFloat centerX = [userInfo[@"centerX"] floatValue];
    CGFloat centerY = [userInfo[@"centerY"] floatValue];
    BOOL isFinished = [userInfo[@"isFinished"] boolValue];
    
    NSLog(@"🔍 [ZoomDebug] Received VNC zoom notification - raw scale: %.3f, center: (%.2f, %.2f), finished: %@",
          rawScale, centerX, centerY, isFinished ? @"YES" : @"NO");
    
    // 检查是否有活跃的VNC连接
    if (!_connected || !_rfbClient) {
        NSLog(@"⚠️ [ZoomDebug] No active VNC connection for zoom");
        return;
    }
    
    // 获取当前 SDL 渲染窗口大小
    int windowWidth = self.renderScreenSize.width;
    int windowHeight = self.renderScreenSize.height;
    SDL_GetRendererOutputSize(self.currentRenderer, &windowWidth, &windowHeight);
    
    // 计算缩放后新的源渲染区域，使用平滑缩放
    static CGFloat lastRawScale = 1.0;
    static CGFloat lastCenterX = 0.5;
    static CGFloat lastCenterY = 0.5;
    
    // 应用平滑插值因子到缩放参数
    CGFloat smoothingFactor = 0.7; // 缩放平滑系数
    CGFloat smoothedScale = lastRawScale + (rawScale - lastRawScale) * smoothingFactor;
    CGFloat smoothedCenterX = lastCenterX + (centerX - lastCenterX) * smoothingFactor;
    CGFloat smoothedCenterY = lastCenterY + (centerY - lastCenterY) * smoothingFactor;
    
    lastRawScale = smoothedScale;
    lastCenterX = smoothedCenterX;
    lastCenterY = smoothedCenterY;
    
    self.currentRenderingRegion = [RenderRegionCalculator calculateRenderRegionWithScreenSize:self.renderScreenSize
                                                                                    imageSize:self.imagePixelsSize
                                                                                  scaleFactor:smoothedScale centerX:smoothedCenterX centerY:smoothedCenterY];
    NSLog(@"🔍 [ZoomDebug] Smoothed rendering region: sourceRect(%@), targetRect(%@), displaySize(%@), scaledSize(%@)",
          NSStringFromCGRect(self.currentRenderingRegion.sourceRect),
          NSStringFromCGRect(self.currentRenderingRegion.targetRect),
          NSStringFromCGSize(self.currentRenderingRegion.displaySize),
          NSStringFromCGSize(self.currentRenderingRegion.scaledSize));
    
    if (isFinished) {
        // 缩放手势结束，重置状态
        NSLog(@"🔍 [ZoomDebug] VNC zoom gesture completed at center: (%.2f, %.2f)", centerX, centerY);
    }
}

#pragma mark - VNC Drag Handling

/// 处理VNC拖拽通知
/// - Parameter notification: 通知对象，包含拖拽状态和位置信息
- (void)handleVNCDragNotification:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *dragState = userInfo[@"state"];
    CGPoint location = [userInfo[@"location"] CGPointValue];
    CGSize viewSize = [userInfo[@"viewSize"] CGSizeValue];
    CGPoint offset = [userInfo[@"offset"] CGPointValue];
    
    NSLog(@"🎯 [ScrcpyVNCClient] Received VNC drag notification - state: %@, location: (%.1f, %.1f), viewSize: (%.1f, %.1f), offset: (%.1f, %.1f)", 
          dragState, location.x, location.y, viewSize.width, viewSize.height, offset.x, offset.y);
    
    // 检查是否有活跃的VNC连接
    if (!_connected || !_rfbClient) {
        NSLog(@"⚠️ [ScrcpyVNCClient] No active VNC connection for drag");
        return;
    }
    
    // 更新拖拽状态
    if ([dragState isEqualToString:@"began"]) {
        self.isDragging = YES;
        self.lastDragLocation = location;
        self.currentDragOffset = offset;
    } else if ([dragState isEqualToString:@"changed"]) {
        self.currentDragOffset = offset;
    } else if ([dragState isEqualToString:@"ended"] || [dragState isEqualToString:@"cancelled"]) {
        self.isDragging = NO;
        // 累积总偏移量
        self.totalDragOffset = CGPointMake(self.totalDragOffset.x + offset.x, 
                                          self.totalDragOffset.y + offset.y);
        NSLog(@"🎯 [ScrcpyVNCClient] Drag ended, total offset: (%.1f, %.1f)", 
              self.totalDragOffset.x, self.totalDragOffset.y);
    }
}

/// 处理VNC拖拽偏移量通知（使用归一化偏移量）
/// - Parameter notification: 通知对象，包含归一化偏移量信息
- (void)handleVNCDragOffsetNotification:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGPoint normalizedOffset = [userInfo[@"normalizedOffset"] CGPointValue];
    CGSize viewSize = [userInfo[@"viewSize"] CGSizeValue];
    
    NSLog(@"🎯 [ScrcpyVNCClient] Received VNC drag offset notification - normalized offset: (%.3f, %.3f), viewSize: (%.1f, %.1f)", 
          normalizedOffset.x, normalizedOffset.y, viewSize.width, viewSize.height);
    
    // 检查是否有活跃的VNC连接
    if (!_connected || !_rfbClient) {
        NSLog(@"⚠️ [ScrcpyVNCClient] No active VNC connection for drag offset");
        return;
    }
    
    // 更新归一化拖拽偏移量
    self.normalizedDragOffset = normalizedOffset;
    
    // 计算实际的像素偏移量
    CGFloat pixelOffsetX = normalizedOffset.x * self.imagePixelsSize.width;
    CGFloat pixelOffsetY = normalizedOffset.y * self.imagePixelsSize.height;
    
    NSLog(@"🎯 [ScrcpyVNCClient] Updated normalized drag offset: (%.3f, %.3f) -> pixel offset: (%.1f, %.1f)", 
          normalizedOffset.x, normalizedOffset.y, pixelOffsetX, pixelOffsetY);
}

/// 重置拖拽偏移量
- (void)resetDragOffset {
    self.currentDragOffset = CGPointZero;
    self.totalDragOffset = CGPointZero;
    self.normalizedDragOffset = CGPointZero;
    self.isDragging = NO;
    self.lastDragLocation = CGPointZero;
    
    NSLog(@"🔄 [ScrcpyVNCClient] Reset drag offset to zero");
}

/// 处理VNC鼠标事件通知
/// - Parameter notification: 通知对象，包含鼠标事件类型和位置信息
- (void)handleVNCMouseEventNotification:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *eventType = userInfo[@"type"];
    CGPoint location = [userInfo[@"location"] CGPointValue];
    CGSize viewSize = [userInfo[@"viewSize"] CGSizeValue];
    
    NSLog(@"🎯 [ScrcpyVNCClient] Received VNC mouse event - type: %@, location: (%.1f, %.1f), viewSize: (%.1f, %.1f)", 
          eventType, location.x, location.y, viewSize.width, viewSize.height);
    
    // 检查是否有活跃的VNC连接
    if (!_connected || !_rfbClient) {
        NSLog(@"⚠️ [ScrcpyVNCClient] No active VNC connection for mouse event");
        return;
    }
    
    // 选择性的性能优化：在高频移动事件时跳过部分帧
    static NSTimeInterval lastMouseEventTime = 0;
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    BOOL isHighFrequencyEvent = [eventType isEqualToString:@"mouseMove"] || [eventType isEqualToString:@"mouseDrag"];
    
    if (isHighFrequencyEvent && (currentTime - lastMouseEventTime) < 0.016) { // 限制为60FPS
        return; // 跳过这个事件以减少网络负载
    }
    lastMouseEventTime = currentTime;
    
    if ([eventType isEqualToString:@"mouseMove"]) {
        // 鼠标移动事件
        [self sendMouseMoveToLocation:location];
    } else if ([eventType isEqualToString:@"mouseClick"]) {
        // 鼠标点击事件
        BOOL isRightClick = [userInfo[@"isRightClick"] boolValue];
        [self sendMouseClickAtLocation:location isRightClick:isRightClick];
    } else if ([eventType isEqualToString:@"mouseDragStart"]) {
        // 开始拖拽事件
        [self sendMouseDragStartAtLocation:location];
    } else if ([eventType isEqualToString:@"mouseDrag"]) {
        // 拖拽移动事件
        [self sendMouseDragToLocation:location];
    } else if ([eventType isEqualToString:@"mouseDragEnd"]) {
        // 结束拖拽事件
        [self sendMouseDragEndAtLocation:location];
    } else if ([eventType isEqualToString:@"mouseWheel"]) {
        // 鼠标滚轮事件
        int deltaX = [userInfo[@"deltaX"] intValue];
        int deltaY = [userInfo[@"deltaY"] intValue];
        [self sendMouseWheelAtLocation:location deltaX:deltaX deltaY:deltaY];
    } else {
        NSLog(@"⚠️ [ScrcpyVNCClient] Unknown mouse event type: %@", eventType);
    }
}

#pragma mark - Custom VNC Functions

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

#pragma mark - Upper Layer Gesture Interface Implementation

/*
 * 优化后的VNC鼠标移动和拖拽实现
 * 
 * 基于libvncclient最佳实践的关键改进：
 * 1. 正确的按钮状态管理：使用位运算维护持久的buttonMask状态
 * 2. 精确的坐标处理：使用round()函数避免浮点精度问题，添加边界检查
 * 3. 标准的拖拽手势模式：
 *    - dragStart: 移动到位置 -> 按下按钮 -> 设置buttonMask
 *    - dragMove: 发送带buttonMask的移动事件（保持按钮按下状态）
 *    - dragEnd: 清除buttonMask -> 发送释放事件
 * 4. 滚轮事件优化：使用临时按钮状态，立即恢复原状态
 * 5. 错误处理：检查SendPointerEvent返回值，提供适当的错误日志
 * 6. 性能优化：避免发送重复的相同位置事件
 * 
 * 参考：/Users/ethan/Src/github.com/libvncserver/examples 中的最佳实践模式
 */

/// 获取VNC按钮掩码对应的人类可读字符串（用于调试）
- (NSString *)buttonMaskDescription:(int)buttonMask {
    NSMutableArray *buttons = [NSMutableArray array];
    if (buttonMask & rfbButton1Mask) [buttons addObject:@"Left"];
    if (buttonMask & rfbButton2Mask) [buttons addObject:@"Middle"];
    if (buttonMask & rfbButton3Mask) [buttons addObject:@"Right"];
    if (buttonMask & rfbButton4Mask) [buttons addObject:@"WheelUp"];
    if (buttonMask & rfbButton5Mask) [buttons addObject:@"WheelDown"];
    
    return buttons.count > 0 ? [buttons componentsJoinedByString:@"+"] : @"None";
}

/// 验证VNC连接状态和图像尺寸是否有效
- (BOOL)isValidForMouseEvents {
    if (!_rfbClient || !_connected) {
        NSLog(@"⚠️ [ScrcpyVNCClient] VNC client not connected");
        return NO;
    }
    
    if (self.imagePixelsSize.width <= 0 || self.imagePixelsSize.height <= 0) {
        NSLog(@"⚠️ [ScrcpyVNCClient] Invalid image size: %.0fx%.0f", 
              self.imagePixelsSize.width, self.imagePixelsSize.height);
        return NO;
    }
    
    return YES;
}

/// 坐标转换辅助方法：将SDL坐标转换为VNC坐标
- (CGPoint)convertSDLToVNCCoordinate:(CGPoint)sdlLocation {
    CGFloat vncX = sdlLocation.x;
    CGFloat vncY = sdlLocation.y;
    
    // 如果有渲染区域信息，需要转换坐标
    if (self.currentRenderingRegion) {
        // 检查点击位置是否在有效的渲染区域内
        CGRect targetRect = self.currentRenderingRegion.targetRect;
        if (!CGRectContainsPoint(targetRect, sdlLocation)) {
            NSLog(@"⚠️ [ScrcpyVNCClient] Click location (%.1f, %.1f) is outside target rect %@", 
                  sdlLocation.x, sdlLocation.y, NSStringFromCGRect(targetRect));
            // 将点击坐标限制在目标区域内
            sdlLocation.x = MAX(targetRect.origin.x, MIN(targetRect.origin.x + targetRect.size.width - 1, sdlLocation.x));
            sdlLocation.y = MAX(targetRect.origin.y, MIN(targetRect.origin.y + targetRect.size.height - 1, sdlLocation.y));
        }
        
        // 将屏幕坐标转换为相对于目标区域的坐标 (0.0 - 1.0)
        CGFloat relativeX = (sdlLocation.x - targetRect.origin.x) / targetRect.size.width;
        CGFloat relativeY = (sdlLocation.y - targetRect.origin.y) / targetRect.size.height;
        
        // 应用拖拽偏移的影响
        CGFloat normalizedDragX = self.normalizedDragOffset.x;
        CGFloat normalizedDragY = self.normalizedDragOffset.y;
        
        // 转换为VNC源图像坐标，考虑拖拽偏移
        CGRect sourceRect = self.currentRenderingRegion.sourceRect;
        vncX = sourceRect.origin.x + (relativeX * sourceRect.size.width) - (normalizedDragX * self.imagePixelsSize.width);
        vncY = sourceRect.origin.y + (relativeY * sourceRect.size.height) - (normalizedDragY * self.imagePixelsSize.height);
        
        // 确保坐标在图像范围内
        vncX = MAX(0, MIN(self.imagePixelsSize.width - 1, vncX));
        vncY = MAX(0, MIN(self.imagePixelsSize.height - 1, vncY));
        
        NSLog(@"🎯 [CoordinateConvert] SDL(%.1f,%.1f) -> Relative(%.3f,%.3f) -> VNC(%.1f,%.1f) [Drag offset: (%.3f,%.3f)]", 
              sdlLocation.x, sdlLocation.y, relativeX, relativeY, vncX, vncY, normalizedDragX, normalizedDragY);
    }
    
    return CGPointMake(vncX, vncY);
}

/// 发送鼠标点击事件到VNC服务器
- (void)sendMouseClickAtLocation:(CGPoint)location isRightClick:(BOOL)isRightClick {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    CGPoint vncLocation = [self convertSDLToVNCCoordinate:location];
    int vncX = (int)round(vncLocation.x);
    int vncY = (int)round(vncLocation.y);
    
    // 边界检查
    vncX = MAX(0, MIN(self.imagePixelsSize.width - 1, vncX));
    vncY = MAX(0, MIN(self.imagePixelsSize.height - 1, vncY));
    
    int clickButtonMask = isRightClick ? rfbButton3Mask : rfbButton1Mask;
    
    NSLog(@"🖱️ [ScrcpyVNCClient] Sending %@ click at SDL(%.1f, %.1f) -> VNC(%d, %d)", 
          isRightClick ? @"right" : @"left", location.x, location.y, vncX, vncY);
    
    // 首先发送鼠标移动到点击位置（确保光标在正确位置）
    rfbBool result = SendPointerEvent(_rfbClient, vncX, vncY, self.buttonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to move to click position");
        return;
    }
    usleep(5000); // 5ms延迟
    
    // 发送按下事件（添加点击按钮到当前按钮状态）
    int pressButtonMask = self.buttonMask | clickButtonMask;
    result = SendPointerEvent(_rfbClient, vncX, vncY, pressButtonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send button press event");
        return;
    }
    usleep(20000); // 20ms延迟（模拟真实点击时间）
    
    // 发送释放事件（移除点击按钮，保持其他按钮状态）
    result = SendPointerEvent(_rfbClient, vncX, vncY, self.buttonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send button release event");
        return;
    }
    
    // 更新当前鼠标位置记录
    self.currentMouseX = vncX;
    self.currentMouseY = vncY;
    
    NSLog(@"✅ [ScrcpyVNCClient] %@ click completed at VNC(%d, %d)", 
          isRightClick ? @"Right" : @"Left", vncX, vncY);
}

/// 发送鼠标移动事件到VNC服务器
- (void)sendMouseMoveToLocation:(CGPoint)location {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    CGPoint vncLocation = [self convertSDLToVNCCoordinate:location];
    int vncX = (int)round(vncLocation.x);
    int vncY = (int)round(vncLocation.y);
    
    // 边界检查
    vncX = MAX(0, MIN(self.imagePixelsSize.width - 1, vncX));
    vncY = MAX(0, MIN(self.imagePixelsSize.height - 1, vncY));
    
    // 简化日志输出，只在debug模式下显示
    #ifdef DEBUG
    static NSTimeInterval lastLogTime = 0;
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if (currentTime - lastLogTime > 0.5) { // 每0.5秒记录一次
        NSLog(@"🖱️ [ScrcpyVNCClient] Mouse move to SDL(%.1f, %.1f) -> VNC(%d, %d), buttonMask: %d", 
              location.x, location.y, vncX, vncY, self.buttonMask);
        lastLogTime = currentTime;
    }
    #endif
    
    // 发送指针事件，保持当前按钮状态
    rfbBool result = SendPointerEvent(_rfbClient, vncX, vncY, self.buttonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send mouse move event");
        return;
    }
    
    // 更新当前鼠标位置记录
    self.currentMouseX = vncX;
    self.currentMouseY = vncY;
}

/// 发送鼠标拖拽开始事件到VNC服务器
- (void)sendMouseDragStartAtLocation:(CGPoint)location {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    CGPoint vncLocation = [self convertSDLToVNCCoordinate:location];
    int vncX = (int)round(vncLocation.x);
    int vncY = (int)round(vncLocation.y);
    
    // 边界检查
    vncX = MAX(0, MIN(self.imagePixelsSize.width - 1, vncX));
    vncY = MAX(0, MIN(self.imagePixelsSize.height - 1, vncY));
    
    NSLog(@"🖱️ [ScrcpyVNCClient] Starting mouse drag at SDL(%.1f, %.1f) -> VNC(%d, %d)", 
          location.x, location.y, vncX, vncY);
    
    // 首先移动到起始位置（确保鼠标在正确位置）
    rfbBool result = SendPointerEvent(_rfbClient, vncX, vncY, 0);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to move to drag start position");
        return;
    }
    
    // 短暂延迟确保位置更新
    usleep(5000); // 5ms延迟
    
    // 发送按下左键事件开始拖拽
    self.buttonMask |= rfbButton1Mask; // 使用按位或设置按钮状态
    result = SendPointerEvent(_rfbClient, vncX, vncY, self.buttonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send drag start event");
        self.buttonMask &= ~rfbButton1Mask; // 恢复按钮状态
        return;
    }
    
    // 更新拖拽状态
    self.isDragging = YES;
    self.currentMouseX = vncX;
    self.currentMouseY = vncY;
    
    NSLog(@"✅ [ScrcpyVNCClient] Drag started at VNC(%d, %d), buttonMask: %d", vncX, vncY, self.buttonMask);
}

/// 发送鼠标拖拽移动事件到VNC服务器
- (void)sendMouseDragToLocation:(CGPoint)location {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    // 确保正在拖拽状态
    if (!self.isDragging || !(self.buttonMask & rfbButton1Mask)) {
        NSLog(@"⚠️ [ScrcpyVNCClient] Not in dragging state, ignoring drag move");
        return;
    }
    
    CGPoint vncLocation = [self convertSDLToVNCCoordinate:location];
    int vncX = (int)round(vncLocation.x);
    int vncY = (int)round(vncLocation.y);
    
    // 边界检查
    vncX = MAX(0, MIN(self.imagePixelsSize.width - 1, vncX));
    vncY = MAX(0, MIN(self.imagePixelsSize.height - 1, vncY));
    
    // 避免发送重复的相同位置
    if (vncX == self.currentMouseX && vncY == self.currentMouseY) {
        return;
    }
    
    // 简化日志输出
    #ifdef DEBUG
    static NSTimeInterval lastDragLogTime = 0;
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if (currentTime - lastDragLogTime > 0.2) { // 每0.2秒记录一次
        NSLog(@"🖱️ [ScrcpyVNCClient] Dragging to SDL(%.1f, %.1f) -> VNC(%d, %d), buttonMask: %d", 
              location.x, location.y, vncX, vncY, self.buttonMask);
        lastDragLogTime = currentTime;
    }
    #endif
    
    // 发送带按钮状态的移动事件（保持拖拽状态）
    rfbBool result = SendPointerEvent(_rfbClient, vncX, vncY, self.buttonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send drag move event");
        return;
    }
    
    // 更新当前位置
    self.currentMouseX = vncX;
    self.currentMouseY = vncY;
}

/// 发送鼠标拖拽结束事件到VNC服务器
- (void)sendMouseDragEndAtLocation:(CGPoint)location {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    CGPoint vncLocation = [self convertSDLToVNCCoordinate:location];
    int vncX = (int)round(vncLocation.x);
    int vncY = (int)round(vncLocation.y);
    
    // 边界检查
    vncX = MAX(0, MIN(self.imagePixelsSize.width - 1, vncX));
    vncY = MAX(0, MIN(self.imagePixelsSize.height - 1, vncY));
    
    NSLog(@"🖱️ [ScrcpyVNCClient] Ending mouse drag at SDL(%.1f, %.1f) -> VNC(%d, %d)", 
          location.x, location.y, vncX, vncY);
    
    // 释放左键按钮状态（使用按位与的补码清除特定按钮）
    self.buttonMask &= ~rfbButton1Mask;
    
    // 发送释放左键事件结束拖拽
    rfbBool result = SendPointerEvent(_rfbClient, vncX, vncY, self.buttonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send drag end event");
    }
    
    // 重置拖拽状态
    self.isDragging = NO;
    self.currentMouseX = vncX;
    self.currentMouseY = vncY;
    
    NSLog(@"✅ [ScrcpyVNCClient] Mouse drag completed at VNC(%d, %d), buttonMask: %d", 
          vncX, vncY, self.buttonMask);
}

/// 发送滚轮事件到VNC服务器
- (void)sendMouseWheelAtLocation:(CGPoint)location deltaX:(int)deltaX deltaY:(int)deltaY {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    CGPoint vncLocation = [self convertSDLToVNCCoordinate:location];
    int vncX = (int)round(vncLocation.x);
    int vncY = (int)round(vncLocation.y);
    
    // 边界检查
    vncX = MAX(0, MIN(self.imagePixelsSize.width - 1, vncX));
    vncY = MAX(0, MIN(self.imagePixelsSize.height - 1, vncY));
    
    NSLog(@"🖱️ [ScrcpyVNCClient] Sending mouse wheel at SDL(%.1f, %.1f) -> VNC(%d, %d), delta: (%d, %d)", 
          location.x, location.y, vncX, vncY, deltaX, deltaY);
    
    // VNC滚轮事件通过按钮4和5实现（向上和向下滚动）
    rfbBool result;
    if (deltaY > 0) {
        // 向上滚动 - 使用临时按钮状态
        int wheelButtonMask = self.buttonMask | rfbButton4Mask;
        result = SendPointerEvent(_rfbClient, vncX, vncY, wheelButtonMask);
        if (result) {
            usleep(10000); // 10ms延迟
            SendPointerEvent(_rfbClient, vncX, vncY, self.buttonMask); // 恢复原按钮状态
        }
    } else if (deltaY < 0) {
        // 向下滚动 - 使用临时按钮状态
        int wheelButtonMask = self.buttonMask | rfbButton5Mask;
        result = SendPointerEvent(_rfbClient, vncX, vncY, wheelButtonMask);
        if (result) {
            usleep(10000); // 10ms延迟
            SendPointerEvent(_rfbClient, vncX, vncY, self.buttonMask); // 恢复原按钮状态
        }
    }
    
    // 处理水平滚动（如果支持）
    if (deltaX != 0) {
        // 水平滚动可以通过按钮6和7实现（如果服务端支持）
        NSLog(@"🖱️ [ScrcpyVNCClient] Horizontal scroll detected, deltaX: %d (not implemented)", deltaX);
    }
    
    // 更新当前位置
    self.currentMouseX = vncX;
    self.currentMouseY = vncY;
}

@end

#pragma mark - VNC Action Execution Extension

@implementation ScrcpyVNCClient (VNCActionExecution)

- (void)executeVNCActions:(NSArray *)actions completion:(void (^)(BOOL success, NSString *error))completion {
    NSLog(@"🔧 [ScrcpyVNCClient] Executing VNC actions: %lu actions", (unsigned long)actions.count);
    
    // Validate VNC connection
    if (!_connected || !_rfbClient) {
        NSString *error = @"VNC client is not connected";
        NSLog(@"❌ [ScrcpyVNCClient] %@", error);
        if (completion) completion(NO, error);
        return;
    }
    
    if (actions.count == 0) {
        NSLog(@"✅ [ScrcpyVNCClient] No VNC actions to execute");
        if (completion) completion(YES, nil);
        return;
    }
    
    // Execute VNC actions on main thread for UI events
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL success = YES;
        NSString *errorMessage = nil;
        
        for (NSDictionary *action in actions) {
            NSString *type = action[@"type"];
            
            if ([type isEqualToString:@"click"]) {
                // Handle click action
                NSNumber *xValue = action[@"x"];
                NSNumber *yValue = action[@"y"];
                
                                 if (xValue && yValue) {
                     CGPoint location = CGPointMake([xValue floatValue], [yValue floatValue]);
                     [self sendMouseClickAtLocation:location isRightClick:NO];
                 } else {
                    success = NO;
                    errorMessage = @"Click action missing x or y coordinates";
                    break;
                }
            } else if ([type isEqualToString:@"key"]) {
                // Handle key action
                NSString *keyCode = action[@"keyCode"];
                
                if (keyCode) {
                    [self sendKeyEvent:keyCode];
                } else {
                    success = NO;
                    errorMessage = @"Key action missing keyCode";
                    break;
                }
            } else if ([type isEqualToString:@"text"]) {
                // Handle text input action
                NSString *text = action[@"text"];
                
                if (text) {
                    [self sendTextInput:text];
                } else {
                    success = NO;
                    errorMessage = @"Text action missing text content";
                    break;
                }
            } else if ([type isEqualToString:@"drag"]) {
                // Handle drag action
                NSNumber *fromX = action[@"fromX"];
                NSNumber *fromY = action[@"fromY"];
                NSNumber *toX = action[@"toX"];
                NSNumber *toY = action[@"toY"];
                
                if (fromX && fromY && toX && toY) {
                    CGPoint fromLocation = CGPointMake([fromX floatValue], [fromY floatValue]);
                    CGPoint toLocation = CGPointMake([toX floatValue], [toY floatValue]);
                    [self sendMouseDragFromLocation:fromLocation toLocation:toLocation];
                } else {
                    success = NO;
                    errorMessage = @"Drag action missing coordinates";
                    break;
                }
            } else {
                success = NO;
                errorMessage = [NSString stringWithFormat:@"Unknown VNC action type: %@", type];
                break;
            }
            
            // Small delay between actions
            [NSThread sleepForTimeInterval:0.1];
        }
        
        if (success) {
            NSLog(@"✅ [ScrcpyVNCClient] All VNC actions executed successfully");
        } else {
            NSLog(@"❌ [ScrcpyVNCClient] VNC actions failed: %@", errorMessage);
        }
        
        if (completion) completion(success, errorMessage);
    });
}

/// Helper method to send a key event
- (void)sendKeyEvent:(NSString *)keyCode {
    // Convert keyCode to VNC key symbol
    int vncKey = [self convertToVNCKey:keyCode];
    if (vncKey == 0) {
        NSLog(@"❌ [ScrcpyVNCClient] Unknown key code: %@", keyCode);
        return;
    }
    
    // Send key press
    rfbBool result = SendKeyEvent(_rfbClient, vncKey, TRUE);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send key press for: %@", keyCode);
        return;
    }
    
    // Small delay
    usleep(50000); // 50ms
    
    // Send key release
    result = SendKeyEvent(_rfbClient, vncKey, FALSE);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send key release for: %@", keyCode);
        return;
    }
    
    NSLog(@"✅ [ScrcpyVNCClient] Key event sent: %@", keyCode);
}

/// Helper method to send text input
- (void)sendTextInput:(NSString *)text {
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar character = [text characterAtIndex:i];
        
        // Convert character to VNC key symbol
        int vncKey = [self convertCharacterToVNCKey:character];
        if (vncKey == 0) {
            NSLog(@"❌ [ScrcpyVNCClient] Cannot convert character to VNC key: %C", character);
            continue;
        }
        
        // Send key press
        rfbBool result = SendKeyEvent(_rfbClient, vncKey, TRUE);
        if (!result) {
            NSLog(@"❌ [ScrcpyVNCClient] Failed to send key press for character: %C", character);
            continue;
        }
        
        // Small delay
        usleep(20000); // 20ms
        
        // Send key release
        result = SendKeyEvent(_rfbClient, vncKey, FALSE);
        if (!result) {
            NSLog(@"❌ [ScrcpyVNCClient] Failed to send key release for character: %C", character);
        }
        
        // Small delay between characters
        usleep(30000); // 30ms
    }
    
    NSLog(@"✅ [ScrcpyVNCClient] Text input sent: %@", text);
}

/// Helper method to send mouse drag from one location to another
- (void)sendMouseDragFromLocation:(CGPoint)fromLocation toLocation:(CGPoint)toLocation {
    // Start drag at from location
    [self sendMouseDragStartAtLocation:fromLocation];
    
    // Small delay
    usleep(100000); // 100ms
    
    // Move to destination
    [self sendMouseDragToLocation:toLocation];
    
    // Small delay
    usleep(100000); // 100ms
    
    // End drag at destination
    [self sendMouseDragEndAtLocation:toLocation];
    
    NSLog(@"✅ [ScrcpyVNCClient] Mouse drag completed from (%.1f, %.1f) to (%.1f, %.1f)", 
          fromLocation.x, fromLocation.y, toLocation.x, toLocation.y);
}

/// Convert key code string to VNC key symbol
- (int)convertToVNCKey:(NSString *)keyCode {
    // Map common key codes to VNC key symbols
    NSDictionary *keyMap = @{
        @"KEYCODE_HOME": @(XK_Home),
        @"KEYCODE_BACK": @(XK_BackSpace),
        @"KEYCODE_MENU": @(XK_Menu),
        @"KEYCODE_ENTER": @(XK_Return),
        @"KEYCODE_SPACE": @(XK_space),
        @"KEYCODE_TAB": @(XK_Tab),
        @"KEYCODE_ESCAPE": @(XK_Escape),
        @"KEYCODE_DEL": @(XK_Delete),
        @"KEYCODE_DPAD_UP": @(XK_Up),
        @"KEYCODE_DPAD_DOWN": @(XK_Down),
        @"KEYCODE_DPAD_LEFT": @(XK_Left),
        @"KEYCODE_DPAD_RIGHT": @(XK_Right),
    };
    
    NSNumber *keySymbol = keyMap[keyCode];
    return keySymbol ? [keySymbol intValue] : 0;
}

/// Convert character to VNC key symbol
- (int)convertCharacterToVNCKey:(unichar)character {
    // For ASCII characters, VNC key symbols are the same as ASCII values
    if (character >= 32 && character <= 126) {
        return (int)character;
    }
    
    // Handle special characters
    switch (character) {
        case '\n':
        case '\r':
            return XK_Return;
        case '\t':
            return XK_Tab;
        case '\b':
            return XK_BackSpace;
        default:
            return 0; // Unknown character
    }
}

@end

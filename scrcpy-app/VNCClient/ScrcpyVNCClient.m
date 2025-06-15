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

#import <objc/runtime.h>
#import <SDL2/SDL.h>
#import <SDL2/SDL_mouse.h>
#import <rfb/rfbclient.h>
#import <rfb/keysym.h>
#import <stdlib.h>
#import <arpa/inet.h>

#define CFRunLoopNormalInterval     0.5f
#define CFRunLoopHandledSourceInterval 0.0001f

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
        
        // 初始化拖拽相关属性
        self.isDragging = NO;
        self.lastDragLocation = CGPointZero;
        self.currentMouseX = 0;
        self.currentMouseY = 0;
        self.buttonMask = 0;
        
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

    int x, y, buttonMask = 0;   // Current mouse position
    struct { int sdl; int rfb; } buttonMapping[]={
        {1, rfbButton1Mask}, {2, rfbButton2Mask}, {3, rfbButton3Mask},
        {4, rfbButton4Mask}, {5, rfbButton5Mask}, {0,0}
    };
    
    // 鼠标点击状态跟踪
    BOOL mouseButtonPressed = NO;
    int pressedButton = 0;
    int pressedX = 0, pressedY = 0;
    NSTimeInterval pressTime = 0;
    const NSTimeInterval clickThreshold = 0.3; // 300ms内认为是点击

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
            break;
        case SDL_MOUSEBUTTONDOWN: {
            // 记录按下状态，但不立即发送事件
            x = e.button.x;
            y = e.button.y;
            pressedButton = e.button.button;
            
            // 映射按钮
            for (int i = 0; buttonMapping[i].sdl; i++) {
                if (pressedButton == buttonMapping[i].sdl) {
                    pressedButton = buttonMapping[i].rfb;
                    break;
                }
            }
            
            mouseButtonPressed = YES;
            pressedX = x;
            pressedY = y;
            pressTime = [[NSDate date] timeIntervalSince1970];
            
            NSLog(@"🖱️ [ScrcpyVNCClient] Mouse button down at (%d, %d), button: %d", x, y, pressedButton);
            break;
        }
        case SDL_MOUSEBUTTONUP: {
            // 检查是否是点击事件
            if (mouseButtonPressed && pressedButton == e.button.button) {
                NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
                NSTimeInterval timeDiff = currentTime - pressTime;
                
                // 检查时间间隔和位置是否在合理范围内（点击）
                int moveDistance = abs(e.button.x - pressedX) + abs(e.button.y - pressedY);
                
                if (timeDiff <= clickThreshold && moveDistance <= 5) {
                    // 这是一个点击事件
                    NSLog(@"🖱️ [ScrcpyVNCClient] Mouse click detected at (%d, %d), button: %d", e.button.x, e.button.y, pressedButton);
                    
                    // 发送按下事件
                    buttonMask |= pressedButton;
                    SendPointerEvent(_rfbClient, e.button.x, e.button.y, buttonMask);
                    
                    // 短暂延迟后发送释放事件
                    usleep(50000); // 50ms delay
                    buttonMask &= ~pressedButton;
                    SendPointerEvent(_rfbClient, e.button.x, e.button.y, buttonMask);
                } else {
                    NSLog(@"🖱️ [ScrcpyVNCClient] Mouse drag detected (time: %.3fs, distance: %d), ignoring", timeDiff, moveDistance);
                }
            }
            
            // 重置状态
            mouseButtonPressed = NO;
            pressedButton = 0;
            break;
        }
        case SDL_MOUSEMOTION: {
            // 只处理鼠标移动，不处理按钮状态
            x = e.motion.x;
            y = e.motion.y;
            
            // 如果鼠标按钮没有按下，只发送位置更新
            if (!mouseButtonPressed) {
                SendPointerEvent(_rfbClient, x, y, 0);
            } else {
                // 如果鼠标按钮按下，发送拖拽事件
                SendPointerEvent(_rfbClient, x, y, pressedButton);
            }
            break;
        }
                
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
        client->appData.useRemoteCursor = TRUE;
        
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
        
        // Update status when SDL window appears
        self.scrcpyStatus = ScrcpyStatusSDLWindowAppeared;
        ScrcpyUpdateStatus(ScrcpyStatusSDLWindowAppeared, "VNC connection established and window appeared");
        
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
            CGFloat dragOffsetX = -self.normalizedDragOffset.x * self.imagePixelsSize.width;
            CGFloat dragOffsetY = -self.normalizedDragOffset.y * self.imagePixelsSize.height;
            
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
        
        // 如果光标可见，更新SDL光标位置
        if (self.cursorVisible && self.vncCursor) {
            // 将VNC坐标转换为SDL窗口坐标
            // 这里需要根据缩放和偏移进行调整
            int sdlX = x;
            int sdlY = y;
            
            // 应用缩放和偏移
            if (self.currentRenderingRegion) {
                CGFloat scaleX = self.currentRenderingRegion.targetRect.size.width / self.currentRenderingRegion.sourceRect.size.width;
                CGFloat scaleY = self.currentRenderingRegion.targetRect.size.height / self.currentRenderingRegion.sourceRect.size.height;
                
                sdlX = (x - self.currentRenderingRegion.sourceRect.origin.x) * scaleX + self.currentRenderingRegion.targetRect.origin.x;
                sdlY = (y - self.currentRenderingRegion.sourceRect.origin.y) * scaleY + self.currentRenderingRegion.targetRect.origin.y;
            }
            
            // 设置SDL光标位置
            SDL_WarpMouseInWindow(NULL, sdlX, sdlY);
        }
        
        return TRUE;
    });
    
    _rfbClient->GetCredential = GetCredentialBlock;
    GetSet_GetCredentialBlockIMP(_rfbClient, imp_implementationWithBlock(^rfbCredential *(rfbClient* cl, int credentialType){
        rfbCredential *c = malloc(sizeof(rfbCredential));
        if (!c) {
            return NULL;
        }
        
        c->userCredential.username = malloc(RFB_BUF_SIZE);
        strcpy(c->userCredential.username, user.UTF8String);
        if (!c->userCredential.username) {
            free(c);
            return NULL;
        }
        
        c->userCredential.password = malloc(RFB_BUF_SIZE);
        strcpy(c->userCredential.password, password.UTF8String);
        if (!c->userCredential.password) {
            free(c->userCredential.username);
            free(c);
            return NULL;
        }

        if(credentialType != rfbCredentialTypeUser) {
            rfbClientErr("something else than username and password required for authentication\n");
            return NULL;
        }

        rfbClientLog("vnc username and password required for authentication!\n");

        /* remove trailing newlines */
        c->userCredential.username[strcspn(c->userCredential.username, "\n")] = 0;
        c->userCredential.password[strcspn(c->userCredential.password, "\n")] = 0;

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
    
    // 计算缩放后新的源渲染区域
    self.currentRenderingRegion = [RenderRegionCalculator calculateRenderRegionWithScreenSize:self.renderScreenSize
                                                                                    imageSize:self.imagePixelsSize
                                                                                  scaleFactor:rawScale centerX:centerX centerY:centerY];
    NSLog(@"🔍 [ZoomDebug] Calculated rendering region: sourceRect(%@), targetRect(%@), displaySize(%@), scaledSize(%@)",
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

@end

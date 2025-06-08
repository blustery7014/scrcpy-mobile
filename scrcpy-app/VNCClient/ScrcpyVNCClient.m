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

#import <objc/runtime.h>
#import <SDL2/SDL.h>
#import <rfb/rfbclient.h>
#import <rfb/keysym.h>

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
        
        // 监听断开连接通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDisconnectRequest:)
                                                     name:@"ScrcpyRequestDisconnectNotification"
                                                   object:nil];
    }
    return self;
}

-(void)dealloc {
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
        case SDL_MOUSEBUTTONUP:
        case SDL_MOUSEBUTTONDOWN:
        case SDL_MOUSEMOTION: {
            int state, i;
            if (e.type == SDL_MOUSEMOTION) {
                x = e.motion.x;
                y = e.motion.y;
                state = e.motion.state;
            }
            else {
                x = e.button.x;
                y = e.button.y;
                state = e.button.button;
                for (i = 0; buttonMapping[i].sdl; i++) {
                    if (state == buttonMapping[i].sdl) {
                        state = buttonMapping[i].rfb;
                        if (e.type == SDL_MOUSEBUTTONDOWN)
                            buttonMask |= state;
                        else
                            buttonMask &= ~state;
                        break;
                    }
                }
            }
            SendPointerEvent(_rfbClient, x, y, buttonMask);
            buttonMask &= ~(rfbButton4Mask | rfbButton5Mask);
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
        int width=client->width,height=client->height, depth=client->format.bitsPerPixel;

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
        SetFormatAndEncodings(client);

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
        
        NSLog(@"SDL Window: %@", self.sdlDelegate.window);
        self.sdlDelegate.window.windowScene = self.currentScene;
        NSLog(@"SDL Window Scene: %@", self.sdlDelegate.window.windowScene);
        [self.sdlDelegate.window makeKeyWindow];
        NSLog(@"SDL Window RootController: %@", self.sdlDelegate.window.rootViewController);
        
        // Update status when SDL window appears
        self.scrcpyStatus = ScrcpyStatusSDLWindowAppeared;
        ScrcpyUpdateStatus(ScrcpyStatusSDLWindowAppeared, "VNC connection established and window appeared");
        
        SDL_RenderSetLogicalSize(sdlRenderer, width, height);
        sdlTexture = SDL_CreateTexture(sdlRenderer,
                           SDL_PIXELFORMAT_ARGB8888,
                           SDL_TEXTUREACCESS_STREAMING,
                           width, height);
        
        if(!sdlTexture) rfbClientErr("resize: error creating texture: %s\n", SDL_GetError());
        
        return true;
    });
    
    _rfbClient->GotFrameBufferUpdate = GotFrameBufferUpdateBlock;
    GetSet_GotFrameBufferUpdateBlockIMP(_rfbClient, imp_implementationWithBlock(^void(rfbClient* cl, int x, int y, int w, int h){
        SDL_Surface *sdl = rfbClientGetClientData(cl, SDL_Init);
        SDL_Rect r = {x, y, w, h};
        
        if(SDL_UpdateTexture(sdlTexture, &r, sdl->pixels + y*sdl->pitch + x*4, sdl->pitch) < 0)
            rfbClientErr("update: failed to update texture: %s\n", SDL_GetError());
        
        if(SDL_RenderClear(sdlRenderer) < 0)
            rfbClientErr("update: failed to clear renderer: %s\n", SDL_GetError());
        
        if(SDL_RenderCopy(sdlRenderer, sdlTexture, NULL, NULL) < 0)
            rfbClientErr("update: failed to copy texture to renderer: %s\n", SDL_GetError());
        
        SDL_RenderPresent(sdlRenderer);
    }));
    
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

@end

//
//  SDLVNCClient.m
//  VNCClient
//
//  Created by Ethan on 12/16/24.
//

#import "ScrcpyVNCClient.h"
#import "ScrcpyBlockWrapper.h"
#import "ScrcpyMenuView.h"

#import <objc/runtime.h>
#import <SDL2/SDL.h>
#import <rfb/rfbclient.h>
#import <rfb/keysym.h>

#define CFRunLoopNormalInterval     0.6f
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

@implementation SDLUIKitDelegate (Extend)

- (void)postFinishLaunch {
    // Hihack postFinishLaunch to prevent SDL run forward_main function
    NSLog(@"SDL Hijacked -[SDLUIKitDelegate postFinishLaunch]");
}

@end

@interface ScrcpyVNCClient () <ScrcpyMenuViewDelegate>
@property (nonatomic, strong) ScrcpyMenuView *menuView;
@property (nonatomic, assign) rfbClient *currentClient;
@property (nonatomic, assign) BOOL isConnected;
@end

@implementation ScrcpyVNCClient

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.sdlDelegate = [[SDLUIKitDelegate alloc] init];
        
        // Mock Delegate Method
        [self.sdlDelegate application:UIApplication.sharedApplication didFinishLaunchingWithOptions:@{}];
        
        // 监听断开连接通知
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stopVNC) name:ScrcpyRequestDisconnectNotification object:nil];
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

-(void)start:(NSString *)host port:(NSString *)port user:(NSString *)user password:(NSString *)password
{
    NSLog(@"✅ SDL_main start vnc client");
    
    // Mock ApplicationDelegate methods
    [self.sdlDelegate application:[UIApplication sharedApplication] didFinishLaunchingWithOptions:@{}];
    
    // Execute SDL main
    SDL_Init(SDL_INIT_VIDEO | SDL_INIT_NOPARACHUTE);
    atexit(SDL_Quit);
    signal(SIGINT, exit);
    
    rfbClient* cl;
    SDL_Event e;
    __block int sdlFlags;
    
    __block SDL_Texture *sdlTexture = NULL;
    __block SDL_Renderer *sdlRenderer = NULL;
    __block SDL_Window *sdlWindow = NULL;

    cl=rfbGetClient(8, 3, 4);
    cl->canHandleNewFBSize = true;
    cl->listenPort = LISTEN_PORT_OFFSET;
    cl->listen6Port = LISTEN_PORT_OFFSET;
    
    // Store reference to current client
    self.currentClient = cl;
    
    // For block with only 1 argument, do not required to invoke between BlockEntry mapping
    cl->MallocFrameBuffer = (MallocFrameBufferProc)imp_implementationWithBlock(^rfbBool(rfbClient* client){
        int width=client->width,height=client->height, depth=client->format.bitsPerPixel;

        sdlFlags |= SDL_WINDOW_RESIZABLE;
        sdlFlags |= SDL_WINDOW_ALLOW_HIGHDPI;

        /* (re)create the surface used as the client's framebuffer */
        SDL_FreeSurface(rfbClientGetClientData(client, SDL_Init));
        SDL_Surface* sdl=SDL_CreateRGBSurface(0, width, height, depth, 0, 0, 0, 0);
        if(!sdl) rfbClientErr("resize: error creating surface: %s\n", SDL_GetError());

        rfbClientSetClientData(client, SDL_Init, sdl);
        client->width = sdl->pitch / (depth / 8);
        client->frameBuffer=sdl->pixels;

        client->format.bitsPerPixel=depth;
        client->format.redShift=sdl->format->Rshift;
        client->format.greenShift=sdl->format->Gshift;
        client->format.blueShift=sdl->format->Bshift;
        client->format.redMax=sdl->format->Rmask>>client->format.redShift;
        client->format.greenMax=sdl->format->Gmask>>client->format.greenShift;
        client->format.blueMax=sdl->format->Bmask>>client->format.blueShift;
        SetFormatAndEncodings(client);

        /* create or resize the window */
        if(!sdlWindow) {
            sdlWindow = SDL_CreateWindow(client->desktopName,
                         SDL_WINDOWPOS_UNDEFINED,
                         SDL_WINDOWPOS_UNDEFINED,
                         width,
                         height,
                         sdlFlags);
            if(!sdlWindow) rfbClientErr("resize: error creating window: %s\n", SDL_GetError());
        } else {
            SDL_SetWindowSize(sdlWindow, width, height);
        }

        /* create the renderer if it does not already exist */
        if(!sdlRenderer) {
            sdlRenderer = SDL_CreateRenderer(sdlWindow, -1, 0);
            if(!sdlRenderer) rfbClientErr("resize: error creating renderer: %s\n", SDL_GetError());
            SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");  /* make the scaled rendering look smoother. */
        }
        SDL_RenderSetLogicalSize(sdlRenderer, width, height);  /* this is a departure from the SDL1.2-based version, but more in the sense of a VNC viewer in keeeping aspect ratio */

        /* (re)create the texture that sits in between the surface->pixels and the renderer */
        if(sdlTexture)
            SDL_DestroyTexture(sdlTexture);
        sdlTexture = SDL_CreateTexture(sdlRenderer,
                           SDL_PIXELFORMAT_ARGB8888,
                           SDL_TEXTUREACCESS_STREAMING,
                           width, height);
        if(!sdlTexture)
            rfbClientErr("resize: error creating texture: %s\n", SDL_GetError());
        
        return true;
    });
    
    cl->GotFrameBufferUpdate = GotFrameBufferUpdateBlock;
    GetSet_GotFrameBufferUpdateBlockIMP(cl, imp_implementationWithBlock(^void(rfbClient* cl, int x, int y, int w, int h){
        SDL_Surface *sdl = rfbClientGetClientData(cl, SDL_Init);
        /* update texture from surface->pixels */
        SDL_Rect r = {x, y, w, h};
         if(SDL_UpdateTexture(sdlTexture, &r, sdl->pixels + y*sdl->pitch + x*4, sdl->pitch) < 0)
            rfbClientErr("update: failed to update texture: %s\n", SDL_GetError());
        /* copy texture to renderer and show */
        if(SDL_RenderClear(sdlRenderer) < 0)
            rfbClientErr("update: failed to clear renderer: %s\n", SDL_GetError());
        if(SDL_RenderCopy(sdlRenderer, sdlTexture, NULL, NULL) < 0)
            rfbClientErr("update: failed to copy texture to renderer: %s\n", SDL_GetError());
        SDL_RenderPresent(sdlRenderer);
    }));
    
    cl->GetCredential = GetCredentialBlock;
    GetSet_GetCredentialBlockIMP(cl, imp_implementationWithBlock(^rfbCredential *(rfbClient* cl, int credentialType){
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
    
    const char *argv[] = {"scrcpy", [NSString stringWithFormat:@"%@:%@", host, port].UTF8String};
    int argc = sizeof(argv) / sizeof(char *);
    NSLog(@"argc: %d", argc);
    
    if(!rfbInitClient(cl, &argc, (char **)argv)) {
        cl = NULL; /* rfbInitClient has already freed the client struct */
        self.currentClient = NULL;
        return;
    }
    
    // Mark as connected
    self.isConnected = YES;
    
    NSLog(@"SDL Window: %@", self.sdlDelegate.window);
    self.sdlDelegate.window.windowScene = self.currentScene;
    NSLog(@"SDL Window Scene: %@", self.sdlDelegate.window.windowScene);
    [self.sdlDelegate.window makeKeyWindow];
    
    // Show ScrcpyMenuView after successful connection
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showMenuView];
        
        // 发送连接成功状态通知
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyStatusUpdated" object:nil userInfo:@{
            @"status": @(1), // ScrcpyStatusConnected
            @"message": @"VNC connected"
        }];
        
        NSLog(@"🔌 [ScrcpyVNCClient] VNC connection established - menu view shown, status notification sent");
    });
    
    int x, y, buttonMask = 0;   // Current mouse position
    struct { int sdl; int rfb; } buttonMapping[]={
        {1, rfbButton1Mask},
        {2, rfbButton2Mask},
        {3, rfbButton3Mask},
        {4, rfbButton4Mask},
        {5, rfbButton5Mask},
        {0,0}
    };
    
    while(self.isConnected) {
        if(SDL_PollEvent(&e)) {
            /*
             handleSDLEvent() return 0 if user requested window close.
             In this case, handleSDLEvent() will have called cleanup().
             */
            NSLog(@"SDL Event Type: %d", e.type);
           
            switch(e.type) {
            case SDL_WINDOWEVENT:
                switch (e.window.event) {
                    case SDL_WINDOWEVENT_EXPOSED:
                        SendFramebufferUpdateRequest(cl, 0, 0, cl->width, cl->height, FALSE);
                        break;
                    
                    case SDL_WINDOWEVENT_RESIZED:
                        SendExtDesktopSize(cl, e.window.data1, e.window.data2);
                        break;
                        
                    case SDL_WINDOWEVENT_FOCUS_GAINED:
                        if (SDL_HasClipboardText()) {
                            char *text = SDL_GetClipboardText();
                            if(text) {
                                rfbClientLog("sending clipboard text '%s'\n", text);
                                SendClientCutText(cl, text, (int)strlen(text));
                            }
                        }
                        break;
                        
                    case SDL_WINDOWEVENT_FOCUS_LOST:
                        NSLog(@"SDL_WINDOWEVENT_FOCUS_LOST");
                        break;
                }
                break;
            case SDL_MOUSEWHEEL:
            {
                break;
            }
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
                SendPointerEvent(cl, x, y, buttonMask);
                buttonMask &= ~(rfbButton4Mask | rfbButton5Mask);
                break;
            }
                    
            case SDL_KEYUP:
            case SDL_KEYDOWN:
                break;
            case SDL_TEXTINPUT:
                break;
            case SDL_QUIT:
                NSLog(@"🔌 [ScrcpyVNCClient] SDL_QUIT event received, breaking VNC loop");
                self.isConnected = NO;
                break;
            default:
                rfbClientLog("ignore SDL event: 0x%x\n", e.type);
            }
        } else {
            int i = WaitForMessage(cl, 500);
            if(i<0) {
                NSLog(@"🔌 [ScrcpyVNCClient] VNC message wait failed, breaking loop");
                self.isConnected = NO;
                break;
            } else {
                if(!HandleRFBServerMessage(cl)) {
                    NSLog(@"🔌 [ScrcpyVNCClient] VNC server message handling failed, breaking loop");
                    self.isConnected = NO;
                    break;
                }
            }
        }
    }
    
    // Hide menu view before cleanup
    dispatch_async(dispatch_get_main_queue(), ^{
        [self hideMenuView];
    });
    
    // Cleanup VNC client
    if (cl) {
        rfbClientCleanup(cl);
    }
    self.currentClient = NULL;
    
    // Clear block IMP to free entry for next client
    GetSet_GetCredentialBlockIMP(cl, nil);
    GetSet_GotFrameBufferUpdateBlockIMP(cl, nil);
    
    NSLog(@"✅ SDL_main end");
}

- (SDLUIKitDelegate *)sdlDelegate {
    if (!_sdlDelegate) {
        _sdlDelegate = [[SDLUIKitDelegate alloc] init];
    }
    return _sdlDelegate;
}

-(void)stopVNC {
    NSLog(@"🔌 [ScrcpyVNCClient] stopVNC called");
    
    // Mark as disconnected
    self.isConnected = NO;
    
    // Call SDL_Quit to send Quit Event
    SDL_Event event;
    event.type = SDL_QUIT;
    SDL_PushEvent(&event);
    
    // Hide menu view
    dispatch_async(dispatch_get_main_queue(), ^{
        [self hideMenuView];
        
        // 发送断开连接状态通知
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyStatusUpdated" object:nil userInfo:@{
            @"status": @(0), // ScrcpyStatusDisconnected
            @"message": @"VNC disconnected"
        }];
        
        NSLog(@"🔌 [ScrcpyVNCClient] VNC disconnection completed - menu view hidden, status notification sent");
    });
}

#pragma mark - Menu View Management

- (void)showMenuView {
    if (!self.menuView) {
        self.menuView = [[ScrcpyMenuView alloc] initWithFrame:CGRectZero];
        self.menuView.delegate = self;
    }
    
    [self.menuView addToActiveWindow];
    NSLog(@"🎨 [ScrcpyVNCClient] Menu view shown");
}

- (void)hideMenuView {
    if (self.menuView) {
        [self.menuView removeFromSuperview];
        self.menuView = nil;
        NSLog(@"🎨 [ScrcpyVNCClient] Menu view hidden");
    }
}

#pragma mark - ScrcpyMenuViewDelegate

- (void)didTapBackButton {
    NSLog(@"🎮 [ScrcpyVNCClient] Back button tapped");
    // VNC equivalent: Send escape key or back gesture
    if (self.currentClient && self.isConnected) {
        // Send Android back key (keycode 4)
        SendKeyEvent(self.currentClient, XK_Escape, TRUE);
        usleep(50000); // 50ms delay
        SendKeyEvent(self.currentClient, XK_Escape, FALSE);
    }
}

- (void)didTapHomeButton {
    NSLog(@"🎮 [ScrcpyVNCClient] Home button tapped");
    // VNC equivalent: Send home key
    if (self.currentClient && self.isConnected) {
        // Send Android home key (Meta key)
        SendKeyEvent(self.currentClient, XK_Super_L, TRUE);
        usleep(50000); // 50ms delay
        SendKeyEvent(self.currentClient, XK_Super_L, FALSE);
    }
}

- (void)didTapSwitchButton {
    NSLog(@"🎮 [ScrcpyVNCClient] Switch button tapped");
    // VNC equivalent: Send recent apps key
    if (self.currentClient && self.isConnected) {
        // Send Alt+Tab for recent apps
        SendKeyEvent(self.currentClient, XK_Alt_L, TRUE);
        SendKeyEvent(self.currentClient, XK_Tab, TRUE);
        usleep(50000); // 50ms delay
        SendKeyEvent(self.currentClient, XK_Tab, FALSE);
        SendKeyEvent(self.currentClient, XK_Alt_L, FALSE);
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

@end

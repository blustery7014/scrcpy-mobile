//
//  ScrcpyADBClient.m
//  Scrcpy Remote
//
//  Created by Ethan on 12/16/24.
//

#import <UIKit/UIKit.h>

#import "ScrcpyADBClient.h"
#import "ADBClient.h"
#import "ScrcpyClientWrapper.h"
#import "scrcpy-porting.h"
#import <SDL2/SDL.h>
#import <libavutil/frame.h>
#import <libavutil/imgutils.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>
#import "ScrcpyRuntime.h"

// C function implementation
void ScrcpySendKeycodeEvent(SDL_Scancode scancode, SDL_Keycode keycode, SDL_Keymod keymod) {
    SDL_Keysym keySym;
    keySym.scancode = scancode;
    keySym.sym = keycode;
    keySym.mod = keymod;
    keySym.unused = 1;
    
    // Send key down event
    {
        SDL_KeyboardEvent keyEvent;
        keyEvent.type = SDL_KEYDOWN;
        keyEvent.state = SDL_PRESSED;
        keyEvent.repeat = '\0';
        keyEvent.keysym = keySym;
        
        SDL_Event event;
        event.type = keyEvent.type;
        event.key = keyEvent;
        
        SDL_PushEvent(&event);
        
        NSLog(@"KEYDOWN EVENT: Post Success");
    }
    
    // Send key up event
    {
        SDL_KeyboardEvent keyEvent;
        keyEvent.type = SDL_KEYUP;
        keyEvent.state = SDL_PRESSED;
        keyEvent.repeat = '\0';
        keyEvent.keysym = keySym;
        
        SDL_Event event;
        event.type = keyEvent.type;
        event.key = keyEvent;
        
        SDL_PushEvent(&event);
        
        NSLog(@"KEYUP EVENT: Post Success");
    }
}

void ScrcpyTryResetVideo(void) {
    static NSTimeInterval lastResetTime = 0;
    if (NSDate.date.timeIntervalSince1970 - lastResetTime < 1.0) {
        return;
    }
    ScrcpySendKeycodeEvent(SDL_SCANCODE_R, SDLK_r, KMOD_LCTRL | KMOD_SHIFT);
    NSLog(@"-> [1] Reset video by LCTRL+SHIFT+R");
    lastResetTime = NSDate.date.timeIntervalSince1970;
}

@interface ScrcpyADBClient ()

@property (nonatomic, strong)  SDLUIKitDelegate  *sdlDelegate;
@property (nonatomic, copy) void (^sessionCompletion)(enum ScrcpyStatus, NSString *);
@property (nonatomic, copy) NSDictionary  *sessionArguments;

// Property for scrcpy status
@property (nonatomic, assign) enum ScrcpyStatus scrcpyStatus;

@end

@implementation ScrcpyADBClient

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onScrcpyStatusUpdated:) name:ScrcpyStatusUpdatedNotificationName object:nil];
        // Observe application enter background
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onApplicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        // Observe application enter foreground
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onApplicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        // Observe disconnect event from scrcpy menu view
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stopScrcpy) name:ScrcpyRequestDisconnectNotification object:nil];
    }
    return self;
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIWindowScene *)currentScene {
    return GetCurrentWindowScene();
}

- (void)setupScrcpyEnvs {
    // Scrcpy SCRCPY_SERVER_PATH to find scrcpy-server under main app bundle
    NSString *serverPath = [[NSBundle mainBundle] pathForResource:@"scrcpy-server" ofType:@""];
    NSLog(@"→ Scrcpy server path: %@", serverPath);
    setenv("SCRCPY_SERVER_PATH", serverPath.UTF8String, 1);
}

- (void)startClient:(NSDictionary *)arguments completion:(nonnull void (^)(enum ScrcpyStatus, NSString * _Nonnull))completion {
    NSLog(@"🟢 Starting connect ADB device..");
    
    // Init scrcpy status
    self.scrcpyStatus = ScrcpyStatusDisconnected;
    
    [self setupScrcpyEnvs];
    
    // Reset audio volume ajust
    // ScrcpyAudioVolumeScale(1.1);
    
    NSString *host = arguments[@"hostReal"];
    NSString *port = arguments[@"port"];
    NSString *serial = [NSString stringWithFormat:@"%@:%@", host, port];

    // Update session completion and arguments
    self.sessionCompletion = completion;
    self.sessionArguments = arguments;
    
    // First kill the ADB server before connecting
    __weak typeof(self) weakSelf = self;
    // Now connect to the ADB device
    [ADBClient.shared executeADBCommandAsync:@[@"connect", serial] callback:^(NSString * _Nullable connectResult, int returnCode) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSLog(@"ADB Result: %@, %@", connectResult, @(returnCode));
        NSLog(@"ADB Devices: %@", [ADBClient.shared adbDevices]);
        
        if (returnCode != 0) {
            NSLog(@"❌ ADB connect failed: %@", connectResult);
            return;
        }
        
        // Notify completion when ADB connected
        strongSelf.sessionCompletion(ScrcpyStatusADBConnected, connectResult);
        
        // Perform selector to prevent runloop hang, this will cause view not rendering
        [self performSelectorOnMainThread:@selector(startScrcpy:) withObject:serial waitUntilDone:NO];
    }];
}

- (NSString *)optionArgumentKeyMapping:(NSString *)key {
    NSDictionary *supportedOptions = @{
        @"maxScreenSize": @"--max-size",
        @"bitRate": @"--video-bit-rate",
        @"videoBitRate": @"--video-bit-rate",
        @"maxFPS": @"--max-fps",
        @"videoCodec": @"--video-codec",
        @"videoBuffer": @"--video-buffer",
    };
    return supportedOptions[key] ?: nil;
}

- (NSString *)reverseOptionArgumentKeyMapping:(NSString *)key {
    NSDictionary *supportedOptions = @{
        @"enableAudio": @"--no-audio",
        @"enableClipboardSync": @"--no-clipboard-autosync",
    };
    return supportedOptions[key] ?: nil;
}

- (NSArray *)buildScrcpyArgs:(NSString *)serial {
    // Default arguments init
    NSMutableDictionary *args = [NSMutableDictionary dictionaryWithDictionary:@{
#ifdef DEBUG
        @"--verbosity": @"debug",
#endif
        @"--fullscreen": @(YES),
        @"--video-codec": @"h264",
        @"--video-buffer": @"0",
        @"--audio-buffer": @"150",
        @"--print-fps": @(YES),
        @"--video-bit-rate": @"4M",
        @"--serial": serial,
        @"--audio-output-buffer": @"10",
        @"--shortcut-mod": @"lctrl,rctrl,lalt,ralt",
    }];
    
    // Check if new display is enabled and add --new-display argument
    if (self.sessionArguments[@"adbOptions"][@"startNewDisplay"] && 
        [self.sessionArguments[@"adbOptions"][@"startNewDisplay"] boolValue]) {
        
        // Build new display string based on user configuration
        NSString *displayWidth = self.sessionArguments[@"adbOptions"][@"displayWidth"];
        NSString *displayHeight = self.sessionArguments[@"adbOptions"][@"displayHeight"];
        NSString *displayDPI = self.sessionArguments[@"adbOptions"][@"displayDPI"];
        
        NSMutableString *newDisplayValue = [NSMutableString string];
        
        // Add width and height if provided
        if (displayWidth && displayWidth.length > 0 && displayHeight && displayHeight.length > 0) {
            [newDisplayValue appendFormat:@"%@x%@", displayWidth, displayHeight];
        }
        
        // Add DPI if provided  
        if (displayDPI && displayDPI.length > 0) {
            if (newDisplayValue.length > 0) {
                [newDisplayValue appendFormat:@"/%@", displayDPI];
            } else {
                [newDisplayValue appendFormat:@"/%@", displayDPI];
            }
        }
        
        // Use the new display value or default if empty
        if (newDisplayValue.length > 0) {
            [args setObject:newDisplayValue forKey:@"--new-display"];
        } else {
            [args setObject:@(YES) forKey:@"--new-display"];
        }
    }
    
    // Merge with session arguments
    for (NSString *key in self.sessionArguments[@"adbOptions"]) {
        if ([@[@"id", @"startNewDisplay", @"volumeScale"] containsObject:key]) {
            continue;
        }
        
        // Skip display parameters as they are handled by --new-display
        if ([@[@"displayWidth", @"displayHeight", @"displayDPI"] containsObject:key]) {
            continue;
        }
        
        // Check reverse option which should be removed
        NSString *reverseKey = [self reverseOptionArgumentKeyMapping:key];
        if (reverseKey) {
            id reverseValue = self.sessionArguments[@"adbOptions"][key];
            if ([reverseValue isKindOfClass:[NSNumber class]] && [reverseValue boolValue] == NO) {
                [args setObject:@(YES) forKey:reverseKey];
            }
            continue;
        }
        
        NSString *argKey = [self optionArgumentKeyMapping:key];
        if (!argKey) {
            NSLog(@"⚠️ Unsupported option key: %@", key);
            continue;
        }
        
        id argValue = self.sessionArguments[@"adbOptions"][key];
        
        // Handle boolean values
        if ([argValue isKindOfClass:[NSNumber class]] && [argValue isKindOfClass:@YES.class]) {
            if ([argValue boolValue] == NO) {
                args[argKey] = @(YES);
            }
            continue;
        }
        
        // Handle string values
        if ([argValue isKindOfClass:[NSString class]] && [(NSString *)argValue length] > 0) {
            args[argKey] = argValue;
            continue;
        }
        
        // Not supported options
        NSLog(@"⚠️ Unsupported option value: %@, %@", key, argValue);
    }
    
    NSMutableArray *argv = [NSMutableArray arrayWithArray:@[@"scrcpy"]];
    for (NSString *key in args) {
        id value = args[key];
        if ([value isKindOfClass:NSNumber.class] && [value boolValue]) {
            [argv addObject:key];
        } else {
            [argv addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
        }
    }
    
    return [argv copy];
}

- (void)startScrcpy:(NSString *)serial {
    // Init SDL Delegate
    [self.sdlDelegate application:[UIApplication sharedApplication] didFinishLaunchingWithOptions:nil];

    // Run a runloop time slice to response UI events
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, NO);
    
    SDL_iPhoneSetEventPump(SDL_TRUE);
    
    // Flush all events include the not proccessed SERVER_DISCONNECT events
    SDL_FlushEvents(0, 0xFFFF);
    
    // Update audio volume scale if audio is enabled
    ScrpyAudioVolumeScale(1.0);
    if (self.sessionArguments && self.sessionArguments[@"adbOptions"]) {
        id enableAudio = self.sessionArguments[@"adbOptions"][@"enableAudio"];
        id volumeScale = self.sessionArguments[@"adbOptions"][@"volumeScale"];
        if ([enableAudio isKindOfClass:[NSNumber class]] && [enableAudio boolValue] && 
            [volumeScale isKindOfClass:[NSNumber class]]) {
            double scale = [volumeScale doubleValue];
            ScrpyAudioVolumeScale(scale);
        }
    }
    
    // Setup arguments
    NSArray *startArgs = [self buildScrcpyArgs:serial];
    NSLog(@"Starting scrcpy with arguments: %@", startArgs);
    
    char *args[(int)startArgs.count];
    for (int i = 0; i < startArgs.count; i++) {
        args[i] = (char *)[startArgs[i] UTF8String];
    }
    
    scrcpy_main((int)startArgs.count, (char **)args);
    SDL_iPhoneSetEventPump(SDL_FALSE);
}

-(void)stopScrcpy {
    // Call SQL_Quit to send Quit Event
    SDL_Event event;
    event.type = SDL_QUIT;
    SDL_PushEvent(&event);
}

#pragma mark - Scrcpy Events

-(void)syncClipboard {
    NSLog(@"-> Syncing clipboard");
    SDL_Event clip_event;
    clip_event.type = SDL_CLIPBOARDUPDATE;

    BOOL posted = (SDL_PushEvent(&clip_event) > 0);
    NSLog(@"Clipboard event: Post %@", posted? @"Success" : @"Failed");
}

-(void)sendKeycodeEvent:(SDL_Scancode)scancode keycode:(SDL_Keycode)keycode keymod:(SDL_Keymod)keymod {
    ScrcpySendKeycodeEvent(scancode, keycode, keymod);
    NSLog(@"KEY EVENT: Post Success");
}

-(void)syncClipboardWithConnectedDevice {
    if (self.scrcpyStatus != ScrcpyStatusSDLWindowCreated) {
        return;
    }
    
    // Check if clipboard sync is enabled
    BOOL enableClipboardSync = YES;
    if (self.sessionArguments && self.sessionArguments[@"adbOptions"]) {
        id value = self.sessionArguments[@"adbOptions"][@"enableClipboardSync"];
        if ([value isKindOfClass:[NSNumber class]]) {
            enableClipboardSync = [value boolValue];
        }
    }
    
    if (enableClipboardSync) {
        [self syncClipboard];
    } else {
        NSLog(@"-> Clipboard sync is disabled");
    }
}

#pragma mark - Getters

- (SDLUIKitDelegate *)sdlDelegate {
    if (!_sdlDelegate) {
        _sdlDelegate = [[SDLUIKitDelegate alloc] init];
    }
    return _sdlDelegate;
}

#pragma mark - Notification

- (void)onScrcpyStatusUpdated:(NSNotification *)notification {
    NSLog(@"Scrcpy status updated: %@", notification.userInfo);
    enum ScrcpyStatus status = [notification.userInfo[@"status"] intValue];
    
    // Update scrcpy status
    self.scrcpyStatus = status;
    
    // Callback
    if (self.sessionCompletion) self.sessionCompletion(status, notification.userInfo[@"message"]);
    
    // Sync clipboard after connected
    [self syncClipboardWithConnectedDevice];
    
    // Make SDL Window visible after window created
    if (status != ScrcpyStatusSDLWindowCreated) {
        return;
    }
    
    // Set SDL Window to current scene on main thread
    NSLog(@"SDL Window: %@", self.sdlDelegate.window);
    self.sdlDelegate.window.windowScene = self.currentScene;
    NSLog(@"SDL Window Scene: %@", self.sdlDelegate.window.windowScene);
    [self.sdlDelegate.window makeKeyWindow];
}

- (void)onApplicationDidEnterBackground:(NSNotification *)notification {
    NSTimeInterval beginBackgroundTime = [NSDate date].timeIntervalSince1970;

    // For more time execute in background
    static void (^beginTaskHandler)(void) = nil;
    beginTaskHandler = ^{
        __block UIBackgroundTaskIdentifier taskIdentifier = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"com.mobile.scrcpy-ios.task" expirationHandler:^{
            [UIApplication.sharedApplication endBackgroundTask:taskIdentifier];
            NSLog(@"Background task expired: %lu", (unsigned long)taskIdentifier);
            
            if (NSDate.date.timeIntervalSince1970 - beginBackgroundTime < 60 * 2) {
                beginTaskHandler();
            }
        }];
        NSLog(@"Application did enter background with task identifier: %lu", (unsigned long)taskIdentifier);
    };
    beginTaskHandler();
}

- (void)onApplicationDidBecomeActive:(NSNotification *)notification {
    NSLog(@"Application did become active, reset video");
    
    if (self.scrcpyStatus != ScrcpyStatusSDLWindowCreated) {
        return;
    }
    
    // Sync clipboard
    [self syncClipboardWithConnectedDevice];
    
    // Trigger reset video when app become active
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self sendKeycodeEvent:SDL_SCANCODE_R keycode:SDLK_r keymod:KMOD_LCTRL | KMOD_SHIFT];
        NSLog(@"-> [2] Reset video by LCTRL+SHIFT+R");
    });
}

@end

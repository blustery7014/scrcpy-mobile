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


@interface ScrcpyADBClient ()

@property (nonatomic, strong)  SDLUIKitDelegate  *sdlDelegate;
@property (nonatomic, copy) void (^sessionCompletion)(enum ScrcpyStatus, NSString *);
@property (nonatomic, copy) NSDictionary  *sessionArguments;

@end

@implementation ScrcpyADBClient

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onScrcpyStatusUpdated:) name:@"ScrcpyStatusUpdated" object:nil];
    }
    return self;
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
    
    [self setupScrcpyEnvs];
    
    NSString *host = arguments[@"hostReal"];
    NSString *port = arguments[@"port"];
    NSString *serial = [NSString stringWithFormat:@"%@:%@", host, port];

    // Update session completion and arguments
    self.sessionCompletion = completion;
    self.sessionArguments = arguments;
    
    // Connect ADB device async to prevent blocking main thread
    __weak typeof(self) weakSelf = self;
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
        @"bitRate": @"--bit-rate",
        @"maxFPS": @"--max-fps",
        @"videoEncoder": @"--video-codec",
        @"videoBuffer": @"--video-buffer",
    };
    return supportedOptions[key] ?: nil;
}

- (NSString *)reverseOptionArgumentKeyMapping:(NSString *)key {
    NSDictionary *supportedOptions = @{
        @"enableAudio": @"--no-audio",
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
        @"--video-codec": @"h265",
        @"--video-buffer": @"16",
        @"--print-fps": @(YES),
        @"--video-bit-rate": @"4M",
        @"--serial": serial,
    }];
    
    // Merge with session arguments
    for (NSString *key in self.sessionArguments[@"adbOptions"]) {
        if ([@[@"id"] containsObject:key]) {
            continue;
        }
        
        NSString *argKey = [self optionArgumentKeyMapping:key];
        NSString *argValue = self.sessionArguments[@"adbOptions"][key];
        if (argKey && argValue != nil && argValue.length > 0) {
            args[argKey] = self.sessionArguments[@"adbOptions"][key];
            continue;
        }
        
        // Reverse flags
        NSString *reverseArgKey = [self reverseOptionArgumentKeyMapping:key];
        if (reverseArgKey && [self.sessionArguments[@"adbOptions"][key] boolValue] == NO) {
            args[reverseArgKey] = @(YES);
            continue;
        }
        
        // Not supported options
        NSLog(@"❌ Unsupported option: %@, %@", key, argValue);
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
    
    // Callback
    if (self.sessionCompletion) self.sessionCompletion(status, notification.userInfo[@"message"]);
    
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

@end

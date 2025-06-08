//
//  ScrcpySDLWrapper.m
//  Scrcpy Remote
//
//  Created by Ethan on 12/15/24.
//

#import "ScrcpyClientWrapper.h"
#import "ScrcpyBlockWrapper.h"

#import <objc/runtime.h>
#import <SDL2/SDL.h>

#import "ScrcpyVNCClient.h"
#import "ScrcpyADBClient.h"
#import "ScrcpyCommon.h"

@interface ScrcpyClientWrapper ()

// VNC Client
@property (nonatomic, strong) ScrcpyVNCClient *vncClient;
// ADB Client
@property (nonatomic, strong) ScrcpyADBClient *adbClient;

// Track current active client
@property (nonatomic, weak) id<ScrcpyClientProtocol> currentActiveClient;

@end

@implementation ScrcpyClientWrapper

- (instancetype)init
{
    self = [super init];
    if (self) {
    }
    return self;
}

- (UIWindow *)keyWindowForScene:(UIScene *)scene {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    return nil;
}

- (ScrcpyADBClient *)adbClient {
    if (!_adbClient) {
        _adbClient = [[ScrcpyADBClient alloc] init];
    }
    return _adbClient;
}

- (ScrcpyVNCClient *)vncClient {
    if (!_vncClient) {
        _vncClient = [[ScrcpyVNCClient alloc] init];
    }
    return _vncClient;
}

- (void)startClient:(NSDictionary *)arguments completion:(nonnull void (^)(enum ScrcpyStatus, NSString * _Nonnull))completion {
    NSLog(@"SDL_main start");
    NSDictionary *deviceClients = @{
        @"adb": self.adbClient,
        @"vnc": self.vncClient
    };
    
    NSString *deviceType = arguments[@"deviceType"];
    if (!deviceType || ![deviceClients.allKeys containsObject:deviceType]) {
        NSLog(@"Unsupported device type: %@", deviceType);
        if (completion) {
            completion(ScrcpyStatusConnectingFailed, @"Unsupported device type");
        }
        return;
    }
    
    id<ScrcpyClientProtocol> deviceClient = deviceClients[deviceType];
    
    // Track current active client
    self.currentActiveClient = deviceClient;
    
    if ([deviceClient respondsToSelector:@selector(startWithArguments:completion:)]) {
        [deviceClient startWithArguments:arguments completion:completion];
    }
}

- (void)disconnectCurrentClient {
    NSLog(@"🔌 [ScrcpyClientWrapper] Disconnecting current client");
    
    if (self.currentActiveClient && [self.currentActiveClient respondsToSelector:@selector(disconnect)]) {
        [self.currentActiveClient disconnect];
        self.currentActiveClient = nil;
        NSLog(@"✅ [ScrcpyClientWrapper] Current client disconnected");
    } else {
        NSLog(@"ℹ️ [ScrcpyClientWrapper] No active client to disconnect");
    }
}

@end

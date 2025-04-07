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
#import <rfb/rfbclient.h>

#import "ScrcpyVNCClient.h"
#import "ScrcpyADBClient.h"

@interface ScrcpyClientWrapper ()

// VNC Client
@property (nonatomic, strong) ScrcpyVNCClient *vncClient;
// ADB Client
@property (nonatomic, strong) ScrcpyADBClient *adbClient;

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
    
    if ([arguments[@"deviceType"] isEqualToString:@"vnc"]) {
        [self.vncClient start:arguments[@"hostReal"]
                         port:arguments[@"port"]
                         user:arguments[@"vncOptions"][@"vncUser"]
                     password:arguments[@"vncOptions"][@"vncPassword"]];
    } else {
        [self.adbClient startClient:arguments completion:completion];
    }
}

- (void)testKill {
    [self.adbClient testKill];
}

@end

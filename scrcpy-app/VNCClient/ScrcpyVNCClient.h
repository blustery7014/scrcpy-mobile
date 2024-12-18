//
//  SDLVNCClient.h
//  VNCClient
//
//  Created by Ethan on 12/16/24.
//

#import <Foundation/Foundation.h>
#import "ScrcpyClientWrapper.h"

NS_ASSUME_NONNULL_BEGIN

// Make protocol to match: @implementation SDLUIKitDelegate
@interface SDLUIKitDelegate: NSObject<UIApplicationDelegate>
+ (id)sharedAppDelegate;
+ (NSString *)getAppDelegateClassName;
- (void)hideLaunchScreen;

- (UIWindow *)window;
- (void)applicationWillTerminate:(UIApplication *)application;
- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;
- (void)applicationWillResignActive:(UIApplication*)application;
- (void)applicationDidEnterBackground:(UIApplication*)application;
- (void)applicationWillEnterForeground:(UIApplication*)application;
- (void)applicationDidBecomeActive:(UIApplication*)application;
@end

@interface ScrcpyVNCClient : NSObject

@property (nonatomic, strong) SDLUIKitDelegate *sdlDelegate;

-(void)start:(NSString *)host port:(NSString *)port user:(NSString *)user password:(NSString *)password;

@end

NS_ASSUME_NONNULL_END

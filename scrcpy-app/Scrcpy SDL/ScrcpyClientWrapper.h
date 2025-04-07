//
//  ScrcpySDLWrapper.h
//  Scrcpy Remote
//
//  Created by Ethan on 12/15/24.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "scrcpy-porting.h"

NS_ASSUME_NONNULL_BEGIN

static inline UIWindowScene * GetCurrentWindowScene(void)
{
    for (UIWindowScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            return scene;
        }
    }
    return nil;
}

// Make interface to match: @implementation SDLUIKitDelegate
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


@interface ScrcpyClientWrapper : NSObject

- (void)startClient:(NSDictionary *)arguments completion:(void (^)(enum ScrcpyStatus statusCode, NSString *message))completion;

- (void)testKill;

@end

NS_ASSUME_NONNULL_END

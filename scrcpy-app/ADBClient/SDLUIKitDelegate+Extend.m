//
//  SDLUIKitDelegate+Extend.m
//  Scrcpy Remote
//
//  Created by Ethan on 5/10/25.
//

#import "SDLUIKitDelegate+Extend.h"

@implementation SDLUIKitDelegate (Extend)

-(void)applicationDidEnterBackground:(UIApplication *)application
{
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

@end

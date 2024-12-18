//
//  ScrcpyADBClient.m
//  Scrcpy Remote
//
//  Created by Ethan on 12/16/24.
//

#import "ScrcpyADBClient.h"
#import "ADBClient.h"
#import <UIKit/UIKit.h>

@interface ScrcpyADBClient ()
@end

@implementation ScrcpyADBClient

- (UIWindowScene *)currentScene {
    for (UIWindowScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            return scene;
        }
    }
    return nil;
}

- (void)startClient:(NSDictionary *)arguments {
    NSLog(@"🟢 Starting connect ADB device..");
    
    NSString *host = arguments[@"hostReal"];
    NSString *port = arguments[@"port"];
    NSLog(@"ADB: %@", [ADBClient.shared executeADBCommand:@[
        @"connect", [NSString stringWithFormat:@"%@:%@", host, port]
    ] returnCode:nil]);
    NSLog(@"ADB Devices: %@", [ADBClient.shared adbDevices]);
    
    NSLog(@"ADB Shell: %@", [ADBClient.shared executeADBCommand:@[
        @"shell", @"ip", @"route"
    ] returnCode:nil]);
}

@end

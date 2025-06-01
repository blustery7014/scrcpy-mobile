//
//  SDLVNCClient.h
//  VNCClient
//
//  Created by Ethan on 12/16/24.
//

#import <Foundation/Foundation.h>
#import "ScrcpyClientWrapper.h"

NS_ASSUME_NONNULL_BEGIN

// Notification name for disconnect scrcpy request
#define ScrcpyRequestDisconnectNotification @"ScrcpyRequestDisconnectNotification"

@interface ScrcpyVNCClient : NSObject

@property (nonatomic, strong) SDLUIKitDelegate *sdlDelegate;

-(void)start:(NSString *)host port:(NSString *)port user:(NSString *)user password:(NSString *)password;
-(void)stopVNC;

@end

NS_ASSUME_NONNULL_END

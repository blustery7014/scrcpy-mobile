//
//  ScrcpyCommon.m
//  Scrcpy Remote
//
//  Created by Ethan on 6/2/25.
//

#import "ScrcpyCommon.h"
#import <Foundation/Foundation.h>

void ScrcpyUpdateStatus(enum ScrcpyStatus status, const char *message) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:@(status) forKey:@"status"];
    
    // 如果有消息，添加到 userInfo 中
    if (message != NULL) {
        NSString *messageString = [NSString stringWithUTF8String:message];
        if (messageString) {
            userInfo[@"message"] = messageString;
        }
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ScrcpyStatusUpdatedNotificationName 
                                                        object:nil 
                                                      userInfo:userInfo];
}


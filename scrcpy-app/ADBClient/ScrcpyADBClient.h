//
//  ScrcpyADBClient.h
//  Scrcpy Remote
//
//  Created by Ethan on 12/16/24.
//

#import <Foundation/Foundation.h>
#import "scrcpy-porting.h"

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyADBClient : NSObject

- (void)startClient:(NSDictionary *)arguments completion:(void (^)(enum ScrcpyStatus statusCode, NSString *message))completion;

@end

NS_ASSUME_NONNULL_END

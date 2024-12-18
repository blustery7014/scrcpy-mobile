//
//  ScrcpySDLWrapper.h
//  Scrcpy Remote
//
//  Created by Ethan on 12/15/24.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyClientWrapper : NSObject

- (void)startClient:(NSDictionary *)arguments;

@end

NS_ASSUME_NONNULL_END

//
//  ScrcpyVNCClient.h
//  VNCClient
//
//  Created by Ethan on 6/28/25.
//

#import <Foundation/Foundation.h>
#import "ScrcpyClientWrapper.h"
#import "ScrcpyCommon.h"

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyVNCClient : NSObject <ScrcpyClientProtocol>

/// 启动VNC连接并显示
/// @param arguments 连接参数，包含主机、端口、用户名、密码等信息
/// @param completion 连接完成回调
- (void)startWithArguments:(NSDictionary *)arguments completion:(void (^)(enum ScrcpyStatus, NSString *))completion;

/// 停止VNC连接
- (void)stopVNC;

@end

NS_ASSUME_NONNULL_END

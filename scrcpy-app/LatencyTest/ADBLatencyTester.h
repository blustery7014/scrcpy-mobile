//
//  ADBLatencyTester.h
//  Scrcpy Remote
//
//  Created by Claude on 12/27/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ADB Protocol Constants
#define ADB_VERSION 0x01000000  // Protocol version
#define ADB_MAX_PAYLOAD (256 * 1024) // 256KB

// ADB Commands
#define ADB_CMD_CNXN @"CNXN"
#define ADB_CMD_AUTH @"AUTH"
#define ADB_CMD_OPEN @"OPEN"

// Authentication types
typedef NS_ENUM(NSInteger, ADBAuthType) {
    ADBAuthToken = 1,
    ADBAuthSignature = 2,
    ADBAuthRSAPublicKey = 3
};

// Latency test result callback
typedef void (^ADBLatencyCallback)(NSNumber * _Nullable latencyMs, NSError * _Nullable error);

@interface ADBLatencyTester : NSObject

// Initialize with session dictionary
- (instancetype)initWithSession:(NSDictionary *)session;

// Test latency method using direct ADB protocol connection
- (void)testLatency:(ADBLatencyCallback)completion;

// Test average latency over multiple iterations
- (void)testAverageLatencyWithCount:(NSInteger)count completion:(ADBLatencyCallback)completion;

// Direct socket-based ADB handshake to test latency
- (void)testDirectADBHandshake:(ADBLatencyCallback)completion;

@end

NS_ASSUME_NONNULL_END 
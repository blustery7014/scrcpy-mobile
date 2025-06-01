//
//  TCPLatencyTester.h
//  Scrcpy Remote
//
//  Created by Claude on 12/27/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Callback block for TCP latency test results
 * @param latencyMs The measured latency in milliseconds, or nil if failed
 * @param error Error object if the test failed, or nil if successful
 */
typedef void (^TCPLatencyCallback)(NSNumber * _Nullable latencyMs, NSError * _Nullable error);

/**
 * TCPLatencyTester - Tests network latency by establishing TCP connection and measuring round-trip time
 * 
 * This class provides functionality to test network latency to any TCP endpoint by:
 * 1. Establishing a TCP connection to the target host:port
 * 2. Sending a small data packet
 * 3. Receiving the first response packet
 * 4. Measuring the total round-trip time
 */
@interface TCPLatencyTester : NSObject

#pragma mark - Initialization

/**
 * Initialize with target host and port
 * @param host The target hostname or IP address
 * @param port The target port number
 * @return Initialized TCPLatencyTester instance
 */
- (instancetype)initWithHost:(NSString *)host port:(NSString *)port;

/**
 * Initialize with target host and port (convenience method)
 * @param host The target hostname or IP address
 * @param port The target port number as integer
 * @return Initialized TCPLatencyTester instance
 */
- (instancetype)initWithHost:(NSString *)host portNumber:(NSInteger)port;

#pragma mark - Latency Testing

/**
 * Test TCP latency to the target endpoint
 * @param completion Callback block called with results
 */
- (void)testLatency:(TCPLatencyCallback)completion;

/**
 * Test TCP latency multiple times and return average
 * @param count Number of tests to perform
 * @param completion Callback block called with average results
 */
- (void)testAverageLatencyWithCount:(NSInteger)count completion:(TCPLatencyCallback)completion;

/**
 * Test TCP latency with custom data payload
 * @param data Custom data to send (if nil, sends default "PING" message)
 * @param completion Callback block called with results
 */
- (void)testLatencyWithCustomData:(NSData * _Nullable)data completion:(TCPLatencyCallback)completion;

#pragma mark - Properties

/**
 * Target hostname or IP address
 */
@property (nonatomic, readonly, copy) NSString *host;

/**
 * Target port number
 */
@property (nonatomic, readonly, copy) NSString *port;

/**
 * Connection timeout in seconds (default: 10)
 */
@property (nonatomic, assign) NSTimeInterval connectionTimeout;

/**
 * Read timeout in seconds (default: 5)
 */
@property (nonatomic, assign) NSTimeInterval readTimeout;

@end

NS_ASSUME_NONNULL_END 
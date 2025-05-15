//
//  ADBClient_cli.h
//  ADB Latency Tester CLI
//
//  Created by Claude on 12/27/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Status Enum
typedef NS_ENUM(NSInteger, ADBDeviceStatus) {
    ADBDeviceStatusOffline = 0,
    ADBDeviceStatusUnauthorized,
    ADBDeviceStatusDevice,
    ADBDeviceStatusRecovery,
    ADBDeviceStatusBootloader,
    ADBDeviceStatusUnknown
};

// Execute ADB Command Callback
typedef void (^ADBClientCallback)(NSString * _Nullable output, int returnCode);

@interface ADBDevice : NSObject

@property (nonatomic, copy) NSString *serial;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, assign) ADBDeviceStatus status;

@end

@interface ADBClient : NSObject

@property (nonatomic, assign, readonly) int listenPort;
@property (nonatomic, assign, readonly) BOOL isADBLaunched;
@property (nonatomic, strong, readonly) NSArray <NSString *>* adbDevices;

+ (instancetype)shared;

// Execute ADB Command sync
- (NSString *)executeADBCommand:(NSArray <NSString *>*)commands returnCode:(int * _Nullable)returnCode;

// Execute ADB Command Async
- (void)executeADBCommandAsync:(NSArray<NSString *> *)commands callback:(ADBClientCallback)callback;

@end

#pragma mark - Mock Implementation for CLI

// This is a mock implementation used only for standalone CLI builds
#ifdef LATENCY_TESTER_CLI

@implementation ADBDevice
@synthesize serial, statusText, status;
@end

@implementation ADBClient

+ (instancetype)shared {
    static ADBClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ADBClient alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isADBLaunched = NO; // CLI version doesn't launch ADB
    }
    return self;
}

- (NSString *)executeADBCommand:(NSArray<NSString *> *)commands returnCode:(int * _Nullable)returnCode {
    // Mock implementation - CLI version doesn't use ADB command methods
    if (returnCode) *returnCode = -1;
    return @"ADB Client not available in CLI mode";
}

- (void)executeADBCommandAsync:(NSArray<NSString *> *)commands callback:(ADBClientCallback)callback {
    // Mock implementation - CLI version doesn't use ADB command methods
    if (callback) callback(@"ADB Client not available in CLI mode", -1);
}

@end

#endif // LATENCY_TESTER_CLI

NS_ASSUME_NONNULL_END 
//
//  ADBClient.h
//  Scrcpy Remote
//
//  Created by Ethan on 12/16/24.
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

@property (nonatomic, assign, readonly)   int  listenPort;
@property (nonatomic, assign, readonly)   BOOL isADBLaunched;
@property (nonatomic, strong, readonly)   NSArray <NSString *>* adbDevices;

+ (instancetype)shared;

// Execute ADB Command sync
- (NSString *)executeADBCommand:(NSArray <NSString *>*)commands returnCode:(int * __nullable)returnCode;

// Execute ADB Command Async
- (void)executeADBCommandAsync:(NSArray<NSString *> *)commands callback:(ADBClientCallback)callback;

@end

NS_ASSUME_NONNULL_END

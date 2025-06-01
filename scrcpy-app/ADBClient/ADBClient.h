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
    ADBDeviceStatusUnknown = 0,
    ADBDeviceStatusDevice,
    ADBDeviceStatusOffline,
    ADBDeviceStatusUnauthorized,
    ADBDeviceStatusRecovery,
    ADBDeviceStatusBootloader
};

// Execute ADB Command Callback
typedef void (^ADBClientCallback)(NSString * _Nullable output, int returnCode);

@interface ADBDevice : NSObject

@property (nonatomic, copy) NSString *serial;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, assign) ADBDeviceStatus status;

- (instancetype)initWith:(NSString *)deviceLine;

@end

@interface ADBClient : NSObject

@property (nonatomic, strong, readonly) NSArray <ADBDevice *> *adbDevices;
@property (nonatomic, assign, readonly) BOOL isADBLaunched;
@property (nonatomic, assign, readonly) int listenPort;

+ (instancetype)shared;

// Execute ADB Command sync
- (NSString *)executeADBCommand:(NSArray <NSString *>*)commands returnCode:(int * __nullable)returnCode;

// Execute ADB Command Async
- (void)executeADBCommandAsync:(NSArray<NSString *> *)commands callback:(ADBClientCallback)callback;

// ADB Key Management Methods
- (NSString *)getADBHomeDirectory;
- (NSString *)getADBAndroidDirectory;
- (NSString *)readADBPrivateKey;
- (NSString *)readADBPublicKey;
- (BOOL)writeADBPrivateKey:(NSString *)privateKey;
- (BOOL)writeADBPublicKey:(NSString *)publicKey;
- (BOOL)generateNewADBKeyPair;
- (BOOL)exportADBKeysToDirectory:(NSString *)directoryPath;
- (BOOL)adbKeyPairExists;

@end

NS_ASSUME_NONNULL_END

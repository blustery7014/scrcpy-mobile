//
//  ADBClient.m
//  Scrcpy Remote
//
//  Created by Ethan on 12/16/24.
//

#import "ADBClient.h"
#import "adb_public.h"
#import <sys/socket.h>
#import <netinet/in.h>

#define kADBConnectStatusUpdated    @"ADBConnectStatusUpdated"

void adb_connect_status_updated(const char *serial, const char *status)
{
    NSLog(@"ADB Connect status updated: %s, %s", serial, status);
    // Post Notification
    [[NSNotificationCenter defaultCenter] postNotificationName:kADBConnectStatusUpdated object:nil userInfo:@{
        @"serial": [NSString stringWithUTF8String:serial],
        @"status": [NSString stringWithUTF8String:status]
    }];
}

@implementation ADBDevice

- (instancetype)initWith:(NSString *)deviceLine
{
    self = [super init];
    if (self) {
        // Skip "List of devices attached"
        if ([deviceLine.lowercaseString isEqualToString:@"list of devices attached"]) { return nil; }
        // Device line format: "19071FDA600789    device"
        NSArray <NSString *> *components = [deviceLine componentsSeparatedByString:@"\t"];
        if (components.count != 2) { return nil; }
        self.serial = components[0];
        self.statusText = components[1];
    }
    return self;
}

- (void)setStatusText:(NSString *)statusText
{
    _statusText = statusText;
    _status = [self.class statusFromText:statusText];
}

+ (ADBDeviceStatus)statusFromText:(NSString *)text
{
    if ([text isEqualToString:@"device"]) {
        return ADBDeviceStatusDevice;
    }
    if ([text isEqualToString:@"offline"]) {
        return ADBDeviceStatusOffline;
    }
    if ([text isEqualToString:@"unauthorized"]) {
        return ADBDeviceStatusUnauthorized;
    }
    if ([text isEqualToString:@"recovery"]) {
        return ADBDeviceStatusRecovery;
    }
    if ([text isEqualToString:@"bootloader"]) {
        return ADBDeviceStatusBootloader;
    }
    return ADBDeviceStatusUnknown;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@: %@, %@", [super description], self.serial, self.statusText];
}

@end

@interface ADBClient ()

@property (nonatomic, strong)   NSMutableArray <ADBDevice *> *devicesInternal;

@end

@implementation ADBClient

+ (instancetype)shared
{
    static ADBClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ADBClient alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) { [self setup]; }
    return self;
}

- (void)setup
{
    // Time to profile adb start up
    NSDate *start = [NSDate date];
    
    // Observe Notifaction
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(adbConnectStatusUpdated:)
                                                 name:kADBConnectStatusUpdated
                                               object:nil];
    
    // Enable verbose trace
    // adb_enable_trace();

    // Find an available port in range [15037, 15037 + 32]
    NSLog(@"Find an available port in range [15037, 15037 + 32]");
    for (int i = 0; i < 32; i++) {
        int port = 25037 + i;
        // Try bind on port by sockect func to test if it's available
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_ANY);
        addr.sin_port = htons(port);
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) {
            NSLog(@"Check socket failed on port: %d, errno: %d", port, errno);
            continue;
        }
        if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            NSLog(@"Check bind failed on port: %d, errno: %d", port, errno);
            close(fd);
            continue;
        }
        close(fd);
        adb_set_server_port([NSString stringWithFormat:@"%d", port].UTF8String);
        _listenPort = port;
        NSLog(@"ADB Client port set to port: %d", port);
        break;
    }

    // Setup ADB home directory
    [self setupADBHomeDirectory];

    int returnCode = -1;
    NSString *output = [self executeADBCommandUnderlying:@[@"devices"] returnCode:&returnCode];
    if (returnCode != 0) {
        // Setup adb failed
        NSLog(@"❌ ADB Client setup failed: test `adb devices` command failed!");
        return;
    }
    NSLog(@"ADB Client setup success, output: %@", output);
    
    // Mark as launched
    _isADBLaunched = YES;

    // Time to profile adb start up
    NSDate *end = [NSDate date];
    NSLog(@"ADB Client setup time: %f", [end timeIntervalSinceDate:start]);
}

- (void)setupADBHomeDirectory
{
    NSString *adbHome = [self getADBHomeDirectory];
    adb_set_home(adbHome.UTF8String);
    NSLog(@"ADB home directory set to: %@", adbHome);
}

- (NSString *)executeADBCommandUnderlying:(NSArray <NSString *>*)commands returnCode:(int*)returnCode
{
    char *output = NULL;
    size_t output_size = 0;
    // Convert NSArray to char**
    const char **argv = malloc(sizeof(char *) * commands.count);
    for (int i = 0; i < commands.count; i++) {
        argv[i] = commands[i].UTF8String;
    }
    int ret = adb_commandline_porting(&output, &output_size, (int)commands.count, argv);
    if (returnCode) { *returnCode = ret; }
    NSLog(@"> adb_commandline_porting [%@]\n> return code: %d\n> output text:\n%s",
          [commands componentsJoinedByString:@" "], ret, output);
    
    // Special for connect and disconnect commands, we need to update devices after executed
    if (commands.count > 0 && [@[@"connect", @"disconnect"] containsObject:commands[0]]) {
        [self updateDevices];
    }
    
    return output_size > 0 && output != NULL ? [NSString stringWithUTF8String:output] : @"";
}

- (NSString *)executeADBCommand:(NSArray <NSString *>*)commands returnCode:(int * __nullable)returnCode
{
    if (!_isADBLaunched) {
        NSLog(@"❌ ADB Client not launched yet!");
        if (returnCode) { *returnCode = -1; }
        return nil;
    }
    return [self executeADBCommandUnderlying:commands returnCode:returnCode];
}

- (void)executeADBCommandAsync:(NSArray<NSString *> *)commands callback:(ADBClientCallback)callback
{
    if (!_isADBLaunched) {
        NSLog(@"❌ ADB Client not launched yet!");
        if (callback) { callback(nil, -1); }
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int returnCode = -1;
        NSString *output = [self executeADBCommand:commands returnCode:&returnCode];
        if (callback) { callback(output, returnCode); }
    });
}

#pragma mark - Getter & Setter

- (NSArray<ADBDevice *> *)adbDevices
{
    return [self.devicesInternal copy];
}

- (NSMutableArray<ADBDevice *> *)devicesInternal
{
    if (!_devicesInternal) {
        _devicesInternal = [NSMutableArray array];
    }
    return _devicesInternal;
}

#pragma mark - ADB Key Management

- (NSString *)getADBHomeDirectory
{
    NSArray <NSString *> *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return documentPaths.lastObject;
}

- (NSString *)getADBAndroidDirectory
{
    NSString *adbHome = [self getADBHomeDirectory];
    return [adbHome stringByAppendingPathComponent:@".android"];
}

- (BOOL)ensureADBAndroidDirectoryExists
{
    NSString *androidDir = [self getADBAndroidDirectory];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:androidDir]) {
        NSError *error;
        BOOL success = [fileManager createDirectoryAtPath:androidDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
        if (!success) {
            NSLog(@"Error creating .android directory: %@", error.localizedDescription);
            return NO;
        }
        NSLog(@"Created .android directory at: %@", androidDir);
    }
    return YES;
}

- (NSString *)readADBPrivateKey
{
    NSString *keyPath = [[self getADBAndroidDirectory] stringByAppendingPathComponent:@"adbkey"];
    NSError *error;
    NSString *content = [NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"Error reading ADB private key: %@", error.localizedDescription);
        return nil;
    }
    return content;
}

- (NSString *)readADBPublicKey
{
    NSString *keyPath = [[self getADBAndroidDirectory] stringByAppendingPathComponent:@"adbkey.pub"];
    NSError *error;
    NSString *content = [NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"Error reading ADB public key: %@", error.localizedDescription);
        return nil;
    }
    return content;
}

- (BOOL)writeADBPrivateKey:(NSString *)privateKey
{
    if (!privateKey || privateKey.length == 0) {
        NSLog(@"Error: Private key content is empty");
        return NO;
    }
    
    // Ensure .android directory exists
    if (![self ensureADBAndroidDirectoryExists]) {
        return NO;
    }
    
    NSString *keyPath = [[self getADBAndroidDirectory] stringByAppendingPathComponent:@"adbkey"];
    NSError *error;
    BOOL success = [privateKey writeToFile:keyPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!success) {
        NSLog(@"Error writing ADB private key: %@", error.localizedDescription);
        return NO;
    }
    
    // Set proper file permissions (0600 - read/write for owner only)
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = @{NSFilePosixPermissions: @(0600)};
    [fileManager setAttributes:attributes ofItemAtPath:keyPath error:&error];
    if (error) {
        NSLog(@"Warning: Could not set file permissions for private key: %@", error.localizedDescription);
    }
    
    NSLog(@"ADB private key saved successfully to: %@", keyPath);
    return YES;
}

- (BOOL)writeADBPublicKey:(NSString *)publicKey
{
    if (!publicKey || publicKey.length == 0) {
        NSLog(@"Error: Public key content is empty");
        return NO;
    }
    
    // Ensure .android directory exists
    if (![self ensureADBAndroidDirectoryExists]) {
        return NO;
    }
    
    NSString *keyPath = [[self getADBAndroidDirectory] stringByAppendingPathComponent:@"adbkey.pub"];
    NSError *error;
    BOOL success = [publicKey writeToFile:keyPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!success) {
        NSLog(@"Error writing ADB public key: %@", error.localizedDescription);
        return NO;
    }
    
    // Set proper file permissions (0644 - read/write for owner, read for others)
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = @{NSFilePosixPermissions: @(0644)};
    [fileManager setAttributes:attributes ofItemAtPath:keyPath error:&error];
    if (error) {
        NSLog(@"Warning: Could not set file permissions for public key: %@", error.localizedDescription);
    }
    
    NSLog(@"ADB public key saved successfully to: %@", keyPath);
    return YES;
}

- (BOOL)generateNewADBKeyPair
{
    // Ensure .android directory exists before generating keys
    if (![self ensureADBAndroidDirectoryExists]) {
        return NO;
    }
    
    // Execute ADB keygen command to generate new key pair
    // The keygen command should create keys in the .android subdirectory
    NSString *androidDir = [self getADBAndroidDirectory];
    int returnCode = -1;
    NSString *output = [self executeADBCommandUnderlying:@[@"keygen", androidDir] returnCode:&returnCode];
    
    if (returnCode == 0) {
        NSLog(@"ADB key pair generated successfully: %@", output);
        return YES;
    } else {
        NSLog(@"Failed to generate ADB key pair. Return code: %d, Output: %@", returnCode, output);
        return NO;
    }
}

- (BOOL)exportADBKeysToDirectory:(NSString *)directoryPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    
    // Ensure destination directory exists
    if (![fileManager fileExistsAtPath:directoryPath]) {
        BOOL created = [fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:&error];
        if (!created) {
            NSLog(@"Error creating export directory: %@", error.localizedDescription);
            return NO;
        }
    }
    
    NSString *androidDir = [self getADBAndroidDirectory];
    NSString *privateKeySource = [androidDir stringByAppendingPathComponent:@"adbkey"];
    NSString *publicKeySource = [androidDir stringByAppendingPathComponent:@"adbkey.pub"];
    
    NSString *privateKeyDest = [directoryPath stringByAppendingPathComponent:@"adbkey"];
    NSString *publicKeyDest = [directoryPath stringByAppendingPathComponent:@"adbkey.pub"];
    
    // Export private key
    if ([fileManager fileExistsAtPath:privateKeySource]) {
        BOOL success = [fileManager copyItemAtPath:privateKeySource toPath:privateKeyDest error:&error];
        if (!success) {
            NSLog(@"Error exporting private key: %@", error.localizedDescription);
            return NO;
        }
    } else {
        NSLog(@"Private key file does not exist at: %@", privateKeySource);
        return NO;
    }
    
    // Export public key
    if ([fileManager fileExistsAtPath:publicKeySource]) {
        BOOL success = [fileManager copyItemAtPath:publicKeySource toPath:publicKeyDest error:&error];
        if (!success) {
            NSLog(@"Error exporting public key: %@", error.localizedDescription);
            return NO;
        }
    } else {
        NSLog(@"Public key file does not exist at: %@", publicKeySource);
        return NO;
    }
    
    NSLog(@"ADB keys exported successfully to: %@", directoryPath);
    return YES;
}

- (BOOL)adbKeyPairExists
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *androidDir = [self getADBAndroidDirectory];
    NSString *privateKeyPath = [androidDir stringByAppendingPathComponent:@"adbkey"];
    NSString *publicKeyPath = [androidDir stringByAppendingPathComponent:@"adbkey.pub"];
    
    return [fileManager fileExistsAtPath:privateKeyPath] && [fileManager fileExistsAtPath:publicKeyPath];
}

#pragma mark - Utils

- (void)updateDevices
{
    int returnCode = -1;
    NSString *output = [self executeADBCommand:@[@"devices"] returnCode:&returnCode];
    if (returnCode != 0) {
        NSLog(@"❌ ADB Client update devices failed: test `adb devices` command failed!");
        return;
    }
    
    // Parse devices
    NSArray <NSString *> *lines = [output componentsSeparatedByString:@"\n"];
    for (int i = 1; i < lines.count; i++) {
        ADBDevice *device = [[ADBDevice alloc] initWith:lines[i]];
        if (device == nil) { continue; }
        
        // Check if device is in our list, just update status
        // To avoid other object reference this object not updated
        ADBDevice *foundDevice = [self findDevice:device.serial];
        if (foundDevice) {
            foundDevice.statusText = device.statusText;
        } else {
            [self.devicesInternal addObject:device];
        }
    }
}

- (ADBDevice *)findDevice:(NSString *)serial
{
    for (ADBDevice *device in self.devicesInternal) {
        if ([device.serial isEqualToString:serial]) {
            return device;
        }
    }
    return nil;
}

#pragma mark - Notification

- (void)adbConnectStatusUpdated:(NSNotification *)notification
{
    NSDictionary *userInfo = notification.userInfo;
    NSString *serial = userInfo[@"serial"];
    NSString *status = userInfo[@"status"];
    NSLog(@"💬 ADB Connect status updated: %@, %@", serial, status);
    
    // Update connected devices
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateDevices]; });
}

@end

//
//  ADBMediaDetector.h
//  Scrcpy Remote
//
//  Created by Ethan on 12/22/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ADBMediaDecoder : NSObject

@property (nonatomic, copy) NSString *mediaType;
@property (nonatomic, copy) NSString *decoderName;

- (instancetype)initWithMediaType:(NSString *)mediaType decoderName:(NSString *)decoderName;

@end

@interface ADBMediaEncoder : NSObject

@property (nonatomic, copy) NSString *mediaType;
@property (nonatomic, copy) NSString *encoderName;

- (instancetype)initWithMediaType:(NSString *)mediaType encoderName:(NSString *)encoderName;

@end

@interface ADBMediaDetector : NSObject

@property (nonatomic, strong, readonly) NSArray <ADBMediaDecoder *> *mediaDecoders;
@property (nonatomic, strong, readonly) NSArray <ADBMediaEncoder *> *mediaEncoders;

- (void)detectMediaCodecsForHost:(NSString *)host port:(int)port completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

/// Manually remove duplicate codecs from the detected arrays (useful for refreshing data)
- (void)removeDuplicateCodecs;

@end

NS_ASSUME_NONNULL_END
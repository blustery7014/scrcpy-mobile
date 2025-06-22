//
//  ADBMediaDetector.m
//  Scrcpy Remote
//
//  Created by Ethan on 12/22/24.
//

#import "ADBMediaDetector.h"
#import "ADBClient.h"

@implementation ADBMediaDecoder

- (instancetype)initWithMediaType:(NSString *)mediaType decoderName:(NSString *)decoderName {
    self = [super init];
    if (self) {
        _mediaType = [mediaType copy];
        _decoderName = [decoderName copy];
    }
    return self;
}

@end

@implementation ADBMediaEncoder

- (instancetype)initWithMediaType:(NSString *)mediaType encoderName:(NSString *)encoderName {
    self = [super init];
    if (self) {
        _mediaType = [mediaType copy];
        _encoderName = [encoderName copy];
    }
    return self;
}

@end

@implementation ADBMediaDetector {
    NSMutableArray <ADBMediaDecoder *> *_mediaDecoders;
    NSMutableArray <ADBMediaEncoder *> *_mediaEncoders;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mediaDecoders = [NSMutableArray array];
        _mediaEncoders = [NSMutableArray array];
    }
    return self;
}

- (NSArray<ADBMediaDecoder *> *)mediaDecoders {
    return [_mediaDecoders copy];
}

- (NSArray<ADBMediaEncoder *> *)mediaEncoders {
    return [_mediaEncoders copy];
}

- (void)detectMediaCodecsForHost:(NSString *)host port:(int)port completion:(void(^)(BOOL success, NSError * _Nullable error))completion {
    ADBClient *adbClient = [ADBClient shared];
    NSString *hostPort = [NSString stringWithFormat:@"%@:%d", host, port];
    
    // First, try to connect to the device
    NSArray *connectCommands = @[@"connect", hostPort];
    
    [adbClient executeADBCommandAsync:connectCommands callback:^(NSString * _Nullable connectOutput, int connectReturnCode) {
        // Note: adb connect can return 0 even if already connected, so we don't strictly check the return code
        // We'll proceed to the dumpsys command regardless, as it will give us the definitive connection status
        
        NSArray *dumpsysCommands = @[@"-s", hostPort, @"shell", @"dumpsys", @"media.player"];
        
        [adbClient executeADBCommandAsync:dumpsysCommands callback:^(NSString * _Nullable output, int returnCode) {
            if (returnCode != 0) {
                NSString *userFriendlyMessage = @"Unable to connect to device";
                
                // Parse common error scenarios and provide user-friendly messages
                if (output) {
                    NSString *lowercaseOutput = [output lowercaseString];
                    if ([lowercaseOutput containsString:@"not found"] || [lowercaseOutput containsString:@"device offline"]) {
                        userFriendlyMessage = @"Device not found. Please check the host and port, and ensure the device is connected.";
                    } else if ([lowercaseOutput containsString:@"unauthorized"]) {
                        userFriendlyMessage = @"Device authorization required. Please allow USB debugging on the device.";
                    } else if ([lowercaseOutput containsString:@"no devices"]) {
                        userFriendlyMessage = @"No devices connected. Please check your connection.";
                    } else if ([lowercaseOutput containsString:@"connection refused"]) {
                        userFriendlyMessage = @"Connection refused. Please verify the host and port are correct.";
                    }
                }
                
                NSError *error = [NSError errorWithDomain:@"ADBMediaDetectorError" 
                                                   code:returnCode 
                                               userInfo:@{
                                                   NSLocalizedDescriptionKey: userFriendlyMessage,
                                                   @"ADBOutput": output ?: @"No output"
                                               }];
                completion(NO, error);
                return;
            }
            
            if (!output || output.length == 0) {
                NSError *error = [NSError errorWithDomain:@"ADBMediaDetectorError" 
                                                   code:-1 
                                               userInfo:@{NSLocalizedDescriptionKey: @"No response from device. Please check your connection and try again."}];
                completion(NO, error);
                return;
            }
            
            [self parseMediaCodecsFromOutput:output];
            completion(YES, nil);
        }];
    }];
}

- (void)parseMediaCodecsFromOutput:(NSString *)output {
    NSLog(@"[ADBMediaDetector] Starting parse, clearing existing data. Previous counts - Decoders: %lu, Encoders: %lu", 
          (unsigned long)_mediaDecoders.count, (unsigned long)_mediaEncoders.count);
    
    [_mediaDecoders removeAllObjects];
    [_mediaEncoders removeAllObjects];
    
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    
    typedef NS_ENUM(NSInteger, ParseState) {
        ParseStateNone,
        ParseStateDecoders,
        ParseStateEncoders
    };
    
    ParseState currentState = ParseStateNone;
    ADBMediaDecoder *currentDecoder = nil;
    ADBMediaEncoder *currentEncoder = nil;
    
    for (NSString *line in lines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // Check for decoder section start
        NSRegularExpression *decoderSectionRegex = [NSRegularExpression regularExpressionWithPattern:@"Decoder.*media types" 
                                                                                              options:NSRegularExpressionCaseInsensitive 
                                                                                                error:nil];
        if ([decoderSectionRegex numberOfMatchesInString:trimmedLine options:0 range:NSMakeRange(0, trimmedLine.length)] > 0) {
            currentState = ParseStateDecoders;
            continue;
        }
        
        // Check for encoder section start
        NSRegularExpression *encoderSectionRegex = [NSRegularExpression regularExpressionWithPattern:@"Encoder.*media types" 
                                                                                              options:NSRegularExpressionCaseInsensitive 
                                                                                                error:nil];
        if ([encoderSectionRegex numberOfMatchesInString:trimmedLine options:0 range:NSMakeRange(0, trimmedLine.length)] > 0) {
            currentState = ParseStateEncoders;
            continue;
        }
        
        if (currentState == ParseStateDecoders) {
            // Check for media type
            NSRegularExpression *mediaTypeRegex = [NSRegularExpression regularExpressionWithPattern:@"Media type '(.+)'" 
                                                                                             options:0 
                                                                                               error:nil];
            NSTextCheckingResult *mediaTypeMatch = [mediaTypeRegex firstMatchInString:trimmedLine 
                                                                              options:0 
                                                                                range:NSMakeRange(0, trimmedLine.length)];
            if (mediaTypeMatch) {
                NSString *mediaType = [trimmedLine substringWithRange:[mediaTypeMatch rangeAtIndex:1]];
                currentDecoder = [[ADBMediaDecoder alloc] initWithMediaType:mediaType decoderName:@""];
                continue;
            }
            
            // Check for decoder name
            NSRegularExpression *decoderNameRegex = [NSRegularExpression regularExpressionWithPattern:@"Decoder \"(.+)\" supports" 
                                                                                               options:0 
                                                                                                 error:nil];
            NSTextCheckingResult *decoderNameMatch = [decoderNameRegex firstMatchInString:trimmedLine 
                                                                                   options:0 
                                                                                     range:NSMakeRange(0, trimmedLine.length)];
            if (decoderNameMatch && currentDecoder) {
                NSString *decoderName = [trimmedLine substringWithRange:[decoderNameMatch rangeAtIndex:1]];
                currentDecoder.decoderName = decoderName;
                
                // Check for duplicates before adding
                BOOL isDuplicate = NO;
                for (ADBMediaDecoder *existingDecoder in _mediaDecoders) {
                    if ([existingDecoder.decoderName isEqualToString:decoderName] && 
                        [existingDecoder.mediaType isEqualToString:currentDecoder.mediaType]) {
                        isDuplicate = YES;
                        break;
                    }
                }
                
                if (!isDuplicate) {
                    [_mediaDecoders addObject:currentDecoder];
                    NSLog(@"[ADBMediaDetector] Added decoder: %@ (%@)", decoderName, currentDecoder.mediaType);
                } else {
                    NSLog(@"[ADBMediaDetector] Skipped duplicate decoder: %@ (%@)", decoderName, currentDecoder.mediaType);
                }
                currentDecoder = nil;
                continue;
            }
        }
        
        if (currentState == ParseStateEncoders) {
            // Check for media type
            NSRegularExpression *mediaTypeRegex = [NSRegularExpression regularExpressionWithPattern:@"Media type '(.+)'" 
                                                                                             options:0 
                                                                                               error:nil];
            NSTextCheckingResult *mediaTypeMatch = [mediaTypeRegex firstMatchInString:trimmedLine 
                                                                              options:0 
                                                                                range:NSMakeRange(0, trimmedLine.length)];
            if (mediaTypeMatch) {
                NSString *mediaType = [trimmedLine substringWithRange:[mediaTypeMatch rangeAtIndex:1]];
                currentEncoder = [[ADBMediaEncoder alloc] initWithMediaType:mediaType encoderName:@""];
                continue;
            }
            
            // Check for encoder name
            NSRegularExpression *encoderNameRegex = [NSRegularExpression regularExpressionWithPattern:@"Encoder \"(.+)\" supports" 
                                                                                               options:0 
                                                                                                 error:nil];
            NSTextCheckingResult *encoderNameMatch = [encoderNameRegex firstMatchInString:trimmedLine 
                                                                                   options:0 
                                                                                     range:NSMakeRange(0, trimmedLine.length)];
            if (encoderNameMatch && currentEncoder) {
                NSString *encoderName = [trimmedLine substringWithRange:[encoderNameMatch rangeAtIndex:1]];
                currentEncoder.encoderName = encoderName;
                
                // Check for duplicates before adding
                BOOL isDuplicate = NO;
                for (ADBMediaEncoder *existingEncoder in _mediaEncoders) {
                    if ([existingEncoder.encoderName isEqualToString:encoderName] && 
                        [existingEncoder.mediaType isEqualToString:currentEncoder.mediaType]) {
                        isDuplicate = YES;
                        break;
                    }
                }
                
                if (!isDuplicate) {
                    [_mediaEncoders addObject:currentEncoder];
                    NSLog(@"[ADBMediaDetector] Added encoder: %@ (%@)", encoderName, currentEncoder.mediaType);
                } else {
                    NSLog(@"[ADBMediaDetector] Skipped duplicate encoder: %@ (%@)", encoderName, currentEncoder.mediaType);
                }
                currentEncoder = nil;
                continue;
            }
        }
    }
    
    NSLog(@"[ADBMediaDetector] Parse completed. Before final deduplication - Decoders: %lu, Encoders: %lu", 
          (unsigned long)_mediaDecoders.count, (unsigned long)_mediaEncoders.count);
    
    // Final deduplication pass to ensure no duplicates remain
    [self removeDuplicateCodecs];
}

/// Remove duplicate codecs from the arrays to prevent UI duplication issues
- (void)removeDuplicateCodecs {
    // Deduplicate decoders
    NSMutableArray *uniqueDecoders = [NSMutableArray array];
    NSMutableSet *decoderKeys = [NSMutableSet set];
    
    for (ADBMediaDecoder *decoder in _mediaDecoders) {
        NSString *key = [NSString stringWithFormat:@"%@|%@", decoder.decoderName, decoder.mediaType];
        if (![decoderKeys containsObject:key]) {
            [decoderKeys addObject:key];
            [uniqueDecoders addObject:decoder];
        }
    }
    
    [_mediaDecoders removeAllObjects];
    [_mediaDecoders addObjectsFromArray:uniqueDecoders];
    
    // Deduplicate encoders
    NSMutableArray *uniqueEncoders = [NSMutableArray array];
    NSMutableSet *encoderKeys = [NSMutableSet set];
    
    for (ADBMediaEncoder *encoder in _mediaEncoders) {
        NSString *key = [NSString stringWithFormat:@"%@|%@", encoder.encoderName, encoder.mediaType];
        if (![encoderKeys containsObject:key]) {
            [encoderKeys addObject:key];
            [uniqueEncoders addObject:encoder];
        }
    }
    
    [_mediaEncoders removeAllObjects];
    [_mediaEncoders addObjectsFromArray:uniqueEncoders];
    
    NSLog(@"[ADBMediaDetector] After deduplication: %lu decoders, %lu encoders", 
          (unsigned long)_mediaDecoders.count, (unsigned long)_mediaEncoders.count);
}

@end
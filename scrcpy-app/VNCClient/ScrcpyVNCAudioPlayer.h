//
//  ScrcpyVNCAudioPlayer.h
//  VNCClient
//
//  VNC Audio Streaming Player
//  Receives MP3 audio stream over TCP and plays via SDL
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyVNCAudioPlayer : NSObject

/// Whether the audio player is currently playing
@property (nonatomic, readonly) BOOL isPlaying;

/// Whether the audio player is connected to the audio stream
@property (nonatomic, readonly) BOOL isConnected;

/// Current audio host
@property (nonatomic, readonly, nullable) NSString *host;

/// Current audio port
@property (nonatomic, readonly) int port;

/// Initialize the audio player
- (instancetype)init;

/// Start audio streaming from the specified host and port
/// @param host The host to connect to
/// @param port The TCP port for audio streaming
/// @param bufferMs Audio buffer time in milliseconds (default: 100)
/// @param completion Callback with success status and error message
- (void)startWithHost:(NSString *)host
                 port:(int)port
             bufferMs:(int)bufferMs
           completion:(void (^)(BOOL success, NSString * _Nullable error))completion;

/// Stop audio streaming and cleanup resources
- (void)stop;

/// Set the audio volume (0.0 to 1.0)
/// @param volume Volume level
- (void)setVolume:(float)volume;

@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, ScrcpyModifierMask) {
    ScrcpyModifierMaskNone  = 0,
    ScrcpyModifierMaskMeta  = 1 << 0,
    ScrcpyModifierMaskCtrl  = 1 << 1,
    ScrcpyModifierMaskAlt   = 1 << 2,
    ScrcpyModifierMaskShift = 1 << 3,
};

@interface ScrcpyModifierState : NSObject

+ (instancetype)shared;

// Locked states persist until toggled off
@property (atomic, assign) BOOL lockMeta;
@property (atomic, assign) BOOL lockCtrl;
@property (atomic, assign) BOOL lockAlt;
@property (atomic, assign) BOOL lockShift;

// Candidate states are one-shot and clear after first non-modifier key
@property (atomic, assign) BOOL candMeta;
@property (atomic, assign) BOOL candCtrl;
@property (atomic, assign) BOOL candAlt;
@property (atomic, assign) BOOL candShift;

// When toolbar already synthesized modifiers for the next key, set this to avoid double-augmenting in VNC
@property (atomic, assign) BOOL nextKeyAlreadyCombined;

- (ScrcpyModifierMask)lockedMask;
- (ScrcpyModifierMask)candidateMask;
- (ScrcpyModifierMask)activeMask; // lock | candidate

// Returns current candidate mask and clears all candidates atomically
- (ScrcpyModifierMask)consumeCandidateMask;

// Returns and clears the nextKeyAlreadyCombined flag atomically
- (BOOL)consumeNextCombinedFlag;

@end


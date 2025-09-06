#import "ScrcpyModifierState.h"

@implementation ScrcpyModifierState

+ (instancetype)shared {
    static ScrcpyModifierState *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [ScrcpyModifierState new]; });
    return s;
}

- (ScrcpyModifierMask)lockedMask {
    ScrcpyModifierMask m = ScrcpyModifierMaskNone;
    if (self.lockMeta)  m |= ScrcpyModifierMaskMeta;
    if (self.lockCtrl)  m |= ScrcpyModifierMaskCtrl;
    if (self.lockAlt)   m |= ScrcpyModifierMaskAlt;
    if (self.lockShift) m |= ScrcpyModifierMaskShift;
    return m;
}

- (ScrcpyModifierMask)candidateMask {
    ScrcpyModifierMask m = ScrcpyModifierMaskNone;
    if (self.candMeta)  m |= ScrcpyModifierMaskMeta;
    if (self.candCtrl)  m |= ScrcpyModifierMaskCtrl;
    if (self.candAlt)   m |= ScrcpyModifierMaskAlt;
    if (self.candShift) m |= ScrcpyModifierMaskShift;
    return m;
}

- (ScrcpyModifierMask)activeMask {
    return [self lockedMask] | [self candidateMask];
}

- (ScrcpyModifierMask)consumeCandidateMask {
    @synchronized (self) {
        ScrcpyModifierMask m = [self candidateMask];
        self.candMeta = self.candCtrl = self.candAlt = self.candShift = NO;
        return m;
    }
}

- (BOOL)consumeNextCombinedFlag {
    @synchronized (self) {
        BOOL v = self.nextKeyAlreadyCombined;
        self.nextKeyAlreadyCombined = NO;
        return v;
    }
}

@end


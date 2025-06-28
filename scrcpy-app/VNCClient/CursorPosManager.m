#import "CursorPosManager.h"
#import <QuartzCore/QuartzCore.h>

@interface CursorPosManager ()

// Internal state for dragging
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) CGPoint lastPanPos;
@property (nonatomic, assign) CGPoint dragDisplayPos; // Temporary display position during a drag

// Touchpad state management
@property (nonatomic, assign) BOOL isTouchActive;
@property (nonatomic, assign) BOOL isMouseButtonDown;
@property (nonatomic, assign) CGPoint touchStartLocation;
@property (nonatomic, assign) CGPoint lastTouchLocation;
@property (nonatomic, assign) NSTimeInterval touchStartTime;
@property (nonatomic, assign) NSTimeInterval lastMoveTime;
@property (nonatomic, assign) CGFloat totalTouchDistance;

// Touchpad configuration constants
@property (nonatomic, assign, readonly) CGFloat tapMaxDistance;      // Max distance for tap (default: 10)
@property (nonatomic, assign, readonly) NSTimeInterval tapMaxTime;  // Max time for tap (default: 0.3s)
@property (nonatomic, assign, readonly) CGFloat minDragDistance;    // Min distance to start drag (default: 5)

@end

@implementation CursorPosManager

- (instancetype)init {
    self = [super init];
    if (self) {
        // Original properties
        _underlyingPos = CGPointZero;
        _isDragging = NO;
        _lastPanPos = CGPointZero;
        _dragDisplayPos = CGPointZero;
        _localScreenSize = CGSizeZero;
        _remoteScreenSize = CGSizeZero;
        
        // Touchpad properties
        _isTouchActive = NO;
        _isMouseButtonDown = NO;
        _touchStartLocation = CGPointZero;
        _lastTouchLocation = CGPointZero;
        _touchStartTime = 0;
        _lastMoveTime = 0;
        _totalTouchDistance = 0;
        
        // Sensitivity settings
        _sensitivity = 1.0;
        _scrollSensitivity = 1.0;
        
        // Configuration constants
        _tapMaxDistance = 10.0;
        _tapMaxTime = 0.3;
        _minDragDistance = 5.0;
    }
    return self;
}

- (CGPoint)displayPos {
    // If dragging, return the temporary drag position, otherwise the stable underlying position.
    return self.isDragging ? self.dragDisplayPos : self.underlyingPos;
}

- (CGPoint)remoteCursorPos {
    if (CGSizeEqualToSize(self.localScreenSize, CGSizeZero) || CGSizeEqualToSize(self.remoteScreenSize, CGSizeZero)) {
        return CGPointZero; // Return zero point if screen sizes are invalid
    }

    CGFloat scaleX = self.remoteScreenSize.width / self.localScreenSize.width;
    CGFloat scaleY = self.remoteScreenSize.height / self.localScreenSize.height;

    CGFloat remoteX = self.displayPos.x * scaleX;
    CGFloat remoteY = self.displayPos.y * scaleY;

    // Strict boundary checking - ensure coordinates are within remote screen bounds
    remoteX = MAX(0, MIN(remoteX, self.remoteScreenSize.width - 1));
    remoteY = MAX(0, MIN(remoteY, self.remoteScreenSize.height - 1));

    return CGPointMake(remoteX, remoteY);
}

- (void)beginMove:(CGPoint)startPos {
    self.isDragging = YES;
    self.lastPanPos = startPos;
    // Start the drag from the last known stable position
    self.dragDisplayPos = self.underlyingPos;
}

- (void)moveTo:(CGPoint)newPos {
    if (!self.isDragging) {
        return;
    }

    // Calculate the change in position from the last pan event
    CGFloat deltaX = newPos.x - self.lastPanPos.x;
    CGFloat deltaY = newPos.y - self.lastPanPos.y;

    // Apply the delta to our current temporary display position
    CGPoint newDisplayPos = CGPointMake(self.dragDisplayPos.x + deltaX, self.dragDisplayPos.y + deltaY);

    // Enhanced boundary checking - clamp the new position within valid bounds
    if (!CGSizeEqualToSize(self.localScreenSize, CGSizeZero) && !CGSizeEqualToSize(self.remoteScreenSize, CGSizeZero)) {
        // First clamp to local screen bounds to prevent extreme values
        newDisplayPos.x = MAX(0, MIN(newDisplayPos.x, self.localScreenSize.width));
        newDisplayPos.y = MAX(0, MIN(newDisplayPos.y, self.localScreenSize.height));
        
        // Convert to remote coordinates for precise boundary checking
        CGFloat scaleToRemoteX = self.remoteScreenSize.width / self.localScreenSize.width;
        CGFloat scaleToRemoteY = self.remoteScreenSize.height / self.localScreenSize.height;
        CGFloat remoteX = newDisplayPos.x * scaleToRemoteX;
        CGFloat remoteY = newDisplayPos.y * scaleToRemoteY;

        // Strict boundary enforcement for remote coordinates
        remoteX = MAX(0, MIN(remoteX, self.remoteScreenSize.width - 1));
        remoteY = MAX(0, MIN(remoteY, self.remoteScreenSize.height - 1));

        // Convert back to local coordinates
        CGFloat scaleToLocalX = self.localScreenSize.width / self.remoteScreenSize.width;
        CGFloat scaleToLocalY = self.localScreenSize.height / self.remoteScreenSize.height;
        newDisplayPos = CGPointMake(remoteX * scaleToLocalX, remoteY * scaleToLocalY);
    } else {
        // Fallback boundary checking when screen sizes are invalid
        newDisplayPos = CGPointZero;
    }

    // Update the temporary display position and the last pan position
    self.dragDisplayPos = newDisplayPos;
    self.lastPanPos = newPos;
}

- (void)stopMove {
    if (!self.isDragging) {
        return;
    }
    
    // The drag is over, commit the temporary position to the stable underlying position
    self.underlyingPos = self.dragDisplayPos;

    // Reset dragging state
    self.isDragging = NO;
    self.lastPanPos = CGPointZero;
}

#pragma mark - Touchpad Methods

- (void)handleTouchBegin:(CGPoint)location {
    NSLog(@"🖱️ [CursorPosManager] Touch begin at: (%.1f, %.1f)", location.x, location.y);
    
    self.isTouchActive = YES;
    self.touchStartLocation = location;
    self.lastTouchLocation = location;
    self.touchStartTime = CACurrentMediaTime();
    self.lastMoveTime = self.touchStartTime;
    self.totalTouchDistance = 0;
    
    // Update cursor position to touch location
    [self updateCursorPosition:location];
}

- (void)handleTouchMove:(CGPoint)location {
    if (!self.isTouchActive) {
        return;
    }
    
    NSTimeInterval currentTime = CACurrentMediaTime();
    CGFloat deltaX = (location.x - self.lastTouchLocation.x) * self.sensitivity;
    CGFloat deltaY = (location.y - self.lastTouchLocation.y) * self.sensitivity;
    
    // Calculate total distance for gesture recognition
    CGFloat distance = sqrt(pow(location.x - self.touchStartLocation.x, 2) + 
                           pow(location.y - self.touchStartLocation.y, 2));
    self.totalTouchDistance = distance;
    
    // Update cursor position with relative movement
    CGPoint newPos = CGPointMake(self.underlyingPos.x + deltaX, 
                                self.underlyingPos.y + deltaY);
    
    // Apply boundary constraints
    newPos = [self constrainPositionToBounds:newPos];
    self.underlyingPos = newPos;
    
    // Check if we should start dragging
    if (!self.isMouseButtonDown && distance > self.minDragDistance && 
        (currentTime - self.touchStartTime) > 0.1) {
        
        NSLog(@"🖱️ [CursorPosManager] Starting drag at distance: %.1f", distance);
        self.isMouseButtonDown = YES;
        
        // Notify delegate of drag start
        CGPoint remotePos = self.remoteCursorPos;
        if ([self.delegate respondsToSelector:@selector(cursorPosManager:didGenerateEvent:atRemoteLocation:)]) {
            [self.delegate cursorPosManager:self 
                           didGenerateEvent:TouchpadEventTypeDragStart 
                           atRemoteLocation:remotePos];
        }
    }
    
    // If dragging, send drag events
    if (self.isMouseButtonDown) {
        CGPoint remotePos = self.remoteCursorPos;
        if ([self.delegate respondsToSelector:@selector(cursorPosManager:didGenerateEvent:atRemoteLocation:)]) {
            [self.delegate cursorPosManager:self 
                           didGenerateEvent:TouchpadEventTypeDrag 
                           atRemoteLocation:remotePos];
        }
    } else {
        // Just moving cursor
        CGPoint remotePos = self.remoteCursorPos;
        if ([self.delegate respondsToSelector:@selector(cursorPosManager:didUpdateCursorPosition:)]) {
            [self.delegate cursorPosManager:self didUpdateCursorPosition:remotePos];
        }
    }
    
    self.lastTouchLocation = location;
    self.lastMoveTime = currentTime;
}

- (void)handleTouchEnd:(CGPoint)location {
    if (!self.isTouchActive) {
        return;
    }
    
    NSLog(@"🖱️ [CursorPosManager] Touch end at: (%.1f, %.1f), distance: %.1f", 
          location.x, location.y, self.totalTouchDistance);
    
    NSTimeInterval touchDuration = CACurrentMediaTime() - self.touchStartTime;
    
    // If we were dragging, end the drag
    if (self.isMouseButtonDown) {
        NSLog(@"🖱️ [CursorPosManager] Ending drag");
        CGPoint remotePos = self.remoteCursorPos;
        if ([self.delegate respondsToSelector:@selector(cursorPosManager:didGenerateEvent:atRemoteLocation:)]) {
            [self.delegate cursorPosManager:self 
                           didGenerateEvent:TouchpadEventTypeDragEnd 
                           atRemoteLocation:remotePos];
        }
        self.isMouseButtonDown = NO;
    } else if (self.totalTouchDistance <= self.tapMaxDistance && touchDuration <= self.tapMaxTime) {
        // This was a tap
        NSLog(@"🖱️ [CursorPosManager] Detected tap");
        [self handleTap:location];
    }
    
    [self resetTouchState];
}

- (void)handleTap:(CGPoint)location {
    NSLog(@"🖱️ [CursorPosManager] Processing tap at: (%.1f, %.1f)", location.x, location.y);
    
    // Update cursor position to tap location
    [self updateCursorPosition:location];
    
    // Generate tap event
    CGPoint remotePos = self.remoteCursorPos;
    if ([self.delegate respondsToSelector:@selector(cursorPosManager:didGenerateEvent:atRemoteLocation:)]) {
        [self.delegate cursorPosManager:self 
                       didGenerateEvent:TouchpadEventTypeTap 
                       atRemoteLocation:remotePos];
    }
}

- (void)handleTwoFingerTap:(CGPoint)location {
    NSLog(@"🖱️ [CursorPosManager] Processing two-finger tap (right click) at: (%.1f, %.1f)", location.x, location.y);
    
    // Update cursor position to tap location
    [self updateCursorPosition:location];
    
    // Generate two-finger tap event (right click)
    CGPoint remotePos = self.remoteCursorPos;
    if ([self.delegate respondsToSelector:@selector(cursorPosManager:didGenerateEvent:atRemoteLocation:)]) {
        [self.delegate cursorPosManager:self 
                       didGenerateEvent:TouchpadEventTypeTwoFingerTap 
                       atRemoteLocation:remotePos];
    }
}

- (void)handleScroll:(CGPoint)location deltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY {
    NSLog(@"🖱️ [CursorPosManager] Processing scroll at: (%.1f, %.1f) delta: (%.1f, %.1f)", 
          location.x, location.y, deltaX, deltaY);
    
    // Update cursor position to scroll location
    [self updateCursorPosition:location];
    
    // Apply scroll sensitivity
    CGFloat adjustedDeltaX = deltaX * self.scrollSensitivity;
    CGFloat adjustedDeltaY = deltaY * self.scrollSensitivity;
    
    // Generate scroll event
    CGPoint remotePos = self.remoteCursorPos;
    if ([self.delegate respondsToSelector:@selector(cursorPosManager:didGenerateScrollEvent:deltaX:deltaY:)]) {
        [self.delegate cursorPosManager:self 
                didGenerateScrollEvent:remotePos 
                                deltaX:adjustedDeltaX 
                                deltaY:adjustedDeltaY];
    }
}

- (void)resetState {
    NSLog(@"🖱️ [CursorPosManager] Resetting all state");
    
    // Reset original state
    self.isDragging = NO;
    self.lastPanPos = CGPointZero;
    self.dragDisplayPos = CGPointZero;
    
    // Reset touchpad state
    [self resetTouchState];
}

#pragma mark - Private Helper Methods

- (void)resetTouchState {
    self.isTouchActive = NO;
    self.isMouseButtonDown = NO;
    self.touchStartLocation = CGPointZero;
    self.lastTouchLocation = CGPointZero;
    self.touchStartTime = 0;
    self.lastMoveTime = 0;
    self.totalTouchDistance = 0;
}

- (void)updateCursorPosition:(CGPoint)location {
    self.underlyingPos = [self constrainPositionToBounds:location];
    
    // Notify delegate of cursor position update
    CGPoint remotePos = self.remoteCursorPos;
    if ([self.delegate respondsToSelector:@selector(cursorPosManager:didUpdateCursorPosition:)]) {
        [self.delegate cursorPosManager:self didUpdateCursorPosition:remotePos];
    }
}

- (CGPoint)constrainPositionToBounds:(CGPoint)position {
    if (CGSizeEqualToSize(self.localScreenSize, CGSizeZero)) {
        return position;
    }
    
    CGFloat constrainedX = MAX(0, MIN(position.x, self.localScreenSize.width));
    CGFloat constrainedY = MAX(0, MIN(position.y, self.localScreenSize.height));
    
    return CGPointMake(constrainedX, constrainedY);
}

@end
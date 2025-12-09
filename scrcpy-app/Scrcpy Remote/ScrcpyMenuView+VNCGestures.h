//
//  ScrcpyMenuView+VNCGestures.h
//  Scrcpy Remote
//
//  VNC gesture handling category for ScrcpyMenuView
//

#import "ScrcpyMenuView.h"

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyMenuView (VNCGestures) <UIGestureRecognizerDelegate>

// VNC Gesture Management
- (void)addPinchGesture;
- (void)removePinchGesture;
- (void)addDragGesture;
- (void)removeDragGesture;
- (void)resetDragOffset;
- (void)addTapGesture;
- (void)removeTapGesture;
- (void)setupGesturePriorities;

// VNC Gesture Handlers
- (void)handleVNCPinch:(UIPinchGestureRecognizer *)gesture;
- (void)handleDrag:(UIPanGestureRecognizer *)gesture;
- (void)handleScroll:(UIPanGestureRecognizer *)gesture;
- (void)handleVNCTap:(UITapGestureRecognizer *)gesture;
- (void)handleVNCTwoFingerTap:(UITapGestureRecognizer *)gesture;

// Helper Methods
- (UIWindow *)getSDLWindow;
- (BOOL)isVNCGesture:(UIGestureRecognizer *)gestureRecognizer;
- (NSString *)gestureNameForRecognizer:(UIGestureRecognizer *)gestureRecognizer;
- (CGPoint)normalizedOffsetForTranslation:(CGPoint)translation viewSize:(CGSize)viewSize;

// Delegate Notification Helpers
- (void)notifyDelegateWithDragState:(NSString *)state location:(CGPoint)location viewSize:(CGSize)viewSize offset:(CGPoint)offset;
- (void)notifyDelegateWithNormalizedOffset:(CGPoint)normalizedOffset viewSize:(CGSize)viewSize isEnd:(BOOL)isEnd;

// VNC Touch Event Forwarding
- (void)forwardTouchAsMouseMoveToVNC:(CGPoint)location;
- (void)forwardTouchAsMouseDragToVNC:(CGPoint)location;
- (void)forwardTouchEndAsMouseEventToVNC:(CGPoint)location withTouch:(UITouch *)touch;
- (void)forwardTouchCancelToVNC:(CGPoint)location;

@end

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyInputMaskView : UIView

// Initialize with frame
- (instancetype)initWithFrame:(CGRect)frame;

// Show in a specific view
- (void)showInView:(UIView *)parentView;

// Hide and remove from superview
- (void)hide;

// Show a keyboard toolbar above given keyboard frame
// deviceTypeString: @"adb" or @"vnc" (others treated as vnc)
- (void)showKeyboardToolbarAboveKeyboardFrame:(CGRect)keyboardFrame
                             deviceTypeString:(nullable NSString *)deviceTypeString
                                     duration:(NSTimeInterval)duration
                                         curve:(UIViewAnimationCurve)curve;

// Hide keyboard toolbar with animation synced with keyboard hide (optional)
- (void)hideKeyboardToolbarWithNotification:(NSNotification *)notification;

@end

NS_ASSUME_NONNULL_END 

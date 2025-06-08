#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyInputMaskView : UIView

// Initialize with frame
- (instancetype)initWithFrame:(CGRect)frame;

// Show in a specific view
- (void)showInView:(UIView *)parentView;

// Hide and remove from superview
- (void)hide;

@end

NS_ASSUME_NONNULL_END 
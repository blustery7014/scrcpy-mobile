#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ScrcpyMenuMaskViewDelegate <NSObject>
- (void)didTapMenuMask;
@end

@interface ScrcpyMenuMaskView : UIView

@property (nonatomic, weak) id<ScrcpyMenuMaskViewDelegate> delegate;

// Initialize with frame
- (instancetype)initWithFrame:(CGRect)frame;

// Show/hide methods
- (void)showInView:(UIView *)parentView;
- (void)hide;

// Update frame to match parent view
- (void)updateFrame;

@end

NS_ASSUME_NONNULL_END 
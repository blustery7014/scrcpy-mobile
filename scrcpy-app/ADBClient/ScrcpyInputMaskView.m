#import "ScrcpyInputMaskView.h"
#import <SDL2/SDL_system.h>

@implementation ScrcpyInputMaskView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Setup view
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        
        // Add tap gesture
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] 
                                             initWithTarget:self 
                                             action:@selector(handleTap:)];
        [self addGestureRecognizer:tapGesture];
        
        // Register for orientation change notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(orientationDidChange:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    // Remove notification observer
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)orientationDidChange:(NSNotification *)notification {
    // Update frame when device orientation changes
    if (self.superview) {
        self.frame = self.superview.bounds;
    }
}

- (void)showInView:(UIView *)parentView {
    // Remove from any previous superview
    [self removeFromSuperview];
    
    // Get window for full screen coverage
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    
    // Set frame to match parent view (full screen)
    if (keyWindow) {
        CGRect screenBounds = keyWindow.bounds;
        self.frame = [parentView.window convertRect:screenBounds fromWindow:keyWindow];
    } else {
        self.frame = parentView.bounds;
    }
    
    // Add to parent view, ensure it's in front
    [parentView addSubview:self];
    
    // Make sure it's initially visible
    self.alpha = 1.0;
}

- (void)hide {
    // Remove from superview
    [UIView animateWithDuration:0.1 animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    NSLog(@"Input mask view tapped - stopping text input");
    
    // Stop text input
    SDL_StopTextInput();
    
    // Hide mask view
    [self hide];
}

@end 
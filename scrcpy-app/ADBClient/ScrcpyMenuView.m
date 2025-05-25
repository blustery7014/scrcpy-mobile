#import "ScrcpyMenuView.h"
#import "ScrcpyMenuMaskView.h"
#import <SDL2/SDL_system.h>
#import <SDL2/SDL_syswm.h>
#import <SDL2/SDL_mouse.h>
#import "ScrcpyADBClient.h"

// Add logging macro
#define LOG_POSITION(fmt, ...) NSLog(@"[ScrcpyMenuView] " fmt, ##__VA_ARGS__)

// MARK: - UI Constants

// Capsule View Constants
static const CGFloat kCapsuleWidth = 55.0f;
static const CGFloat kCapsuleHeight = 26.0f;
static const CGFloat kCapsuleCornerRadius = 13.0f;
static const CGFloat kCapsuleHandleIconWidth = 31.0f;
static const CGFloat kCapsuleHandleIconHeight = 20.0f;
static const CGFloat kCapsuleHandleIconX = 12.0f;
static const CGFloat kCapsuleHandleIconY = 3.0f;

// Capsule Alpha Values
static const CGFloat kCapsuleAlphaIdle = 0.3f;
static const CGFloat kCapsuleAlphaNormal = 0.8f;
static const CGFloat kCapsuleAlphaExpanded = 0.8f;

// Menu View Constants
static const CGFloat kMenuHeight = 60.0f;
static const CGFloat kMenuCornerRadius = 30.0f;
static const CGFloat kMenuHorizontalPadding = 5.0f;
static const CGFloat kMenuVerticalSpacing = 10.0f;

// Button Constants
static const CGFloat kButtonWidth = 60.0f;
static const CGFloat kButtonHeight = 60.0f;
static const CGFloat kButtonSpacing = 0.0f;

// Animation Constants
static const CGFloat kAnimationDuration = 0.15f;
static const CGFloat kMenuAnimationDuration = 0.25f;
static const CGFloat kMenuAnimationDelay = 0.0f;
static const CGFloat kMenuAnimationSpringDamping = 0.6f;
static const CGFloat kMenuAnimationSpringVelocity = 0.5f;
static const CGFloat kFadeTimerInterval = 3.0f;

// Position Constants
static const CGFloat kDefaultPositionRatioX = 0.8f; // 右下方
static const CGFloat kDefaultPositionRatioY = 0.8f; // 右下方

// Dynamic Island avoidance constants
static const CGFloat kDynamicIslandWidth = 100.0f;

@interface ScrcpyMenuView () <ScrcpyMenuMaskViewDelegate>

// UI Elements
@property (nonatomic, strong) UIView *capsuleView;
@property (nonatomic, strong) UIView *capsuleBackgroundView;
@property (nonatomic, strong) UIImageView *capsuleHandleIcon;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, strong) ScrcpyMenuMaskView *maskView;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIButton *homeButton;
@property (nonatomic, strong) UIButton *switchButton;
@property (nonatomic, strong) UIButton *keyboardButton;
@property (nonatomic, strong) UIButton *actionsButton;
@property (nonatomic, strong) UIButton *disconnectButton;

// State
@property (nonatomic, assign) BOOL isExpanded;
@property (nonatomic, assign) CGPoint positionRatio; // 相对于屏幕中心的比例 (-1 to 1)
@property (nonatomic, strong) NSTimer *fadeTimer;
@property (nonatomic, weak) UIWindow *activeWindow;

// Private method declarations
- (void)savePositionRatio:(CGPoint)ratio;
- (CGPoint)loadPositionRatio;
- (void)updatePositionFromRatio;
- (void)updateRatioFromPosition;
- (CGRect)getDynamicIslandRect:(UIWindow *)window;
- (BOOL)doesCapsuleOverlapDynamicIsland:(UIWindow *)window;
- (CGPoint)adjustPositionToAvoidDynamicIsland:(UIWindow *)window;

@end

@implementation ScrcpyMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _isExpanded = NO;
        
        LOG_POSITION(@"Initializing menu view with frame: (%.1f, %.1f, %.1f, %.1f)",
                     frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
        
        // 设置为可接收用户交互事件
        self.userInteractionEnabled = YES;
        
        // Load saved position ratio or use default
        _positionRatio = [self loadPositionRatio];
        LOG_POSITION(@"Loaded position ratio: (%.3f, %.3f)", _positionRatio.x, _positionRatio.y);
        
        [self setupViews];
        [self setupGestures];
        [self startFadeTimer];
        
        // Set initial frame size based on capsule dimensions
        self.frame = CGRectMake(0, 0, kCapsuleWidth, kCapsuleHeight);
        
        // Register for orientation change notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(orientationDidChange:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)orientationDidChange:(NSNotification *)notification {
    LOG_POSITION(@"Device orientation changed, updating layout");
    // Update layout after a short delay to ensure the rotation animation is complete
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateLayout];
    });
}

#pragma mark - Position Management

- (CGPoint)loadPositionRatio {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGFloat savedRatioX = [defaults floatForKey:@"ScrcpyMenuPositionRatioX"];
    CGFloat savedRatioY = [defaults floatForKey:@"ScrcpyMenuPositionRatioY"];
    
    // Check if we have valid saved values (center-relative range: -1 to 1)
    if (savedRatioX >= -1 && savedRatioX <= 1 && savedRatioY >= -1 && savedRatioY <= 1) {
        // If both values are zero, it means no saved data, use default
        if (savedRatioX == 0 && savedRatioY == 0) {
            LOG_POSITION(@"No saved position, using default (%.3f, %.3f)", kDefaultPositionRatioX, kDefaultPositionRatioY);
            return CGPointMake(kDefaultPositionRatioX, kDefaultPositionRatioY);
        }
        LOG_POSITION(@"Using saved position ratio");
        return CGPointMake(savedRatioX, savedRatioY);
    } else {
        LOG_POSITION(@"Invalid saved position, using default (%.3f, %.3f)", kDefaultPositionRatioX, kDefaultPositionRatioY);
        return CGPointMake(kDefaultPositionRatioX, kDefaultPositionRatioY);
    }
}

- (void)savePositionRatio:(CGPoint)ratio {
    LOG_POSITION(@"Saving position ratio: (%.3f, %.3f)", ratio.x, ratio.y);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setFloat:ratio.x forKey:@"ScrcpyMenuPositionRatioX"];
    [defaults setFloat:ratio.y forKey:@"ScrcpyMenuPositionRatioY"];
    [defaults synchronize];
}

- (void)updatePositionFromRatio {
    UIWindow *window = [self activeWindow];
    if (!window) return;
    
    LOG_POSITION(@"updatePositionFromRatio called - Current ratio: (%.3f, %.3f)", 
                 self.positionRatio.x, self.positionRatio.y);
    
    CGRect screenBounds = window.bounds;
    CGFloat screenWidth = screenBounds.size.width;
    CGFloat screenHeight = screenBounds.size.height;
    
    LOG_POSITION(@"Screen size: %.1f x %.1f", screenWidth, screenHeight);
    
    // Calculate screen center
    CGFloat screenCenterX = screenWidth / 2.0;
    CGFloat screenCenterY = screenHeight / 2.0;
    
    // Calculate reachable boundaries (no safe area constraints)
    CGFloat minFrameX = 0;
    CGFloat maxFrameX = screenWidth - self.frame.size.width;
    CGFloat minFrameY = 0;
    CGFloat maxFrameY = screenHeight - self.frame.size.height;
    
    // Calculate the reachable center positions
    CGFloat minCenterX = minFrameX + self.frame.size.width / 2.0;
    CGFloat maxCenterX = maxFrameX + self.frame.size.width / 2.0;
    CGFloat minCenterY = minFrameY + self.frame.size.height / 2.0;
    CGFloat maxCenterY = maxFrameY + self.frame.size.height / 2.0;
    
    // Calculate maximum offsets from center
    CGFloat maxOffsetX = MAX(fabs(minCenterX - screenCenterX), fabs(maxCenterX - screenCenterX));
    CGFloat maxOffsetY = MAX(fabs(minCenterY - screenCenterY), fabs(maxCenterY - screenCenterY));
    
    LOG_POSITION(@"Screen center: (%.1f, %.1f), Max offsets: (%.1f, %.1f)",
                 screenCenterX, screenCenterY, maxOffsetX, maxOffsetY);
    
    // Calculate capsule center position using center-relative ratio
    // Ratio range is -1 to 1, where 0 means center
    CGFloat capsuleCenterX = screenCenterX + (maxOffsetX * self.positionRatio.x);
    CGFloat capsuleCenterY = screenCenterY + (maxOffsetY * self.positionRatio.y);
    
    LOG_POSITION(@"Target capsule center: (%.1f, %.1f)", capsuleCenterX, capsuleCenterY);
    
    // Convert center position to top-left corner position
    CGFloat x = capsuleCenterX - self.frame.size.width / 2.0;
    CGFloat y = capsuleCenterY - self.frame.size.height / 2.0;
    
    // Ensure position is within screen bounds
    CGFloat originalX = x, originalY = y;
    x = MAX(0, MIN(screenWidth - self.frame.size.width, x));
    y = MAX(0, MIN(screenHeight - self.frame.size.height, y));
    
    if (originalX != x || originalY != y) {
        LOG_POSITION(@"Position was clamped from (%.1f, %.1f) to (%.1f, %.1f)", originalX, originalY, x, y);
    }
    
    LOG_POSITION(@"Final position: (%.1f, %.1f)", x, y);
    
    // Update frame
    self.frame = CGRectMake(x, y, self.frame.size.width, self.frame.size.height);
    
    // Check for Dynamic Island overlap and adjust if necessary
    if ([self doesCapsuleOverlapDynamicIsland:window]) {
        LOG_POSITION(@"Position overlaps with Dynamic Island, adjusting...");
        CGPoint adjustedPosition = [self adjustPositionToAvoidDynamicIsland:window];
        self.frame = CGRectMake(adjustedPosition.x, adjustedPosition.y, self.frame.size.width, self.frame.size.height);
        LOG_POSITION(@"Position adjusted to: (%.1f, %.1f)", adjustedPosition.x, adjustedPosition.y);
    }
}

- (void)updateRatioFromPosition {
    UIWindow *window = [self activeWindow];
    if (!window) return;
    
    LOG_POSITION(@"updateRatioFromPosition called - Current frame: (%.1f, %.1f, %.1f, %.1f)", 
                 self.frame.origin.x, self.frame.origin.y, self.frame.size.width, self.frame.size.height);
    
    CGRect screenBounds = window.bounds;
    CGFloat screenWidth = screenBounds.size.width;
    CGFloat screenHeight = screenBounds.size.height;
    
    // Calculate screen center
    CGFloat screenCenterX = screenWidth / 2.0;
    CGFloat screenCenterY = screenHeight / 2.0;
    
    // Calculate current capsule center
    CGFloat capsuleCenterX = self.frame.origin.x + self.frame.size.width / 2.0;
    CGFloat capsuleCenterY = self.frame.origin.y + self.frame.size.height / 2.0;
    
    // Calculate reachable boundaries (no safe area constraints)
    CGFloat minFrameX = 0;
    CGFloat maxFrameX = screenWidth - self.frame.size.width;
    CGFloat minFrameY = 0;
    CGFloat maxFrameY = screenHeight - self.frame.size.height;
    
    // Calculate the reachable center positions
    CGFloat minCenterX = minFrameX + self.frame.size.width / 2.0;
    CGFloat maxCenterX = maxFrameX + self.frame.size.width / 2.0;
    CGFloat minCenterY = minFrameY + self.frame.size.height / 2.0;
    CGFloat maxCenterY = maxFrameY + self.frame.size.height / 2.0;
    
    // Calculate maximum offsets from center
    CGFloat maxOffsetX = MAX(fabs(minCenterX - screenCenterX), fabs(maxCenterX - screenCenterX));
    CGFloat maxOffsetY = MAX(fabs(minCenterY - screenCenterY), fabs(maxCenterY - screenCenterY));
    
    LOG_POSITION(@"Screen center: (%.1f, %.1f), Capsule center: (%.1f, %.1f)", screenCenterX, screenCenterY, capsuleCenterX, capsuleCenterY);
    LOG_POSITION(@"Reachable center range - X: [%.1f, %.1f], Y: [%.1f, %.1f]", minCenterX, maxCenterX, minCenterY, maxCenterY);
    LOG_POSITION(@"Max offsets: (%.1f, %.1f)", maxOffsetX, maxOffsetY);
    
    // Calculate center-relative ratio
    CGFloat ratioX = 0;
    CGFloat ratioY = 0;
    
    if (maxOffsetX > 0) {
        ratioX = (capsuleCenterX - screenCenterX) / maxOffsetX;
        ratioX = MAX(-1, MIN(1, ratioX));
    }
    
    if (maxOffsetY > 0) {
        ratioY = (capsuleCenterY - screenCenterY) / maxOffsetY;
        ratioY = MAX(-1, MIN(1, ratioY));
    }
    
    LOG_POSITION(@"Calculated center-relative ratio: (%.3f, %.3f)", ratioX, ratioY);
    LOG_POSITION(@"Previous ratio was: (%.3f, %.3f)", self.positionRatio.x, self.positionRatio.y);
    
    // Store the center-relative ratio
    self.positionRatio = CGPointMake(ratioX, ratioY);
    [self savePositionRatio:self.positionRatio];
    
    LOG_POSITION(@"Stored new center-relative ratio: (%.3f, %.3f)", ratioX, ratioY);
}

- (void)setupViews {
    // Capsule view (container)
    self.capsuleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kCapsuleWidth, kCapsuleHeight)];
    self.capsuleView.clipsToBounds = YES;
    
    // Capsule background view
    self.capsuleBackgroundView = [[UIView alloc] initWithFrame:self.capsuleView.bounds];
    self.capsuleBackgroundView.layer.cornerRadius = kCapsuleCornerRadius;
    self.capsuleBackgroundView.clipsToBounds = YES;
    
    // Gradient layer for capsule background
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = self.capsuleBackgroundView.bounds;
    gradientLayer.colors = @[
        (id)[UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:0.85].CGColor,
        (id)[UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.9].CGColor
    ];
    gradientLayer.startPoint = CGPointMake(0, 0);
    gradientLayer.endPoint = CGPointMake(1, 1);
    [self.capsuleBackgroundView.layer insertSublayer:gradientLayer atIndex:0];
    
    // Add handle icon to the capsule
    self.capsuleHandleIcon = [[UIImageView alloc] initWithFrame:CGRectMake(kCapsuleHandleIconX, kCapsuleHandleIconY, kCapsuleHandleIconWidth, kCapsuleHandleIconHeight)];
    self.capsuleHandleIcon.image = [UIImage systemImageNamed:@"ellipsis"];
    self.capsuleHandleIcon.tintColor = [UIColor colorWithWhite:1.0 alpha:1.0];
    self.capsuleHandleIcon.contentMode = UIViewContentModeScaleAspectFit;
    
    // Add subviews to capsule view
    [self.capsuleView addSubview:self.capsuleBackgroundView];
    [self.capsuleView addSubview:self.capsuleHandleIcon];
    [self addSubview:self.capsuleView];
    
    // Menu view (expanded state)
    UIWindow *window = [self activeWindow];
    self.activeWindow = window;
    CGFloat menuWidth = window.bounds.size.width - (kMenuHorizontalPadding * 2);
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, kMenuHeight)];
    self.menuView.layer.cornerRadius = kMenuCornerRadius;
    self.menuView.clipsToBounds = YES;
    self.menuView.alpha = 0;
    self.menuView.hidden = YES;
    
    // Gradient layer for menu
    CAGradientLayer *menuGradientLayer = [CAGradientLayer layer];
    menuGradientLayer.frame = CGRectMake(0, 0, menuWidth, kMenuHeight);
    menuGradientLayer.colors = @[
        (id)[UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:0.85].CGColor,
        (id)[UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.9].CGColor
    ];
    menuGradientLayer.startPoint = CGPointMake(0, 0);
    menuGradientLayer.endPoint = CGPointMake(1, 0);
    [self.menuView.layer insertSublayer:menuGradientLayer atIndex:0];
    self.menuView.layer.masksToBounds = YES;
    
    // Create buttons
    CGFloat buttonWidth = kButtonWidth;
    CGFloat buttonHeight = kButtonHeight;
    CGFloat spacing = kButtonSpacing;
    
    // Back button
    self.backButton = [self createButtonWithIcon:@"arrow.left" position:CGRectMake(spacing, 0, buttonWidth, buttonHeight)];
    [self.menuView addSubview:self.backButton];
    
    // Home button
    self.homeButton = [self createButtonWithIcon:@"house" position:CGRectMake(buttonWidth + spacing, 0, buttonWidth, buttonHeight)];
    [self.menuView addSubview:self.homeButton];
    
    // Switch button
    self.switchButton = [self createButtonWithIcon:@"square.stack" position:CGRectMake((buttonWidth + spacing) * 2, 0, buttonWidth, buttonHeight)];
    [self.menuView addSubview:self.switchButton];
    
    // Keyboard button
    self.keyboardButton = [self createButtonWithIcon:@"keyboard" position:CGRectMake((buttonWidth + spacing) * 3, 0, buttonWidth, buttonHeight)];
    [self.menuView addSubview:self.keyboardButton];
    
    // Actions button
    self.actionsButton = [self createButtonWithIcon:@"ellipsis.circle" position:CGRectMake((buttonWidth + spacing) * 4, 0, buttonWidth, buttonHeight)];
    [self.menuView addSubview:self.actionsButton];
    
    // Disconnect button
    self.disconnectButton = [self createButtonWithIcon:@"xmark.circle" position:CGRectMake((buttonWidth + spacing) * 5, 0, buttonWidth, buttonHeight)];
    [self.menuView addSubview:self.disconnectButton];
}

- (UIButton *)createButtonWithIcon:(NSString *)iconName position:(CGRect)frame {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    
    // Set up the button with SF Symbol
    UIImage *icon = [UIImage systemImageNamed:iconName];
    [button setImage:icon forState:UIControlStateNormal];
    button.tintColor = [UIColor whiteColor];
    
    // 确保按钮拦截所有事件
    button.exclusiveTouch = YES;
    
    // 添加自定义事件处理
    [button addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(buttonTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(buttonTouchUpOutside:) forControlEvents:UIControlEventTouchUpOutside];
    [button addTarget:self action:@selector(buttonTouchCancel:) forControlEvents:UIControlEventTouchCancel];
    
    // 存储按钮的标识，用于在事件处理时区分
    button.accessibilityIdentifier = iconName;
    
    return button;
}

- (void)setupGestures {
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    tapGesture.cancelsTouchesInView = YES;
    tapGesture.delaysTouchesEnded = YES;
    [self.capsuleView addGestureRecognizer:tapGesture];
    
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    panGesture.cancelsTouchesInView = YES;
    panGesture.delaysTouchesEnded = YES;
    [self.capsuleView addGestureRecognizer:panGesture];
    
    UITapGestureRecognizer *dismissTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissTap:)];
    dismissTapGesture.cancelsTouchesInView = YES;
    [[self activeWindow] addGestureRecognizer:dismissTapGesture];
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    [self toggleMenuExpansion];
}

- (void)handleDismissTap:(UITapGestureRecognizer *)gesture {
    if (self.isExpanded) {
        CGPoint location = [gesture locationInView:self];
        if (![self.menuView pointInside:[self.menuView convertPoint:location fromView:self] withEvent:nil] &&
            ![self.capsuleView pointInside:[self.capsuleView convertPoint:location fromView:self] withEvent:nil]) {
            // 停止键盘输入
            SDL_StopTextInput();
            
            [self toggleMenuExpansion];
        }
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    // 拖动时恢复胶囊背景正常展示透明度
    self.capsuleBackgroundView.alpha = kCapsuleAlphaNormal;
    
    // 确保使用正确的坐标系（相对于父视图）
    UIView *referenceView = self.superview;
    if (!referenceView) {
        // Fallback to active window if no superview
        referenceView = [self activeWindow];
    }
    
    CGPoint translation = [gesture translationInView:referenceView];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        LOG_POSITION(@"Pan gesture began at position: (%.1f, %.1f)", self.frame.origin.x, self.frame.origin.y);
        LOG_POSITION(@"Current ratio: (%.3f, %.3f)", 
                     self.positionRatio.x, self.positionRatio.y);
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        // Calculate new position based on current frame origin instead of center to avoid compound errors
        CGFloat newX = self.frame.origin.x + translation.x;
        CGFloat newY = self.frame.origin.y + translation.y;
        
        // Update frame directly
        self.frame = CGRectMake(newX, newY, self.frame.size.width, self.frame.size.height);
        [gesture setTranslation:CGPointZero inView:referenceView];
        
        if (self.isExpanded) {
            [self updateMenuPosition];
        }
        
        LOG_POSITION(@"Dragging to position: (%.1f, %.1f)", newX, newY);
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        LOG_POSITION(@"Pan gesture ended, saving position");
        
        // Check for Dynamic Island overlap and adjust if necessary
        UIWindow *window = [self activeWindow];
        if (window && [self doesCapsuleOverlapDynamicIsland:window]) {
            LOG_POSITION(@"Dragged position overlaps with Dynamic Island, adjusting...");
            CGPoint adjustedPosition = [self adjustPositionToAvoidDynamicIsland:window];
            
            // Animate to the adjusted position
            [UIView animateWithDuration:0.3 
                             animations:^{
                self.frame = CGRectMake(adjustedPosition.x, adjustedPosition.y, self.frame.size.width, self.frame.size.height);
            }];
            
            LOG_POSITION(@"Position adjusted to: (%.1f, %.1f)", adjustedPosition.x, adjustedPosition.y);
        }
        
        // 计算并保存新的位置比例
        [self updateRatioFromPosition];
        
        // 拖拽结束后1秒自动变为静止模式透明度
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.isExpanded) {
                [UIView animateWithDuration:0.15 animations:^{
                    self.capsuleBackgroundView.alpha = kCapsuleAlphaIdle;
                }];
            }
        });
    }
}

- (void)toggleMenuExpansion {
    if (self.isExpanded) {
        // 收起菜单
        [UIView animateWithDuration:kAnimationDuration animations:^{
            self.menuView.alpha = 0;
            self.menuView.transform = CGAffineTransformMakeScale(0.5, 0.5);
            // 降低胶囊背景透明度
            self.capsuleBackgroundView.alpha = kCapsuleAlphaIdle;
        } completion:^(BOOL finished) {
            self.menuView.hidden = YES;
            self.menuView.transform = CGAffineTransformIdentity;
            [self.menuView removeFromSuperview];
        }];
        
        // 隐藏遮罩层
        [self.maskView hide];
    } else {
        // 展开菜单
        [self updateMenuPosition];
        self.menuView.hidden = NO;
        self.menuView.alpha = 0;
        self.menuView.transform = CGAffineTransformMakeScale(0.5, 0.5);
        
        // 确保遮罩视图存在且正确初始化
        if (!self.maskView) {
            UIWindow *window = [self activeWindow];
            if (window) {
                self.maskView = [[ScrcpyMenuMaskView alloc] initWithFrame:window.bounds];
                self.maskView.delegate = self;
            }
        }
        
        // 显示遮罩层在window上
        UIWindow *window = [self activeWindow];
        if (window) {
            [self.maskView showInView:window];
            // 将菜单视图添加到window上
            [window addSubview:self.menuView];
        }
        
        [UIView animateWithDuration:kMenuAnimationDuration 
                              delay:kMenuAnimationDelay 
             usingSpringWithDamping:kMenuAnimationSpringDamping
              initialSpringVelocity:kMenuAnimationSpringVelocity
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.menuView.alpha = 1.0;
            self.menuView.transform = CGAffineTransformIdentity;
            // 恢复胶囊背景正常展示透明度
            self.capsuleBackgroundView.alpha = kCapsuleAlphaExpanded;
        } completion:nil];
    }
    
    self.isExpanded = !self.isExpanded;
}

- (void)updateMenuPosition {
    UIWindow *window = [self activeWindow];
    if (!window) return;
    
    CGRect screenBounds = window.bounds;
    // 限制菜单最大宽度为 400
    CGFloat maxMenuWidth = 400.0f;
    CGFloat availableWidth = screenBounds.size.width - (kMenuHorizontalPadding * 2);
    CGFloat menuWidth = MIN(maxMenuWidth, availableWidth);
    CGFloat menuHeight = self.menuView.frame.size.height;
    
    // Convert capsule frame to window coordinates
    CGRect capsuleFrameInWindow = [self.capsuleView convertRect:self.capsuleView.bounds toView:window];
    
    // Calculate available space above and below
    CGFloat spaceAbove = capsuleFrameInWindow.origin.y;
    CGFloat spaceBelow = screenBounds.size.height - (capsuleFrameInWindow.origin.y + capsuleFrameInWindow.size.height);
    
    // Determine menu vertical position
    CGFloat menuY;
    BOOL showAbove = (spaceAbove > spaceBelow) && (spaceAbove >= menuHeight + kMenuVerticalSpacing * 2);
    
    if (showAbove) {
        menuY = capsuleFrameInWindow.origin.y - menuHeight - kMenuVerticalSpacing;
    } else {
        menuY = capsuleFrameInWindow.origin.y + capsuleFrameInWindow.size.height + kMenuVerticalSpacing;
    }
    
    // Ensure menu stays within screen bounds vertically
    menuY = MAX(kMenuHorizontalPadding, 
                MIN(screenBounds.size.height - menuHeight - kMenuHorizontalPadding, menuY));
    
    // Calculate menu horizontal position
    CGFloat menuX;
    CGFloat screenCenterX = screenBounds.size.width / 2.0f;
    CGFloat capsuleCenterX = CGRectGetMidX(capsuleFrameInWindow);
    
    if (menuWidth >= maxMenuWidth) {
        // 当菜单宽度达到最大宽度时，根据胶囊位置决定对齐方式
        if (capsuleCenterX < screenCenterX) {
            // 胶囊在屏幕左边，菜单与胶囊左边对齐
            menuX = capsuleFrameInWindow.origin.x;
        } else {
            // 胶囊在屏幕右边，菜单与胶囊右边对齐
            menuX = capsuleFrameInWindow.origin.x + capsuleFrameInWindow.size.width - menuWidth;
        }
    } else {
        // 当菜单宽度小于最大宽度时，水平居中显示
        menuX = (screenBounds.size.width - menuWidth) / 2.0f;
    }
    
    // Ensure menu stays within screen bounds horizontally
    menuX = MAX(kMenuHorizontalPadding,
                MIN(screenBounds.size.width - menuWidth - kMenuHorizontalPadding, menuX));
    
    // Avoid Dynamic Island area when positioning menu
    CGRect dynamicIslandRect = [self getDynamicIslandRect:window];
    if (dynamicIslandRect.size.height > 0) {
        CGRect proposedMenuRect = CGRectMake(menuX, menuY, menuWidth, menuHeight);
        
        // Check if menu would overlap with Dynamic Island
        if (CGRectIntersectsRect(proposedMenuRect, dynamicIslandRect)) {
            LOG_POSITION(@"Menu would overlap with Dynamic Island, adjusting position");
            
            // Move menu below Dynamic Island
            CGFloat dynamicIslandBottom = dynamicIslandRect.origin.y + dynamicIslandRect.size.height;
            menuY = MAX(menuY, dynamicIslandBottom + kMenuVerticalSpacing);
            
            // Ensure menu still fits on screen
            menuY = MIN(menuY, screenBounds.size.height - menuHeight - kMenuHorizontalPadding);
            
            LOG_POSITION(@"Menu position adjusted to avoid Dynamic Island: Y = %.1f", menuY);
        }
    }
    
    // Update menu frame
    self.menuView.frame = CGRectMake(menuX, menuY, menuWidth, menuHeight);
    
    // Update gradient layer frame
    if (self.menuView.layer.sublayers.count > 0 && 
        [self.menuView.layer.sublayers[0] isKindOfClass:[CAGradientLayer class]]) {
        ((CAGradientLayer *)self.menuView.layer.sublayers[0]).frame = self.menuView.bounds;
    }
    
    [self repositionMenuButtons:menuWidth];
}

- (void)repositionMenuButtons:(CGFloat)menuWidth {
    NSArray *buttons = @[self.backButton, self.homeButton, self.switchButton, 
                         self.keyboardButton, self.actionsButton, self.disconnectButton];
    
    int buttonCount = (int)buttons.count;
    CGFloat buttonWidth = kButtonWidth;
    CGFloat totalButtonsWidth = buttonWidth * buttonCount;
    
    // 计算间距，使按钮均匀分布
    CGFloat spacing = (menuWidth - totalButtonsWidth) / (buttonCount + 1);
    
    // 重新定位每个按钮
    for (int i = 0; i < buttonCount; i++) {
        UIButton *button = buttons[i];
        CGRect frame = button.frame;
        frame.origin.x = spacing + (buttonWidth + spacing) * i;
        button.frame = frame;
    }
}

- (void)startFadeTimer {
    // 移除淡出计时器
    [self.fadeTimer invalidate];
    self.fadeTimer = [NSTimer scheduledTimerWithTimeInterval:kFadeTimerInterval target:self selector:@selector(fadeCapsule) userInfo:nil repeats:NO];
}

- (void)fadeCapsule {
    // 闲置状态只改变胶囊背景透明度
    if (!self.isExpanded) {
        [UIView animateWithDuration:kAnimationDuration animations:^{
            self.capsuleBackgroundView.alpha = kCapsuleAlphaIdle;
        }];
    }
}

#pragma mark - Button Touch Event Handlers

- (void)buttonTouchDown:(UIButton *)sender {
    // 消费事件，不向下传递
}

- (void)buttonTouchUpInside:(UIButton *)sender {
    // 根据按钮标识调用相应的方法
    NSString *identifier = sender.accessibilityIdentifier;
    
    if ([identifier isEqualToString:@"arrow.left"]) {
        [self backButtonTapped:sender];
    } else if ([identifier isEqualToString:@"house"]) {
        [self homeButtonTapped:sender];
    } else if ([identifier isEqualToString:@"square.stack"]) {
        [self switchButtonTapped:sender];
    } else if ([identifier isEqualToString:@"keyboard"]) {
        [self keyboardButtonTapped:sender];
    } else if ([identifier isEqualToString:@"ellipsis.circle"]) {
        [self actionsButtonTapped:sender];
    } else if ([identifier isEqualToString:@"xmark.circle"]) {
        [self disconnectButtonTapped:sender];
    }
}

- (void)buttonTouchUpOutside:(UIButton *)sender {
    // 消费事件，不向下传递
}

- (void)buttonTouchCancel:(UIButton *)sender {
    // 消费事件，不向下传递
}

#pragma mark - Button Actions

- (void)backButtonTapped:(UIButton *)sender {
    // 停止键盘输入
    SDL_StopTextInput();
    
    if ([self.delegate respondsToSelector:@selector(didTapBackButton)]) {
        [self.delegate didTapBackButton];
    }
}

- (void)homeButtonTapped:(UIButton *)sender {
    // 停止键盘输入
    SDL_StopTextInput();
    
    if ([self.delegate respondsToSelector:@selector(didTapHomeButton)]) {
        [self.delegate didTapHomeButton];
    }
}

- (void)switchButtonTapped:(UIButton *)sender {
    // 停止键盘输入
    SDL_StopTextInput();
    
    if ([self.delegate respondsToSelector:@selector(didTapSwitchButton)]) {
        [self.delegate didTapSwitchButton];
    }
}

- (void)keyboardButtonTapped:(UIButton *)sender {
    // 不停止键盘输入，因为这个按钮就是用来启动键盘的
    if ([self.delegate respondsToSelector:@selector(didTapKeyboardButton)]) {
        [self.delegate didTapKeyboardButton];
    }
    [self toggleMenuExpansion];
}

- (void)actionsButtonTapped:(UIButton *)sender {
    // 停止键盘输入
    SDL_StopTextInput();
    
    if ([self.delegate respondsToSelector:@selector(didTapActionsButton)]) {
        [self.delegate didTapActionsButton];
    }
    [self toggleMenuExpansion];
}

- (void)disconnectButtonTapped:(UIButton *)sender {
    // 停止键盘输入
    SDL_StopTextInput();
    
    if ([self.delegate respondsToSelector:@selector(didTapDisconnectButton)]) {
        [self.delegate didTapDisconnectButton];
    }
    [self toggleMenuExpansion];
}

// ScrcpyMenuMaskViewDelegate 方法
- (void)didTapMenuMask {
    if (self.isExpanded) {
        [self toggleMenuExpansion];
    }
}

// 重写hitTest方法，用于处理触摸事件
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden || self.alpha <= 0.01) {
        return nil;
    }
    
    // 检查是否在胶囊视图内
    if (CGRectContainsPoint(self.capsuleView.frame, point)) {
        return self.capsuleView;
    }
    
    // 如果菜单展开，检查是否在菜单视图内
    if (self.isExpanded && !self.menuView.hidden && self.menuView.superview) {
        CGPoint menuPoint = [self convertPoint:point toView:self.menuView];
        if ([self.menuView pointInside:menuPoint withEvent:event]) {
            return [self.menuView hitTest:menuPoint withEvent:event];
        }
    }
    
    return nil; // 不在控制范围内的点击，返回nil
}

// 重写pointInside方法，确定是否应该接收触摸事件
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // 对于胶囊按钮，我们需要精确的命中测试
    if (CGRectContainsPoint(self.capsuleView.frame, point)) {
        return YES;
    }
    
    // 如果菜单展开，检查是否在菜单视图内
    if (self.isExpanded && !self.menuView.hidden && self.menuView.superview) {
        CGPoint menuPoint = [self convertPoint:point toView:self.menuView];
        return [self.menuView pointInside:menuPoint withEvent:event];
    }
    
    return NO;
}

#pragma mark - Touch Event Handling

// 实现这些方法以防止事件向下传递
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // 不调用super方法来阻止事件传递
    // 如果点击在菜单或胶囊上，则消费掉事件
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self];
    
    if ((self.isExpanded && CGRectContainsPoint(self.menuView.frame, point)) || 
        CGRectContainsPoint(self.capsuleView.frame, point)) {
        // 不向下传递
    } else {
        [super touchesBegan:touches withEvent:event];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // 不调用super方法来阻止事件传递
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self];
    
    if ((self.isExpanded && CGRectContainsPoint(self.menuView.frame, point)) || 
        CGRectContainsPoint(self.capsuleView.frame, point)) {
        // 不向下传递
    } else {
        [super touchesMoved:touches withEvent:event];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // 不调用super方法来阻止事件传递
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self];
    
    if ((self.isExpanded && CGRectContainsPoint(self.menuView.frame, point)) || 
        CGRectContainsPoint(self.capsuleView.frame, point)) {
        // 不向下传递
    } else {
        [super touchesEnded:touches withEvent:event];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // 不调用super方法来阻止事件传递
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self];
    
    if ((self.isExpanded && CGRectContainsPoint(self.menuView.frame, point)) || 
        CGRectContainsPoint(self.capsuleView.frame, point)) {
        // 不向下传递
    } else {
        [super touchesCancelled:touches withEvent:event];
    }
}

// Helper method to get active window
- (UIWindow *)activeWindow {
    SDL_Window *window = SDL_GetMouseFocus();
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (SDL_GetWindowWMInfo(window, &info)) {
        UIWindow *uiWindow = info.info.uikit.window;
        return uiWindow;
    }
    return [UIApplication sharedApplication].keyWindow;
}

- (void)addToActiveWindow {
    UIWindow *window = [self activeWindow];
    if (!window) return;
    
    LOG_POSITION(@"addToActiveWindow called");
    
    // Update layout based on current position ratio
    [self updateLayout];
    
    // 确保userInteractionEnabled为YES
    self.userInteractionEnabled = YES;
    self.capsuleView.userInteractionEnabled = YES;
    self.menuView.userInteractionEnabled = YES;
    
    // 确保按钮能拦截所有事件
    for (UIView *subview in self.menuView.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)subview;
            button.exclusiveTouch = YES;
        }
    }
    
    // 初始化遮罩视图
    self.maskView = [[ScrcpyMenuMaskView alloc] initWithFrame:window.bounds];
    self.maskView.delegate = self;
    
    // 设置胶囊背景初始透明度
    self.capsuleBackgroundView.alpha = kCapsuleAlphaIdle;
    
    // 将视图添加到window的最顶层
    [window addSubview:self];
}

- (void)updateLayout {
    UIWindow *window = [self activeWindow];
    if (!window) return;
    
    LOG_POSITION(@"updateLayout called");
    
    // Update position based on current ratio
    [self updatePositionFromRatio];
    
    // If menu is expanded, update its position too
    if (self.isExpanded) {
        [self updateMenuPosition];
    }
}

#pragma mark - Dynamic Island Avoidance

/*
 * Dynamic Island Avoidance System
 * 
 * This system prevents the capsule from overlapping with the Dynamic Island area on supported devices.
 * 
 * Dynamic Island Definition:
 * - Width: 100 points (centered horizontally)
 * - Height: Equal to safe area top inset
 * - Position: Top center of the screen
 * 
 * Avoidance Strategy:
 * 1. During layout updates: Check and adjust position if capsule would overlap
 * 2. During drag operations: Animate to safe position when drag ends in Dynamic Island area
 * 3. Menu positioning: Ensure expanded menu doesn't overlap with Dynamic Island
 * 
 * The system chooses the minimal movement required (left, right, or down) to resolve overlaps.
 */

- (CGRect)getDynamicIslandRect:(UIWindow *)window {
    if (!window) return CGRectZero;
    
    CGRect screenBounds = window.bounds;
    CGFloat screenWidth = screenBounds.size.width;
    
    // Get safe area insets to determine dynamic island height
    UIEdgeInsets safeAreaInsets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeAreaInsets = window.safeAreaInsets;
    }
    
    // Dynamic island area: center width 100, height = safe area top
    CGFloat dynamicIslandHeight = safeAreaInsets.top;
    CGFloat dynamicIslandX = (screenWidth - kDynamicIslandWidth) / 2.0;
    CGFloat dynamicIslandY = 0;
    
    CGRect dynamicIslandRect = CGRectMake(dynamicIslandX, dynamicIslandY, kDynamicIslandWidth, dynamicIslandHeight);
    
    LOG_POSITION(@"Dynamic Island rect: (%.1f, %.1f, %.1f, %.1f)", 
                 dynamicIslandRect.origin.x, dynamicIslandRect.origin.y, 
                 dynamicIslandRect.size.width, dynamicIslandRect.size.height);
    
    return dynamicIslandRect;
}

- (BOOL)doesCapsuleOverlapDynamicIsland:(UIWindow *)window {
    CGRect dynamicIslandRect = [self getDynamicIslandRect:window];
    
    // If dynamic island height is 0 (no safe area top), no overlap possible
    if (dynamicIslandRect.size.height <= 0) {
        return NO;
    }
    
    CGRect capsuleRect = self.frame;
    BOOL overlap = CGRectIntersectsRect(capsuleRect, dynamicIslandRect);
    
    if (overlap) {
        LOG_POSITION(@"Capsule overlaps with Dynamic Island - Capsule: (%.1f, %.1f, %.1f, %.1f), Island: (%.1f, %.1f, %.1f, %.1f)",
                     capsuleRect.origin.x, capsuleRect.origin.y, capsuleRect.size.width, capsuleRect.size.height,
                     dynamicIslandRect.origin.x, dynamicIslandRect.origin.y, dynamicIslandRect.size.width, dynamicIslandRect.size.height);
    }
    
    return overlap;
}

- (CGPoint)adjustPositionToAvoidDynamicIsland:(UIWindow *)window {
    CGRect dynamicIslandRect = [self getDynamicIslandRect:window];
    
    // If no dynamic island area, return current position
    if (dynamicIslandRect.size.height <= 0) {
        return self.frame.origin;
    }
    
    CGRect capsuleRect = self.frame;
    CGRect screenBounds = window.bounds;
    
    // Calculate distances to move capsule out of dynamic island area
    CGFloat moveLeft = dynamicIslandRect.origin.x - (capsuleRect.origin.x + capsuleRect.size.width);
    CGFloat moveRight = (dynamicIslandRect.origin.x + dynamicIslandRect.size.width) - capsuleRect.origin.x;
    CGFloat moveDown = (dynamicIslandRect.origin.y + dynamicIslandRect.size.height) - capsuleRect.origin.y;
    
    // Choose the movement that requires the least distance
    CGFloat newX = capsuleRect.origin.x;
    CGFloat newY = capsuleRect.origin.y;
    
    // Consider horizontal movement first (left or right)
    if (fabs(moveLeft) <= fabs(moveRight)) {
        // Move left
        newX = capsuleRect.origin.x + moveLeft;
        LOG_POSITION(@"Avoiding Dynamic Island by moving left by %.1f", fabs(moveLeft));
    } else {
        // Move right
        newX = capsuleRect.origin.x + moveRight;
        LOG_POSITION(@"Avoiding Dynamic Island by moving right by %.1f", moveRight);
    }
    
    // If horizontal movement would put capsule out of screen bounds, move down instead
    if (newX < 0 || newX + capsuleRect.size.width > screenBounds.size.width) {
        newX = capsuleRect.origin.x; // Keep original X
        newY = capsuleRect.origin.y + moveDown;
        LOG_POSITION(@"Horizontal movement out of bounds, moving down by %.1f instead", moveDown);
    }
    
    // Ensure the new position is within screen bounds
    newX = MAX(0, MIN(screenBounds.size.width - capsuleRect.size.width, newX));
    newY = MAX(0, MIN(screenBounds.size.height - capsuleRect.size.height, newY));
    
    LOG_POSITION(@"Adjusted position to avoid Dynamic Island: (%.1f, %.1f) -> (%.1f, %.1f)",
                 capsuleRect.origin.x, capsuleRect.origin.y, newX, newY);
    
    return CGPointMake(newX, newY);
}

@end 

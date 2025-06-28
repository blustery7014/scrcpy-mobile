#import "ScrcpyMenuView.h"
#import "ScrcpyMenuMaskView.h"
#import "ScrcpyConstants.h"
#import <SDL2/SDL_system.h>
#import <SDL2/SDL_syswm.h>
#import <SDL2/SDL_mouse.h>
#import "ScrcpyADBClient.h"
#import "ScrcpyVNCClient.h"

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


@interface ScrcpyMenuView () <ScrcpyMenuMaskViewDelegate, ScrcpyMenuViewDelegate>

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
@property (nonatomic, assign) ScrcpyDeviceType currentDeviceType;
@property (nonatomic, assign) BOOL isUpdatingButtonLayout;

// VNC 缩放相关
@property (nonatomic, assign) CGFloat currentZoomScale;
@property (nonatomic, assign) CGFloat gestureStartZoomScale;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchGesture;
@property (nonatomic, assign) CGFloat gestureStartCenterX;
@property (nonatomic, assign) CGFloat gestureStartCenterY;

// VNC 拖拽相关
@property (nonatomic, strong) UIPanGestureRecognizer *dragGesture;
@property (nonatomic, assign) CGPoint dragStartLocation;
@property (nonatomic, assign) CGPoint currentDragOffset;
@property (nonatomic, assign) CGPoint totalDragOffset;

// VNC 触摸事件追踪相关
@property (nonatomic, assign) NSTimeInterval touchStartTime;
@property (nonatomic, assign) CGPoint touchStartLocation;
@property (nonatomic, assign) BOOL isDragging;

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
        _currentDeviceType = ScrcpyDeviceTypeADB; // 默认为ADB设备
        _currentZoomScale = 1.0; // 初始化缩放比例为1.0
        _gestureStartZoomScale = 1.0; // 初始化手势开始时的缩放比例
        _dragStartLocation = CGPointZero; // 初始化拖拽开始位置
        _currentDragOffset = CGPointZero; // 初始化当前拖拽偏移量
        _totalDragOffset = CGPointZero; // 初始化总拖拽偏移量
        
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
    
    // 清理Pinch手势
    [self removePinchGesture];
    
    // 清理拖拽手势
    [self removeDragGesture];
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
    CGFloat savedRatioX = [defaults floatForKey:kUserDefaultsPositionRatioX];
    CGFloat savedRatioY = [defaults floatForKey:kUserDefaultsPositionRatioY];
    
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
    [defaults setFloat:ratio.x forKey:kUserDefaultsPositionRatioX];
    [defaults setFloat:ratio.y forKey:kUserDefaultsPositionRatioY];
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
    self.capsuleHandleIcon.image = [UIImage systemImageNamed:kIconCapsuleHandle];
    self.capsuleHandleIcon.tintColor = [UIColor colorWithWhite:1.0 alpha:1.0];
    self.capsuleHandleIcon.contentMode = UIViewContentModeScaleAspectFit;
    
    // Add subviews to capsule view
    [self.capsuleView addSubview:self.capsuleBackgroundView];
    [self.capsuleView addSubview:self.capsuleHandleIcon];
    [self addSubview:self.capsuleView];
    
    // Menu view (expanded state)
    UIWindow *window = [self activeWindow];
    self.activeWindow = window;
    
    // 使用默认宽度初始化菜单视图，稍后会通过updateButtonLayout自动调整
    CGFloat initialMenuWidth = 6 * kButtonWidth + 5 * kButtonSpacing + kMenuHorizontalPadding * 2; // 按最大按钮数量计算
    
    // 确保不超过屏幕宽度
    CGFloat maxAvailableWidth = window.bounds.size.width - (kMenuHorizontalPadding * 2);
    initialMenuWidth = MIN(initialMenuWidth, maxAvailableWidth);
    
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, initialMenuWidth, kMenuHeight)];
    self.menuView.layer.cornerRadius = kMenuCornerRadius;
    self.menuView.clipsToBounds = YES;
    self.menuView.alpha = 0;
    self.menuView.hidden = YES;
    
    // Gradient layer for menu
    CAGradientLayer *menuGradientLayer = [CAGradientLayer layer];
    menuGradientLayer.frame = CGRectMake(0, 0, initialMenuWidth, kMenuHeight);
    menuGradientLayer.colors = @[
        (id)[UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:0.85].CGColor,
        (id)[UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.9].CGColor
    ];
    menuGradientLayer.startPoint = CGPointMake(0, 0);
    menuGradientLayer.endPoint = CGPointMake(1, 0);
    [self.menuView.layer insertSublayer:menuGradientLayer atIndex:0];
    self.menuView.layer.masksToBounds = YES;
    
    // Create buttons with temporary positions (will be updated by updateButtonLayout)
    CGRect tempButtonFrame = CGRectMake(0, 0, kButtonWidth, kButtonHeight);
    
    // Back button
    self.backButton = [self createButtonWithIcon:kIconBackButton position:tempButtonFrame];
    [self.menuView addSubview:self.backButton];
    
    // Home button
    self.homeButton = [self createButtonWithIcon:kIconHomeButton position:tempButtonFrame];
    [self.menuView addSubview:self.homeButton];
    
    // Switch button
    self.switchButton = [self createButtonWithIcon:kIconSwitchButton position:tempButtonFrame];
    [self.menuView addSubview:self.switchButton];
    
    // Keyboard button
    self.keyboardButton = [self createButtonWithIcon:kIconKeyboardButton position:tempButtonFrame];
    [self.menuView addSubview:self.keyboardButton];
    
    // Actions button
    self.actionsButton = [self createButtonWithIcon:kIconActionsButton position:tempButtonFrame];
    [self.menuView addSubview:self.actionsButton];
    
    // Disconnect button
    self.disconnectButton = [self createButtonWithIcon:kIconDisconnectButton position:tempButtonFrame];
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
        CGPoint location = [gesture locationInView:self.window];
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
        // 在菜单位置设置后，重新应用按钮布局
        [self updateButtonLayout];
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
    
    // 计算当前可见按钮数量
    NSInteger visibleButtonCount = [self visibleButtonCount];
    
    // 根据可见按钮数量计算理想菜单宽度
    CGFloat totalButtonsWidth = visibleButtonCount * kButtonWidth + (visibleButtonCount - 1) * kButtonSpacing;
    CGFloat menuWidth = totalButtonsWidth + kMenuHorizontalPadding * 2;
    
    // 限制菜单最大宽度，并考虑屏幕可用宽度
    CGFloat maxMenuWidth = 400.0f;
    CGFloat availableWidth = screenBounds.size.width - (kMenuHorizontalPadding * 2);
    menuWidth = MIN(MIN(maxMenuWidth, availableWidth), menuWidth);
    
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
    
    // 不再调用旧的 repositionMenuButtons，由 updateButtonLayout 处理
    LOG_POSITION(@"🔧 updateMenuPosition completed, menu frame: (%.2f, %.2f, %.2f, %.2f)", 
                 self.menuView.frame.origin.x, self.menuView.frame.origin.y, 
                 self.menuView.frame.size.width, self.menuView.frame.size.height);
    
    // 确保按钮布局在菜单位置设置后得到正确应用
    // 但只在不是从 updateButtonLayout 调用时才执行，避免递归
    if (!self.isUpdatingButtonLayout) {
        [self updateButtonLayout];
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
    
    if ([identifier isEqualToString:kIconBackButton]) {
        [self backButtonTapped:sender];
    } else if ([identifier isEqualToString:kIconHomeButton]) {
        [self homeButtonTapped:sender];
    } else if ([identifier isEqualToString:kIconSwitchButton]) {
        [self switchButtonTapped:sender];
    } else if ([identifier isEqualToString:kIconKeyboardButton]) {
        [self keyboardButtonTapped:sender];
    } else if ([identifier isEqualToString:kIconActionsButton]) {
        [self actionsButtonTapped:sender];
    } else if ([identifier isEqualToString:kIconDisconnectButton]) {
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
    
    // 只有在VNC模式下才拦截其他区域的触摸事件
    if (self.currentDeviceType == ScrcpyDeviceTypeVNC) {
        return self;
    }
    
    // 非VNC模式下，不拦截其他区域的触摸事件
    return nil;
}

// 重写pointInside方法，确定是否应该接收触摸事件
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // 检查是否在胶囊视图内（始终需要处理）
    if (CGRectContainsPoint(self.capsuleView.frame, point)) {
        return YES;
    }
    
    // 如果菜单展开，检查是否在菜单视图内（始终需要处理）
    if (self.isExpanded && !self.menuView.hidden && self.menuView.superview) {
        CGPoint menuPoint = [self convertPoint:point toView:self.menuView];
        if ([self.menuView pointInside:menuPoint withEvent:event]) {
            return YES;
        }
    }
    
    // 只有在VNC模式下才拦截其他区域的触摸事件
    if (self.currentDeviceType == ScrcpyDeviceTypeVNC) {
        return YES;
    }
    
    return NO;
}

#pragma mark - Touch Event Handling

// 实现这些方法以防止事件向下传递
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.window];
    
    if ((self.isExpanded && CGRectContainsPoint(self.menuView.frame, point)) || 
        CGRectContainsPoint(self.capsuleView.frame, point)) {
        // 菜单区域，不向下传递
    } else if (self.currentDeviceType == ScrcpyDeviceTypeVNC) {
        // 只在VNC模式下处理VNC鼠标事件
        [self forwardTouchAsMouseMoveToVNC:point];
        [super touchesBegan:touches withEvent:event];
    } else {
        // 非VNC模式，传递给父类处理
        [super touchesBegan:touches withEvent:event];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.window];
    
    if ((self.isExpanded && CGRectContainsPoint(self.menuView.frame, point)) || 
        CGRectContainsPoint(self.capsuleView.frame, point)) {
        // 菜单区域，不向下传递
    } else if (self.currentDeviceType == ScrcpyDeviceTypeVNC) {
        // 只在VNC模式下处理VNC鼠标拖拽事件
        [self forwardTouchAsMouseDragToVNC:point];
        [super touchesMoved:touches withEvent:event];
    } else {
        // 非VNC模式，传递给父类处理
        [super touchesMoved:touches withEvent:event];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.window];
    
    if ((self.isExpanded && CGRectContainsPoint(self.menuView.frame, point)) || 
        CGRectContainsPoint(self.capsuleView.frame, point)) {
        // 菜单区域，不向下传递
    } else if (self.currentDeviceType == ScrcpyDeviceTypeVNC) {
        // 只在VNC模式下处理VNC鼠标事件结束
        [self forwardTouchEndAsMouseEventToVNC:point withTouch:touch];
        [super touchesEnded:touches withEvent:event];
    } else {
        // 非VNC模式，传递给父类处理
        [super touchesEnded:touches withEvent:event];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.window];
    
    if ((self.isExpanded && CGRectContainsPoint(self.menuView.frame, point)) || 
        CGRectContainsPoint(self.capsuleView.frame, point)) {
        // 菜单区域，不向下传递
    } else if (self.currentDeviceType == ScrcpyDeviceTypeVNC) {
        // 只在VNC模式下处理VNC触摸取消事件
        [self forwardTouchCancelToVNC:point];
        [super touchesCancelled:touches withEvent:event];
    } else {
        // 非VNC模式，传递给父类处理
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

#pragma mark - Device Type Configuration

// Helper method to count visible buttons
- (NSInteger)visibleButtonCount {
    NSInteger count = 0;
    if (!self.backButton.hidden) count++;
    if (!self.homeButton.hidden) count++;
    if (!self.switchButton.hidden) count++;
    if (!self.keyboardButton.hidden) count++;
    if (!self.actionsButton.hidden) count++;
    if (!self.disconnectButton.hidden) count++;
    return count;
}

+ (ScrcpyDeviceType)deviceTypeFromString:(NSString *)deviceTypeString {
    if ([deviceTypeString.lowercaseString isEqualToString:kDeviceTypeVNC]) {
        return ScrcpyDeviceTypeVNC;
    } else if ([deviceTypeString.lowercaseString isEqualToString:kDeviceTypeADB]) {
        return ScrcpyDeviceTypeADB;
    } else {
        // 默认为ADB类型
        return ScrcpyDeviceTypeADB;
    }
}

- (void)configureForDeviceType:(ScrcpyDeviceType)deviceType {
    self.currentDeviceType = deviceType;
    
    // 根据设备类型配置按钮可见性
    if (deviceType == ScrcpyDeviceTypeADB) {
        // ADB设备支持所有按钮
        self.backButton.hidden = NO;
        self.homeButton.hidden = NO;
        self.switchButton.hidden = NO;
        self.keyboardButton.hidden = NO;
        self.actionsButton.hidden = NO;
        self.disconnectButton.hidden = NO;
        
        // 移除的Pinch手势（如果存在）
        [self removePinchGesture];
        
        // 移除的拖拽手势（如果存在）
        [self removeDragGesture];
        
        LOG_POSITION(@"Configured menu for ADB device - all buttons visible");
    } else if (deviceType == ScrcpyDeviceTypeVNC) {
        // VNC设备只支持部分按钮
        self.backButton.hidden = YES;
        self.homeButton.hidden = YES;
        self.switchButton.hidden = YES;
        self.keyboardButton.hidden = NO;
        self.actionsButton.hidden = NO;
        self.disconnectButton.hidden = NO;
        
        // 为VNC设备添加Pinch缩放手势（延迟添加以确保SDL窗口初始化完成）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self addPinchGesture];
            [self addDragGesture];
        });
        
        LOG_POSITION(@"Configured menu for VNC device - limited buttons visible and pinch gesture enabled");
    }
    
    // 重新布局按钮
    [self updateButtonLayout];
}

- (NSArray<UIButton *> *)getVisibleButtons {
    NSMutableArray *visibleButtons = [NSMutableArray array];
    
    if (!self.backButton.hidden) [visibleButtons addObject:self.backButton];
    if (!self.homeButton.hidden) [visibleButtons addObject:self.homeButton];
    if (!self.switchButton.hidden) [visibleButtons addObject:self.switchButton];
    if (!self.keyboardButton.hidden) [visibleButtons addObject:self.keyboardButton];
    if (!self.actionsButton.hidden) [visibleButtons addObject:self.actionsButton];
    if (!self.disconnectButton.hidden) [visibleButtons addObject:self.disconnectButton];
    
    return [visibleButtons copy];
}

- (void)updateButtonLayout {
    if (!self.menuView) return;
    
    // 防止递归调用
    if (self.isUpdatingButtonLayout) {
        LOG_POSITION(@"🔧 updateButtonLayout skipped - already updating");
        return;
    }
    self.isUpdatingButtonLayout = YES;
    
    // 获取可见的按钮
    NSArray<UIButton *> *visibleButtons = [self getVisibleButtons];
    
    if (visibleButtons.count == 0) {
        LOG_POSITION(@"No visible buttons to layout");
        return;
    }
    
    // 详细调试信息
    LOG_POSITION(@"🔧 Starting updateButtonLayout - Device type: %ld", (long)self.currentDeviceType);
    LOG_POSITION(@"🔧 Visible buttons count: %ld", (long)visibleButtons.count);
    
    for (NSInteger i = 0; i < visibleButtons.count; i++) {
        UIButton *button = visibleButtons[i];
        NSString *buttonType = kButtonTypeUnknown;
        if (button == self.backButton) buttonType = kButtonTypeBack;
        else if (button == self.homeButton) buttonType = kButtonTypeHome;
        else if (button == self.switchButton) buttonType = kButtonTypeSwitch;
        else if (button == self.keyboardButton) buttonType = kButtonTypeKeyboard;
        else if (button == self.actionsButton) buttonType = kButtonTypeActions;
        else if (button == self.disconnectButton) buttonType = kButtonTypeDisconnect;
        
        LOG_POSITION(@"🔧 Button %ld: %@ (current frame: %.2f, %.2f, %.2f, %.2f)", 
                     (long)i, buttonType, button.frame.origin.x, button.frame.origin.y, 
                     button.frame.size.width, button.frame.size.height);
    }
    
    // 计算自适应布局参数
    CGFloat buttonWidth = kButtonWidth;
    CGFloat buttonHeight = kButtonHeight;
    CGFloat spacing = kButtonSpacing;
    
    LOG_POSITION(@"🔧 Constants - buttonWidth: %.1f, buttonHeight: %.1f, spacing: %.1f, padding: %.1f", 
                 buttonWidth, buttonHeight, spacing, kMenuHorizontalPadding);
    
    // 计算所有按钮占用的总宽度
    CGFloat totalButtonsWidth = visibleButtons.count * buttonWidth + (visibleButtons.count - 1) * spacing;
    
    // 计算理想的菜单宽度（包含左右边距）
    CGFloat idealMenuWidth = totalButtonsWidth + kMenuHorizontalPadding * 2;
    
    // 获取当前菜单尺寸
    CGRect currentFrame = self.menuView.frame;
    CGFloat menuHeight = currentFrame.size.height;
    
    LOG_POSITION(@"🔧 Menu calculations - totalButtonsWidth: %.1f, idealMenuWidth: %.1f, menuHeight: %.1f", 
                 totalButtonsWidth, idealMenuWidth, menuHeight);
    
    // 更新菜单视图的宽度
    self.menuView.frame = CGRectMake(currentFrame.origin.x, currentFrame.origin.y, idealMenuWidth, menuHeight);
    
    // 计算按钮容器在菜单中的起始X位置（应该从padding开始）
    CGFloat containerStartX = kMenuHorizontalPadding;
    CGFloat containerY = (menuHeight - buttonHeight) / 2.0; // 垂直居中
    
    LOG_POSITION(@"🔧 Container position - startX: %.1f, startY: %.1f", containerStartX, containerY);
    
    // 布局可见的按钮
    for (NSInteger i = 0; i < visibleButtons.count; i++) {
        UIButton *button = visibleButtons[i];
        CGFloat xPosition = containerStartX + i * (buttonWidth + spacing);
        
        // 移除可能存在的约束
        button.translatesAutoresizingMaskIntoConstraints = YES;
        
        // 强制设置按钮frame
        button.frame = CGRectMake(xPosition, containerY, buttonWidth, buttonHeight);
        
        // 确保按钮布局立即生效
        [button setNeedsLayout];
        [button layoutIfNeeded];
        
        // 验证设置是否生效
        CGRect actualFrame = button.frame;
        
        LOG_POSITION(@"🔧 Button %ld - calculated: (%.2f, %.2f), actual: (%.2f, %.2f, %.2f, %.2f)", 
                     (long)i, xPosition, containerY, 
                     actualFrame.origin.x, actualFrame.origin.y, actualFrame.size.width, actualFrame.size.height);
        
        // 再次验证（在下一个runloop中）
        dispatch_async(dispatch_get_main_queue(), ^{
            CGRect finalFrame = button.frame;
            if (finalFrame.origin.x != xPosition || finalFrame.origin.y != containerY) {
                LOG_POSITION(@"⚠️ Button %ld frame changed after layout! Expected: (%.2f, %.2f), Got: (%.2f, %.2f)", 
                             (long)i, xPosition, containerY, finalFrame.origin.x, finalFrame.origin.y);
            }
        });
    }
    
    // 更新gradient layer以匹配新的菜单尺寸
    for (CALayer *layer in self.menuView.layer.sublayers) {
        if ([layer isKindOfClass:[CAGradientLayer class]]) {
            layer.frame = CGRectMake(0, 0, idealMenuWidth, menuHeight);
            break;
        }
    }
    
    // 强制更新菜单视图布局
    [self.menuView setNeedsLayout];
    [self.menuView layoutIfNeeded];
    
    LOG_POSITION(@"Updated button layout: %ld visible buttons, menu width: %.1f, total buttons width: %.1f", 
                 (long)visibleButtons.count, idealMenuWidth, totalButtonsWidth);
    
    // 验证布局是否正确
    [self validateButtonLayout:visibleButtons];
    
    // 最后一次验证按钮位置
    LOG_POSITION(@"🔧 Final verification:");
    for (NSInteger i = 0; i < visibleButtons.count; i++) {
        UIButton *button = visibleButtons[i];
        CGFloat expectedX = containerStartX + i * (buttonWidth + spacing);
        CGRect currentFrame = button.frame;
        
        if (fabs(currentFrame.origin.x - expectedX) > 0.1 || fabs(currentFrame.origin.y - containerY) > 0.1) {
            LOG_POSITION(@"❌ Button %ld position mismatch! Expected: (%.2f, %.2f), Got: (%.2f, %.2f)", 
                         (long)i, expectedX, containerY, currentFrame.origin.x, currentFrame.origin.y);
        } else {
                         LOG_POSITION(@"✅ Button %ld position correct: (%.2f, %.2f)", 
                          (long)i, currentFrame.origin.x, currentFrame.origin.y);
         }
     }
     
     // 重置更新标志
     self.isUpdatingButtonLayout = NO;
 }

- (void)validateButtonLayout:(NSArray<UIButton *> *)visibleButtons {
    if (visibleButtons.count == 0) return;
    
    // 检查按钮是否在菜单范围内
    CGFloat menuWidth = self.menuView.frame.size.width;
    UIButton *lastButton = visibleButtons.lastObject;
    CGFloat lastButtonRightEdge = lastButton.frame.origin.x + lastButton.frame.size.width;
    
    if (lastButtonRightEdge > menuWidth - kMenuHorizontalPadding) {
        LOG_POSITION(@"⚠️ Button layout validation failed: last button exceeds menu bounds");
        LOG_POSITION(@"Last button right edge: %.1f, menu width: %.1f, padding: %.1f", 
                     lastButtonRightEdge, menuWidth, kMenuHorizontalPadding);
    } else {
        LOG_POSITION(@"✅ Button layout validation passed: all buttons within bounds");
    }
    
    // 检查按钮是否垂直居中
    CGFloat menuHeight = self.menuView.frame.size.height;
    CGFloat expectedY = (menuHeight - kButtonHeight) / 2.0;
    UIButton *firstButton = visibleButtons.firstObject;
    
    if (fabs(firstButton.frame.origin.y - expectedY) > 1.0) {
        LOG_POSITION(@"⚠️ Button vertical alignment validation failed: expected Y: %.1f, actual Y: %.1f", 
                     expectedY, firstButton.frame.origin.y);
    } else {
        LOG_POSITION(@"✅ Button vertical alignment validation passed");
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

#pragma mark - VNC Pinch Gesture Management

- (void)addPinchGesture {
    // 移除已存在的手势（如果有）
    [self removePinchGesture];
    
    // 获取SDL窗口
    UIWindow *sdlWindow = [self getSDLWindow];
    if (!sdlWindow) {
        LOG_POSITION(@"⚠️ Cannot add pinch gesture - SDL window not found");
        return;
    }
    
    // 创建Pinch手势识别器
    self.pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleVNCPinch:)];
    self.pinchGesture.delegate = self;
    
    // 添加到SDL窗口的根视图控制器的视图上
    UIViewController *rootVC = sdlWindow.rootViewController;
    if (rootVC && rootVC.view) {
        [rootVC.view addGestureRecognizer:self.pinchGesture];
        LOG_POSITION(@"✅ Added pinch gesture to SDL window view");
    } else {
        LOG_POSITION(@"⚠️ Cannot add pinch gesture - SDL window root view controller not found");
    }
}

- (void)removePinchGesture {
    if (self.pinchGesture) {
        [self.pinchGesture.view removeGestureRecognizer:self.pinchGesture];
        self.pinchGesture = nil;
        LOG_POSITION(@"🗑️ Removed VNC pinch gesture");
    }
}

- (UIWindow *)getSDLWindow {
    // 尝试通过SDL获取窗口
    SDL_Window *sdlWindow = SDL_GetMouseFocus();
    if (sdlWindow) {
        SDL_SysWMinfo info;
        SDL_VERSION(&info.version);
        if (SDL_GetWindowWMInfo(sdlWindow, &info)) {
            UIWindow *uiWindow = info.info.uikit.window;
            if (uiWindow) {
                return uiWindow;
            }
        }
    }
    
    // Fallback: 查找当前活跃的场景中的键窗口
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
        }
    }
    
    return nil;
}

#pragma mark - Pinch Gesture Handler

#define kMinZoomScale   1.0
#define kMaxZoomScale   4.0

- (void)handleVNCPinch:(UIPinchGestureRecognizer *)gesture {
    if (self.currentDeviceType != ScrcpyDeviceTypeVNC) {
        return;
    }
    
    CGFloat gestureScale = gesture.scale;
    
    // 计算触摸中心点（归一化坐标 0.0-1.0）
    CGPoint pinchCenter = [gesture locationInView:gesture.view];
    CGSize viewSize = gesture.view.bounds.size;
    CGFloat normalizedX = pinchCenter.x / viewSize.width;
    CGFloat normalizedY = pinchCenter.y / viewSize.height;
    
    // 确保坐标在有效范围内
    normalizedX = MAX(0.0, MIN(1.0, normalizedX));
    normalizedY = MAX(0.0, MIN(1.0, normalizedY));
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            // 记录手势开始时的缩放比例
            self.currentZoomScale = MAX(self.currentZoomScale, kMinZoomScale); // 当前的缩放比例不低于 1.0
            self.currentZoomScale = MIN(self.currentZoomScale, kMaxZoomScale); // 当前的缩放比例不低于 3.0
            self.gestureStartZoomScale = self.currentZoomScale;
            self.gestureStartCenterX = pinchCenter.x;
            self.gestureStartCenterY = pinchCenter.y;
            
            // 计算归一化的中心点坐标
            CGFloat normalizedStartX = self.gestureStartCenterX / viewSize.width;
            CGFloat normalizedStartY = self.gestureStartCenterY / viewSize.height;
            
            // 确保坐标在有效范围内
            normalizedStartX = MAX(0.0, MIN(1.0, normalizedStartX));
            normalizedStartY = MAX(0.0, MIN(1.0, normalizedStartY));
            
            LOG_POSITION(@"🔍 VNC Pinch gesture began - current zoom: %.3f, gesture scale: %.3f, center: (%.3f, %.3f)",
                         self.currentZoomScale, gestureScale, normalizedStartX, normalizedStartY);
            
            // 通知代理缩放手势开始（使用固定的中心点信息）
            if ([self.delegate respondsToSelector:@selector(didPinchWithScale:centerX:centerY:)]) {
                [self.delegate didPinchWithScale:self.currentZoomScale centerX:normalizedStartX centerY:normalizedStartY];
            } else if ([self.delegate respondsToSelector:@selector(didPinchWithScale:)]) {
                // 兼容性处理
                [self.delegate didPinchWithScale:self.currentZoomScale];
            }
            break;
        }
            
        case UIGestureRecognizerStateChanged: {
            // 直接使用手势缩放比例，去掉阻尼
            CGFloat newScale = self.gestureStartZoomScale * gestureScale;
            
            // 限制缩放范围
            newScale = MAX(kMinZoomScale, MIN(kMaxZoomScale, newScale));
            
            // 使用手势开始时记录的中心点，避免后续跳动
            CGFloat normalizedStartX = self.gestureStartCenterX / viewSize.width;
            CGFloat normalizedStartY = self.gestureStartCenterY / viewSize.height;
            
            // 确保坐标在有效范围内
            normalizedStartX = MAX(0.0, MIN(1.0, normalizedStartX));
            normalizedStartY = MAX(0.0, MIN(1.0, normalizedStartY));
            
            LOG_POSITION(@"🔍 VNC Pinch gesture changed - gesture scale: %.3f, start zoom: %.3f, new scale: %.3f, fixed center: (%.3f, %.3f)", 
                         gestureScale, self.gestureStartZoomScale, newScale, normalizedStartX, normalizedStartY);
            
            // 通知代理进行缩放（使用固定的中心点信息）
            if ([self.delegate respondsToSelector:@selector(didPinchWithScale:centerX:centerY:)]) {
                [self.delegate didPinchWithScale:newScale centerX:normalizedStartX centerY:normalizedStartY];
            } else if ([self.delegate respondsToSelector:@selector(didPinchWithScale:)]) {
                // 兼容性处理
                [self.delegate didPinchWithScale:newScale];
            }
            break;
        }
            
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            // 直接使用手势缩放比例
            CGFloat finalScale = self.gestureStartZoomScale * gestureScale;
            finalScale = MAX(kMinZoomScale, MIN(kMaxZoomScale, finalScale));
            
            // 更新当前缩放比例
            self.currentZoomScale = finalScale;
            
            // 使用手势开始时记录的中心点，避免后续跳动
            CGFloat normalizedStartX = self.gestureStartCenterX / viewSize.width;
            CGFloat normalizedStartY = self.gestureStartCenterY / viewSize.height;
            
            // 确保坐标在有效范围内
            normalizedStartX = MAX(0.0, MIN(1.0, normalizedStartX));
            normalizedStartY = MAX(0.0, MIN(1.0, normalizedStartY));
            
            LOG_POSITION(@"🔍 VNC Pinch gesture ended - gesture scale: %.3f, final scale: %.3f, fixed center: (%.3f, %.3f)", 
                         gestureScale, finalScale, normalizedStartX, normalizedStartY);
            
            // 通知代理缩放结束（使用固定的中心点信息）
            if ([self.delegate respondsToSelector:@selector(didPinchEndWithFinalScale:centerX:centerY:)]) {
                [self.delegate didPinchEndWithFinalScale:finalScale centerX:normalizedStartX centerY:normalizedStartY];
            } else if ([self.delegate respondsToSelector:@selector(didPinchEndWithFinalScale:)]) {
                // 兼容性处理
                [self.delegate didPinchEndWithFinalScale:finalScale];
            }
            break;
        }
            
        default:
            break;
    }
}

#pragma mark - Drag Gesture Management

- (void)addDragGesture {
    // 移除已存在的手势（如果有）
    [self removeDragGesture];
    
    // 获取SDL窗口
    UIWindow *sdlWindow = [self getSDLWindow];
    if (!sdlWindow) {
        LOG_POSITION(@"⚠️ Cannot add drag gesture - SDL window not found");
        return;
    }
    
    // 创建拖拽手势识别器
    self.dragGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    self.dragGesture.delegate = self;
    self.dragGesture.minimumNumberOfTouches = 2;
    self.dragGesture.maximumNumberOfTouches = 3;
    
    // 添加到SDL窗口的根视图控制器的视图上
    UIViewController *rootVC = sdlWindow.rootViewController;
    if (rootVC && rootVC.view) {
        [rootVC.view addGestureRecognizer:self.dragGesture];
        LOG_POSITION(@"✅ Added drag gesture to SDL window view");
    } else {
        LOG_POSITION(@"⚠️ Cannot add drag gesture - SDL window root view controller not found");
    }
}

- (void)removeDragGesture {
    if (self.dragGesture) {
        [self.dragGesture.view removeGestureRecognizer:self.dragGesture];
        self.dragGesture = nil;
        LOG_POSITION(@"🗑️ Removed VNC drag gesture");
    }
}

- (void)resetDragOffset {
    self.currentDragOffset = CGPointZero;
    self.totalDragOffset = CGPointZero;
    self.dragStartLocation = CGPointZero;
    LOG_POSITION(@"🔄 Reset drag offset to zero");
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 允许Pinch手势与其他手势同时进行，但不与我们自己的手势冲突
    if (gestureRecognizer == self.pinchGesture) {
        return YES;
    }
    // 允许拖拽手势与其他手势同时进行
    if (gestureRecognizer == self.dragGesture) {
        return YES;
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // 确保Pinch手势只在VNC设备时响应
    if (gestureRecognizer == self.pinchGesture) {
        return self.currentDeviceType == ScrcpyDeviceTypeVNC;
    }
    // 确保拖拽手势只在VNC设备时响应
    if (gestureRecognizer == self.dragGesture) {
        return self.currentDeviceType == ScrcpyDeviceTypeVNC;
    }
    return YES;
}

#pragma mark - Drag Gesture Handler

- (void)handleDrag:(UIPanGestureRecognizer *)gesture {
    if (self.currentDeviceType != ScrcpyDeviceTypeVNC) {
        return;
    }
    
    // 获取拖拽位置和视图尺寸
    CGPoint location = [gesture locationInView:gesture.view];
    CGSize viewSize = gesture.view.bounds.size;
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            // 记录拖拽开始位置
            self.dragStartLocation = location;
            self.currentDragOffset = CGPointZero;
            
            LOG_POSITION(@"🎯 VNC Drag gesture began - start location: (%.1f, %.1f), viewSize: (%.1f, %.1f)", 
                         location.x, location.y, viewSize.width, viewSize.height);
            
            // 通知代理拖拽开始
            if ([self.delegate respondsToSelector:@selector(didDragWithState:location:viewSize:offset:)]) {
                [self.delegate didDragWithState:kDragStateBegan location:location viewSize:viewSize offset:self.currentDragOffset];
            } else if ([self.delegate respondsToSelector:@selector(didDragWithState:location:viewSize:)]) {
                // 兼容性处理
                [self.delegate didDragWithState:kDragStateBegan location:location viewSize:viewSize];
            }
            
            // 调用自己的代理方法实现
            [self didDragWithState:kDragStateBegan location:location viewSize:viewSize offset:self.currentDragOffset];
            break;
        }
            
        case UIGestureRecognizerStateChanged: {
            // 计算当前拖拽偏移量（相对于开始位置）
            CGPoint translation = [gesture translationInView:gesture.view];
            self.currentDragOffset = translation;
            
            // 计算归一化的偏移量（相对于视图尺寸的比例）
            CGFloat normalizedOffsetX = translation.x / viewSize.width;
            CGFloat normalizedOffsetY = translation.y / viewSize.height;
            
            // 确保归一化偏移量在合理范围内
            normalizedOffsetX = MAX(-1.0, MIN(1.0, normalizedOffsetX));
            normalizedOffsetY = MAX(-1.0, MIN(1.0, normalizedOffsetY));
            
            LOG_POSITION(@"🎯 VNC Drag gesture changed - location: (%.1f, %.1f), translation: (%.1f, %.1f), normalized offset: (%.3f, %.3f)", 
                         location.x, location.y, translation.x, translation.y, normalizedOffsetX, normalizedOffsetY);
            
            // 通知代理拖拽移动（包含偏移量信息）
            if ([self.delegate respondsToSelector:@selector(didDragWithState:location:viewSize:offset:)]) {
                [self.delegate didDragWithState:kDragStateChanged location:location viewSize:viewSize offset:self.currentDragOffset];
            } else if ([self.delegate respondsToSelector:@selector(didDragWithState:location:viewSize:)]) {
                // 兼容性处理
                [self.delegate didDragWithState:kDragStateChanged location:location viewSize:viewSize];
            }
            
            // 调用自己的代理方法实现
            [self didDragWithState:kDragStateChanged location:location viewSize:viewSize offset:self.currentDragOffset];
            
            // 通知代理渲染Rect控制（使用归一化偏移量）
            if ([self.delegate respondsToSelector:@selector(didDragWithNormalizedOffset:viewSize:)]) {
                CGPoint normalizedOffset = CGPointMake(normalizedOffsetX, normalizedOffsetY);
                [self.delegate didDragWithNormalizedOffset:normalizedOffset viewSize:viewSize];
            }
            
            // 调用自己的代理方法实现
            CGPoint normalizedOffset = CGPointMake(normalizedOffsetX, normalizedOffsetY);
            [self didDragWithNormalizedOffset:normalizedOffset viewSize:viewSize];
            break;
        }
            
        case UIGestureRecognizerStateEnded: {
            // 计算最终拖拽偏移量
            CGPoint translation = [gesture translationInView:gesture.view];
            self.currentDragOffset = translation;
            self.totalDragOffset = CGPointMake(self.totalDragOffset.x + translation.x, 
                                              self.totalDragOffset.y + translation.y);
            
            // 计算归一化的最终偏移量
            CGFloat normalizedOffsetX = translation.x / viewSize.width;
            CGFloat normalizedOffsetY = translation.y / viewSize.height;
            normalizedOffsetX = MAX(-1.0, MIN(1.0, normalizedOffsetX));
            normalizedOffsetY = MAX(-1.0, MIN(1.0, normalizedOffsetY));
            
            LOG_POSITION(@"🎯 VNC Drag gesture ended - location: (%.1f, %.1f), final translation: (%.1f, %.1f), normalized offset: (%.3f, %.3f)", 
                         location.x, location.y, translation.x, translation.y, normalizedOffsetX, normalizedOffsetY);
            
            // 通知代理拖拽结束（包含偏移量信息）
            if ([self.delegate respondsToSelector:@selector(didDragWithState:location:viewSize:offset:)]) {
                [self.delegate didDragWithState:kDragStateEnded location:location viewSize:viewSize offset:self.currentDragOffset];
            } else if ([self.delegate respondsToSelector:@selector(didDragWithState:location:viewSize:)]) {
                // 兼容性处理
                [self.delegate didDragWithState:kDragStateEnded location:location viewSize:viewSize];
            }
            
            // 调用自己的代理方法实现
            [self didDragWithState:kDragStateEnded location:location viewSize:viewSize offset:self.currentDragOffset];
            
            // 通知代理最终渲染Rect控制（使用归一化偏移量）
            if ([self.delegate respondsToSelector:@selector(didDragEndWithNormalizedOffset:viewSize:)]) {
                CGPoint normalizedOffset = CGPointMake(normalizedOffsetX, normalizedOffsetY);
                [self.delegate didDragEndWithNormalizedOffset:normalizedOffset viewSize:viewSize];
            }
            
            // 调用自己的代理方法实现
            CGPoint normalizedOffset = CGPointMake(normalizedOffsetX, normalizedOffsetY);
            [self didDragEndWithNormalizedOffset:normalizedOffset viewSize:viewSize];
            break;
        }
            
        case UIGestureRecognizerStateCancelled: {
            // 重置拖拽偏移量
            self.currentDragOffset = CGPointZero;
            
            LOG_POSITION(@"🎯 VNC Drag gesture cancelled - location: (%.1f, %.1f)", location.x, location.y);
            
            // 通知代理拖拽取消
            if ([self.delegate respondsToSelector:@selector(didDragWithState:location:viewSize:offset:)]) {
                [self.delegate didDragWithState:kDragStateCancelled location:location viewSize:viewSize offset:self.currentDragOffset];
            } else if ([self.delegate respondsToSelector:@selector(didDragWithState:location:viewSize:)]) {
                // 兼容性处理
                [self.delegate didDragWithState:kDragStateCancelled location:location viewSize:viewSize];
            }
            
            // 调用自己的代理方法实现
            [self didDragWithState:kDragStateCancelled location:location viewSize:viewSize offset:self.currentDragOffset];
            break;
        }
            
        default:
            break;
    }
}

#pragma mark - ScrcpyMenuViewDelegate Implementation

- (void)didDragWithState:(NSString *)state location:(CGPoint)location viewSize:(CGSize)viewSize {
    // 发送VNC拖拽通知
    NSDictionary *userInfo = @{
        kKeyState: state,
        kKeyLocation: [NSValue valueWithCGPoint:location],
        kKeyViewSize: [NSValue valueWithCGSize:viewSize]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCDrag object:nil userInfo:userInfo];
}

- (void)didDragWithState:(NSString *)state location:(CGPoint)location viewSize:(CGSize)viewSize offset:(CGPoint)offset {
    // 发送VNC拖拽通知（包含偏移量）
    NSDictionary *userInfo = @{
        kKeyState: state,
        kKeyLocation: [NSValue valueWithCGPoint:location],
        kKeyViewSize: [NSValue valueWithCGSize:viewSize],
        kKeyOffset: [NSValue valueWithCGPoint:offset]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCDrag object:nil userInfo:userInfo];
}

- (void)didDragWithNormalizedOffset:(CGPoint)normalizedOffset viewSize:(CGSize)viewSize {
    // 发送VNC拖拽偏移量通知
    NSDictionary *userInfo = @{
        kKeyNormalizedOffset: [NSValue valueWithCGPoint:normalizedOffset],
        kKeyViewSize: [NSValue valueWithCGSize:viewSize]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCDragOffset object:nil userInfo:userInfo];
}

- (void)didDragEndWithNormalizedOffset:(CGPoint)normalizedOffset viewSize:(CGSize)viewSize {
    // 发送VNC拖拽结束偏移量通知
    NSDictionary *userInfo = @{
        kKeyNormalizedOffset: [NSValue valueWithCGPoint:normalizedOffset],
        kKeyViewSize: [NSValue valueWithCGSize:viewSize]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCDragOffset object:nil userInfo:userInfo];
}

#pragma mark - VNC Touch Event Forwarding

// 获取VNC客户端实例
- (ScrcpyVNCClient *)getVNCClient {
    // 通过通知中心发送事件，或者通过单例获取VNC客户端
    // 这里使用通知方式，因为VNC客户端已经在监听这些通知
    return nil; // 我们使用通知，不需要直接引用
}


// 转发触摸开始为鼠标移动事件
- (void)forwardTouchAsMouseMoveToVNC:(CGPoint)location {
    // 记录触摸开始时间和位置
    self.touchStartTime = [[NSDate date] timeIntervalSince1970];
    self.touchStartLocation = location;
    self.isDragging = NO;
    
    NSLog(@"🎯 [ScrcpyMenuView] Touch began at (%.1f, %.1f), forwarding as mouse move", location.x, location.y);
    NSLog(@"🎯 [ScrcpyMenuView] Touch start time recorded: %.3f", self.touchStartTime);
    
    // 发送触摸移动通知到VNC客户端
    NSDictionary *userInfo = @{
        kKeyType: kMouseEventTypeMove,
        kKeyLocation: [NSValue valueWithCGPoint:location],
        kKeyViewSize: [NSValue valueWithCGSize:self.bounds.size]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCMouseEvent object:nil userInfo:userInfo];
}

// 转发触摸移动为鼠标拖拽事件
- (void)forwardTouchAsMouseDragToVNC:(CGPoint)location {
    // 计算移动距离
    CGFloat deltaX = location.x - self.touchStartLocation.x;
    CGFloat deltaY = location.y - self.touchStartLocation.y;
    CGFloat distance = sqrt(deltaX * deltaX + deltaY * deltaY);
    
    // 如果移动距离超过阈值，认为是拖拽
    const CGFloat dragThreshold = 5.0;
    if (distance > dragThreshold) {
        if (!self.isDragging) {
            // 开始拖拽
            self.isDragging = YES;
            NSLog(@"🎯 [ScrcpyMenuView] Drag started at (%.1f, %.1f)", self.touchStartLocation.x, self.touchStartLocation.y);
            
            NSDictionary *userInfo = @{
                kKeyType: kMouseEventTypeDragStart,
                kKeyLocation: [NSValue valueWithCGPoint:self.touchStartLocation],
                kKeyViewSize: [NSValue valueWithCGSize:self.bounds.size]
            };
            [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCMouseEvent object:nil userInfo:userInfo];
        }
        
        // 继续拖拽
        NSLog(@"🎯 [ScrcpyMenuView] Dragging to (%.1f, %.1f)", location.x, location.y);
        
        NSDictionary *userInfo = @{
            kKeyType: kMouseEventTypeDrag,
            kKeyLocation: [NSValue valueWithCGPoint:location],
            kKeyViewSize: [NSValue valueWithCGSize:self.bounds.size]
        };
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCMouseEvent object:nil userInfo:userInfo];
    } else {
        // 移动距离很小，继续作为鼠标移动处理
        [self forwardTouchAsMouseMoveToVNC:location];
    }
}

// 转发触摸结束为鼠标事件
- (void)forwardTouchEndAsMouseEventToVNC:(CGPoint)location withTouch:(UITouch *)touch {
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval touchDuration = currentTime - self.touchStartTime;
    
    // 计算移动距离
    CGFloat deltaX = location.x - self.touchStartLocation.x;
    CGFloat deltaY = location.y - self.touchStartLocation.y;
    CGFloat distance = sqrt(deltaX * deltaX + deltaY * deltaY);
    
    const CGFloat clickThreshold = 5.0;    // 移动距离阈值
    const NSTimeInterval clickTimeThreshold = 0.5; // 时间阈值
    
    if (self.isDragging) {
        // 结束拖拽，忽略点击事件判定
        NSLog(@"🎯 [ScrcpyMenuView] Drag ended at (%.1f, %.1f)", location.x, location.y);
        
        NSDictionary *userInfo = @{
            kKeyType: kMouseEventTypeDragEnd,
            kKeyLocation: [NSValue valueWithCGPoint:location],
            kKeyViewSize: [NSValue valueWithCGSize:self.bounds.size]
        };
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCMouseEvent object:nil userInfo:userInfo];
        
        self.isDragging = NO;
    } else if (distance <= clickThreshold && touchDuration <= clickTimeThreshold) {
        // 判断为点击事件
        BOOL isRightClick = (touch.tapCount == 2); // 双击作为右键
        
        NSLog(@"🎯 [ScrcpyMenuView] %@ click at (%.1f, %.1f), duration: %.3fs, distance: %.1f", 
              isRightClick ? kLogLabelRight : kLogLabelLeft, location.x, location.y, touchDuration, distance);
        
        NSDictionary *userInfo = @{
            kKeyType: kMouseEventTypeClick,
            kKeyLocation: [NSValue valueWithCGPoint:location],
            kKeyIsRightClick: @(isRightClick),
            kKeyViewSize: [NSValue valueWithCGSize:self.bounds.size]
        };
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCMouseEvent object:nil userInfo:userInfo];
    } else {
        NSLog(@"🎯 [ScrcpyMenuView] Touch ended without click or drag (duration: %.3fs, distance: %.1f)", touchDuration, distance);
    }
    
    // 重置状态
    self.isDragging = NO;
    self.touchStartTime = 0;
    self.touchStartLocation = CGPointZero;
}

// 转发触摸取消事件
- (void)forwardTouchCancelToVNC:(CGPoint)location {
    if (self.isDragging) {
        NSLog(@"🎯 [ScrcpyMenuView] Touch cancelled during drag at (%.1f, %.1f)", location.x, location.y);
        
        NSDictionary *userInfo = @{
            kKeyType: kMouseEventTypeDragEnd,
            kKeyLocation: [NSValue valueWithCGPoint:location],
            kKeyViewSize: [NSValue valueWithCGSize:self.bounds.size]
        };
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCMouseEvent object:nil userInfo:userInfo];
    }
    
    // 重置状态
    self.isDragging = NO;
    self.touchStartTime = 0;
    self.touchStartLocation = CGPointZero;
}

@end 

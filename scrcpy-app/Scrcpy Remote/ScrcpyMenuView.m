#import "ScrcpyMenuView.h"
#import "Scrcpy_Remote-Swift.h"
#import "ScrcpyMenuMaskView.h"
#import "ScrcpyConstants.h"
#import <SDL2/SDL_system.h>
#import <SDL2/SDL_syswm.h>
#import <SDL2/SDL_mouse.h>
#import "ScrcpyADBClient.h"
#import "ScrcpyVNCClient.h"
#import <objc/runtime.h>
#import "ScrcpyActionsBridge.h"
#import "ScrcpyActionsTableViewController.h"
#import "ADBClient.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Add logging macro
#define LOG_POSITION(fmt, ...) NSLog(@"[ScrcpyMenuView] " fmt, ##__VA_ARGS__)

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


@interface ScrcpyMenuView () <ScrcpyMenuMaskViewDelegate, ScrcpyMenuViewDelegate, UITableViewDataSource, UITableViewDelegate>

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
@property (nonatomic, strong) UIButton *clipboardSyncButton;
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
@property (nonatomic, strong) UIPanGestureRecognizer *dragGesture;  // 单指拖拽（鼠标移动）
@property (nonatomic, strong) UIPanGestureRecognizer *scrollGesture; // 双指滚动
@property (nonatomic, assign) CGPoint dragStartLocation;
@property (nonatomic, assign) CGPoint currentDragOffset;
@property (nonatomic, assign) CGPoint totalDragOffset;
@property (nonatomic, assign) BOOL isScrolling; // 滚动状态标识

// VNC 点击相关
@property (nonatomic, strong) UITapGestureRecognizer *vncTapGesture;
@property (nonatomic, strong) UITapGestureRecognizer *vncTwoFingerTapGesture;

// VNC 触摸事件追踪相关
@property (nonatomic, assign) NSTimeInterval touchStartTime;

// Actions Popup 相关
@property (nonatomic, strong) UIView *actionsPopupView;
@property (nonatomic, strong) UITableView *actionsTableView;
@property (nonatomic, strong) NSArray<ScrcpyActionData *> *actionsData;
@property (nonatomic, strong) UITapGestureRecognizer *dismissGestureRecognizer;
@property (nonatomic, strong) UIView *actionConfirmationView;
@property (nonatomic, assign) CGPoint touchStartLocation;
@property (nonatomic, assign) BOOL isDragging;

// File Transfer 相关
@property (nonatomic, strong) UIView *fileTransferPopupView;
@property (nonatomic, strong) UIScrollView *fileTransferScrollView;
@property (nonatomic, strong) NSMutableArray<NSURL *> *pendingFileURLs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIProgressView *> *fileProgressViews;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UILabel *> *fileStatusLabels;
@property (nonatomic, assign) BOOL isFileTransferCancelled;
@property (nonatomic, assign) NSInteger currentTransferIndex;
@property (nonatomic, assign) BOOL hasFileTransferError;
@property (nonatomic, strong) UIButton *fileTransferCloseButton;
@property (nonatomic, strong) UILabel *fileTransferHeaderLabel;

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
        
        // 初始化手势状态
        self.isDragging = NO;
        self.isScrolling = NO;
        self.currentZoomScale = 1.0;
        self.currentDragOffset = CGPointZero;
        self.totalDragOffset = CGPointZero;
        
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
    
    // 清理点击手势
    [self removeTapGesture];
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
    
    // Remove default button event handlers for Actions button
    [self.actionsButton removeTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.actionsButton removeTarget:self action:@selector(buttonTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [self.actionsButton removeTarget:self action:@selector(buttonTouchUpOutside:) forControlEvents:UIControlEventTouchUpOutside];
    [self.actionsButton removeTarget:self action:@selector(buttonTouchCancel:) forControlEvents:UIControlEventTouchCancel];
    
    // Add TapGesture to Actions button
    UITapGestureRecognizer *actionsTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(actionsButtonTappedViaGesture:)];
    actionsTapGesture.numberOfTapsRequired = 1;
    actionsTapGesture.cancelsTouchesInView = YES;
    [self.actionsButton addGestureRecognizer:actionsTapGesture];
    NSLog(@"🎯 [ScrcpyMenuView] Added TapGesture to Actions button");
    
    [self.menuView addSubview:self.actionsButton];
    
    // Clipboard Sync button (VNC only)
    self.clipboardSyncButton = [self createButtonWithIcon:kIconClipboardSyncButton position:tempButtonFrame];
    [self.menuView addSubview:self.clipboardSyncButton];
    
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
    NSLog(@"🚀 [ScrcpyMenuView] Actions button tapped");
    // 停止键盘输入
    SDL_StopTextInput();
    
    // Show the actions menu
    [self showActionsMenu];
}

- (void)actionsButtonTappedViaGesture:(UITapGestureRecognizer *)gesture {
    NSLog(@"🎯🎯🎯 [ScrcpyMenuView] actionsButtonTappedViaGesture called - GESTURE WORKING!");
    
    // Add visual feedback
    UIView *targetView = gesture.view;
    [UIView animateWithDuration:0.1 animations:^{
        targetView.alpha = 0.5;
        targetView.transform = CGAffineTransformMakeScale(0.95, 0.95);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1 animations:^{
            targetView.alpha = 1.0;
            targetView.transform = CGAffineTransformIdentity;
        }];
    }];
    
    // 停止键盘输入
    SDL_StopTextInput();
    
    // Show the actions menu
    NSLog(@"🎯🎯🎯 [ScrcpyMenuView] About to call showActionsMenu via gesture");
    [self showActionsMenu];
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
    if (!self.clipboardSyncButton.hidden) count++;
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
        self.clipboardSyncButton.hidden = YES; // ADB: do not show clipboard sync
        self.disconnectButton.hidden = NO;
        
        // 移除的Pinch手势（如果存在）
        [self removePinchGesture];
        
        // 移除的拖拽手势（如果存在）
        [self removeDragGesture];
        
        // 移除VNC点击手势（如果存在）
        [self removeTapGesture];
        
        LOG_POSITION(@"Configured menu for ADB device - all buttons visible");
    } else if (deviceType == ScrcpyDeviceTypeVNC) {
        // VNC设备只支持部分按钮
        self.backButton.hidden = YES;
        self.homeButton.hidden = YES;
        self.switchButton.hidden = YES;
        self.keyboardButton.hidden = NO;
        self.actionsButton.hidden = NO;
        self.clipboardSyncButton.hidden = NO; // VNC: show clipboard sync
        self.disconnectButton.hidden = NO;
        
        // 为VNC设备添加手势（延迟添加以确保SDL窗口初始化完成）
        LOG_POSITION(@"🐆 [ScrcpyMenuView] Scheduling VNC gestures setup with 0.3s delay");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            LOG_POSITION(@"🐆 [ScrcpyMenuView] Adding VNC gestures now");
            [self addPinchGesture];
            [self addDragGesture];
            [self addTapGesture];
            [self setupGesturePriorities];
            LOG_POSITION(@"🐆 [ScrcpyMenuView] VNC gestures setup completed");
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
    if (!self.clipboardSyncButton.hidden) [visibleButtons addObject:self.clipboardSyncButton];
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
    
    // 配置缩放手势的基本属性
    self.pinchGesture.delaysTouchesBegan = NO;      // 允许正常响应
    self.pinchGesture.delaysTouchesEnded = NO;      // 允许正常结束  
    self.pinchGesture.cancelsTouchesInView = YES;   // 取消其他手势的触摸
    
    // 添加到SDL窗口上
    UIViewController *rootVC = sdlWindow.rootViewController;
    if (rootVC && rootVC.view && rootVC.view.window) {
        [rootVC.view.window addGestureRecognizer:self.pinchGesture];
        LOG_POSITION(@"✅ Added pinch gesture to SDL window");
    } else {
        LOG_POSITION(@"⚠️ Cannot add pinch gesture - SDL window or root view controller not found");
    }
}

- (void)removePinchGesture {
    [self safeRemoveGesture:&_pinchGesture];
    LOG_POSITION(@"🗑️ Removed VNC pinch gesture");
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
    
    // 创建单指拖拽手势识别器（鼠标移动）
    self.dragGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    self.dragGesture.delegate = self;
    self.dragGesture.minimumNumberOfTouches = 1;
    self.dragGesture.maximumNumberOfTouches = 1;  // 仅单指
    LOG_POSITION(@"✅ Created single-finger drag gesture: %@", self.dragGesture);
    
    // 创建双指滚动手势识别器
    self.scrollGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleScroll:)];
    self.scrollGesture.delegate = self;
    self.scrollGesture.minimumNumberOfTouches = 2;
    self.scrollGesture.maximumNumberOfTouches = 2;  // 仅双指
    
    // 配置滚动手势的基本属性，不过于激进
    self.scrollGesture.delaysTouchesBegan = NO;     // 不延迟开始触摸
    self.scrollGesture.delaysTouchesEnded = NO;     // 不延迟结束触摸
    self.scrollGesture.cancelsTouchesInView = NO;   // 不取消其他手势，允许竞争
    
    LOG_POSITION(@"✅ Created two-finger scroll gesture with priority settings: %@", self.scrollGesture);
    
    // 添加到SDL窗口上
    UIViewController *rootVC = sdlWindow.rootViewController;
    if (rootVC && rootVC.view && rootVC.view.window) {
        [rootVC.view.window addGestureRecognizer:self.dragGesture];
        [rootVC.view.window addGestureRecognizer:self.scrollGesture];
        LOG_POSITION(@"✅ Added drag and scroll gestures to SDL window: %@", rootVC.view.window);
        LOG_POSITION(@"✅ Drag gesture added: %@", self.dragGesture);
        LOG_POSITION(@"✅ Scroll gesture added: %@", self.scrollGesture);
    } else {
        LOG_POSITION(@"⚠️ Cannot add drag gesture - SDL window or root view controller not found");
    }
}

- (void)removeDragGesture {
    [self safeRemoveGesture:&_dragGesture];
    [self safeRemoveGesture:&_scrollGesture];
    LOG_POSITION(@"🗑️ Removed VNC drag and scroll gestures");
}

- (void)resetDragOffset {
    self.currentDragOffset = CGPointZero;
    self.totalDragOffset = CGPointZero;
    self.dragStartLocation = CGPointZero;
    self.isDragging = NO;
    self.isScrolling = NO;
    LOG_POSITION(@"🔄 Reset drag offset and states to zero");
}

#pragma mark - VNC Tap Gesture Management

- (void)addTapGesture {
    // 移除已存在的手势（如果有）
    [self removeTapGesture];
    
    // 获取SDL窗口
    UIWindow *sdlWindow = [self getSDLWindow];
    if (!sdlWindow) {
        LOG_POSITION(@"⚠️ Cannot add tap gesture - SDL window not found");
        return;
    }
    
    // 创建单指点击手势识别器（左键点击）
    self.vncTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleVNCTap:)];
    self.vncTapGesture.delegate = self;
    self.vncTapGesture.numberOfTapsRequired = 1;
    self.vncTapGesture.numberOfTouchesRequired = 1;
    
    // 创建两指点击手势识别器（右键点击，类似TrackPad操作）
    self.vncTwoFingerTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleVNCTwoFingerTap:)];
    self.vncTwoFingerTapGesture.delegate = self;
    self.vncTwoFingerTapGesture.numberOfTapsRequired = 1;
    self.vncTwoFingerTapGesture.numberOfTouchesRequired = 2;
    
    // 添加到SDL窗口上
    UIViewController *rootVC = sdlWindow.rootViewController;
    if (rootVC && rootVC.view && rootVC.view.window) {
        [rootVC.view.window addGestureRecognizer:self.vncTapGesture];
        [rootVC.view.window addGestureRecognizer:self.vncTwoFingerTapGesture];
        LOG_POSITION(@"✅ Added tap and two-finger tap gestures to SDL window");
    } else {
        LOG_POSITION(@"⚠️ Cannot add tap gesture - SDL window or root view controller not found");
    }
}

- (void)removeTapGesture {
    [self safeRemoveGesture:&_vncTapGesture];
    [self safeRemoveGesture:&_vncTwoFingerTapGesture];
    LOG_POSITION(@"🗑️ Removed VNC tap gestures");
}

- (void)handleVNCTap:(UITapGestureRecognizer *)gesture {
    [self handleVNCTapGesture:gesture isRightClick:NO];
}

- (void)handleVNCTwoFingerTap:(UITapGestureRecognizer *)gesture {
    [self handleVNCTapGesture:gesture isRightClick:YES];
}

// Unified VNC tap gesture handler
- (void)handleVNCTapGesture:(UITapGestureRecognizer *)gesture isRightClick:(BOOL)isRightClick {
    if (gesture.state != UIGestureRecognizerStateEnded) {
        return;
    }

    CGPoint location = [gesture locationInView:gesture.view];
    CGSize viewSize = gesture.view.bounds.size;

    NSLog(@"🎯 [ScrcpyMenuView] VNC %@ tap gesture at (%.1f, %.1f), view size: (%.1fx%.1f)",
          isRightClick ? @"two-finger (right click)" : @"single", location.x, location.y, viewSize.width, viewSize.height);

    // 发送点击事件通知
    NSDictionary *userInfo = @{
        kKeyType: kMouseEventTypeClick,
        kKeyLocation: [NSValue valueWithCGPoint:location],
        kKeyIsRightClick: @(isRightClick),
        kKeyViewSize: [NSValue valueWithCGSize:viewSize]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCMouseEvent object:nil userInfo:userInfo];
}

- (void)setupGesturePriorities {
    // 设置手势优先级：点击手势优先级最高
    // 由于拖拽手势需要2-3个手指，它与单指点击手势在物理上不会冲突
    // 但为了确保点击响应速度，让其他单指手势等待点击手势失败

    LOG_POSITION(@"🎯 Setting up VNC gesture priorities");

    // 注意：由于拖拽手势配置为2-3指操作，理论上不会与单指点击冲突
    // 但如果有其他单指手势，可以在这里设置优先级
    if (self.vncTapGesture) {
        LOG_POSITION(@"✅ Tap gesture has highest priority for single finger touches");
    }
}

#pragma mark - UI Helpers

// Create an image with consistent container size (icon centered)
- (UIImage *)imageWithIcon:(UIImage *)icon inSize:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGFloat x = (size.width - icon.size.width) / 2;
    CGFloat y = (size.height - icon.size.height) / 2;
    [icon drawInRect:CGRectMake(x, y, icon.size.width, icon.size.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

#pragma mark - VNC Gesture Helpers

// Check if the gesture recognizer is a VNC-specific gesture
- (BOOL)isVNCGesture:(UIGestureRecognizer *)gestureRecognizer {
    return gestureRecognizer == self.pinchGesture ||
           gestureRecognizer == self.dragGesture ||
           gestureRecognizer == self.scrollGesture ||
           gestureRecognizer == self.vncTapGesture ||
           gestureRecognizer == self.vncTwoFingerTapGesture;
}

// Get descriptive name for a gesture recognizer (for logging)
- (NSString *)gestureNameForRecognizer:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.pinchGesture) return @"Pinch";
    if (gestureRecognizer == self.dragGesture) return @"Drag";
    if (gestureRecognizer == self.scrollGesture) return @"Scroll";
    if (gestureRecognizer == self.vncTapGesture) return @"Tap";
    if (gestureRecognizer == self.vncTwoFingerTapGesture) return @"TwoFingerTap";
    return @"Unknown";
}

// Calculate normalized offset (clamped to [-1, 1]) from translation and view size
- (CGPoint)normalizedOffsetForTranslation:(CGPoint)translation viewSize:(CGSize)viewSize {
    CGFloat normalizedOffsetX = viewSize.width > 0 ? translation.x / viewSize.width : 0;
    CGFloat normalizedOffsetY = viewSize.height > 0 ? translation.y / viewSize.height : 0;
    return CGPointMake(MAX(-1.0, MIN(1.0, normalizedOffsetX)), MAX(-1.0, MIN(1.0, normalizedOffsetY)));
}

// Unified delegate notification for drag state changes
- (void)notifyDelegateWithDragState:(NSString *)state location:(CGPoint)location viewSize:(CGSize)viewSize offset:(CGPoint)offset {
    if ([self.delegate respondsToSelector:@selector(didDragWithState:location:viewSize:offset:)]) {
        [self.delegate didDragWithState:state location:location viewSize:viewSize offset:offset];
    } else if ([self.delegate respondsToSelector:@selector(didDragWithState:location:viewSize:)]) {
        [self.delegate didDragWithState:state location:location viewSize:viewSize];
    }
    [self didDragWithState:state location:location viewSize:viewSize offset:offset];
}

// Unified delegate notification for normalized offset during drag
- (void)notifyDelegateWithNormalizedOffset:(CGPoint)normalizedOffset viewSize:(CGSize)viewSize isEnd:(BOOL)isEnd {
    if (isEnd) {
        if ([self.delegate respondsToSelector:@selector(didDragEndWithNormalizedOffset:viewSize:)]) {
            [self.delegate didDragEndWithNormalizedOffset:normalizedOffset viewSize:viewSize];
        }
        [self didDragEndWithNormalizedOffset:normalizedOffset viewSize:viewSize];
    } else {
        if ([self.delegate respondsToSelector:@selector(didDragWithNormalizedOffset:viewSize:)]) {
            [self.delegate didDragWithNormalizedOffset:normalizedOffset viewSize:viewSize];
        }
        [self didDragWithNormalizedOffset:normalizedOffset viewSize:viewSize];
    }
}

// Helper to safely remove a gesture recognizer and nil the reference
- (void)safeRemoveGesture:(UIGestureRecognizer * __strong *)gesturePtr {
    if (gesturePtr && *gesturePtr) {
        [(*gesturePtr).view removeGestureRecognizer:*gesturePtr];
        *gesturePtr = nil;
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    LOG_POSITION(@"🤝 [ScrcpyMenuView] shouldRecognizeSimultaneously - gesture1: %@, gesture2: %@", 
                 gestureRecognizer.class, otherGestureRecognizer.class);
    
    // 在拖拽或滚动过程中，禁止点击手势与任何其他手势同时进行
    if (self.isDragging || self.isScrolling) {
        if (gestureRecognizer == self.vncTapGesture || gestureRecognizer == self.vncTwoFingerTapGesture ||
            otherGestureRecognizer == self.vncTapGesture || otherGestureRecognizer == self.vncTwoFingerTapGesture) {
            return NO;
        }
    }
    
    // 双指滚动与单指拖拽不能同时进行（互相排斥）
    if ((gestureRecognizer == self.scrollGesture && otherGestureRecognizer == self.dragGesture) ||
        (gestureRecognizer == self.dragGesture && otherGestureRecognizer == self.scrollGesture)) {
        LOG_POSITION(@"⛔ [ScrcpyMenuView] Preventing simultaneous drag and scroll");
        return NO;
    }
    
    // 点击手势不与拖拽手势同时进行
    if ((gestureRecognizer == self.vncTapGesture && (otherGestureRecognizer == self.dragGesture || otherGestureRecognizer == self.scrollGesture)) ||
        ((gestureRecognizer == self.dragGesture || gestureRecognizer == self.scrollGesture) && otherGestureRecognizer == self.vncTapGesture)) {
        return NO;
    }
    
    // 两指点击手势不与拖拽或滚动手势同时进行
    if ((gestureRecognizer == self.vncTwoFingerTapGesture && (otherGestureRecognizer == self.dragGesture || otherGestureRecognizer == self.scrollGesture)) ||
        ((gestureRecognizer == self.dragGesture || gestureRecognizer == self.scrollGesture) && otherGestureRecognizer == self.vncTwoFingerTapGesture)) {
        return NO;
    }
    
    // 双指滚动与双指缩放可以尝试同时开始，通过手势特征判断优先级
    // 不在这里完全禁止，而是在手势开始时通过shouldBegin来判断
    if ((gestureRecognizer == self.scrollGesture && otherGestureRecognizer == self.pinchGesture) ||
        (gestureRecognizer == self.pinchGesture && otherGestureRecognizer == self.scrollGesture)) {
        LOG_POSITION(@"🤝 [ScrcpyMenuView] Allowing scroll and pinch to compete");
        return YES;  // 允许同时尝试，让系统根据手势特征选择
    }
    
    // 允许Pinch手势与单指拖拽手势同时进行
    if ((gestureRecognizer == self.pinchGesture && otherGestureRecognizer == self.dragGesture) ||
        (gestureRecognizer == self.dragGesture && otherGestureRecognizer == self.pinchGesture)) {
        return YES;
    }
    
    // 其他情况不允许同时进行
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    LOG_POSITION(@"🐆 [ScrcpyMenuView] shouldReceiveTouch - gesture: %@, isDragging: %@, isScrolling: %@, deviceType: %ld", 
                 gestureRecognizer.class, self.isDragging ? @"YES" : @"NO", self.isScrolling ? @"YES" : @"NO", (long)self.currentDeviceType);
    
    // 在拖拽或滚动过程中，阻止点击手势接收触摸事件
    if (self.isDragging || self.isScrolling) {
        if (gestureRecognizer == self.vncTapGesture || gestureRecognizer == self.vncTwoFingerTapGesture) {
            NSLog(@"🚫 [ScrcpyMenuView] Blocking tap gesture during drag/scroll");
            return NO;
        }
    }
    
    // 在滚动过程中，阻止单指拖拽手势接收触摸事件
    if (self.isScrolling && gestureRecognizer == self.dragGesture) {
        NSLog(@"🚫 [ScrcpyMenuView] Blocking single-finger drag during scroll");
        return NO;
    }
    
    // 在明确的滚动过程中（已经确定为滚动），阻止缩放手势
    // 但只有在滚动手势真正激活后才阻止，避免过早阻断
    if (self.isScrolling && gestureRecognizer == self.pinchGesture && self.scrollGesture.state == UIGestureRecognizerStateChanged) {
        NSLog(@"🚫 [ScrcpyMenuView] Blocking pinch gesture during active scroll");
        return NO;
    }
    
    // 在单指拖拽过程中，阻止双指滚动手势接收触摸事件
    if (self.isDragging && gestureRecognizer == self.scrollGesture) {
        NSLog(@"🚫 [ScrcpyMenuView] Blocking two-finger scroll during drag");
        return NO;
    }
    
    // 确保所有VNC手势只在VNC设备时响应
    if ([self isVNCGesture:gestureRecognizer]) {
        BOOL shouldReceive = (self.currentDeviceType == ScrcpyDeviceTypeVNC);
        LOG_POSITION(@"🔍 [ScrcpyMenuView] VNC gesture %@ shouldReceive: %@",
                     [self gestureNameForRecognizer:gestureRecognizer], shouldReceive ? @"YES" : @"NO");
        return shouldReceive;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    LOG_POSITION(@"⏳ [ScrcpyMenuView] shouldRequireFailure - gesture: %@, waitFor: %@", 
                 gestureRecognizer.class, otherGestureRecognizer.class);
    
    // 简化逻辑：只让非点击手势等待点击手势失败
    if (otherGestureRecognizer == self.vncTapGesture) {
        // 其他手势应该等待点击手势失败（除了拖拽和滚动手势，因为它们使用不同数量的手指）
        if (gestureRecognizer != self.dragGesture && gestureRecognizer != self.scrollGesture) {
            LOG_POSITION(@"⏳ [ScrcpyMenuView] Gesture %@ will wait for tap to fail", gestureRecognizer.class);
            return YES;
        }
    }
    
    // 移除严格的等待逻辑，让手势系统根据手势特征自然选择
    // 滚动和缩放手势应该能够公平竞争，而不是强制等待
    if (gestureRecognizer == self.pinchGesture && otherGestureRecognizer == self.scrollGesture) {
        LOG_POSITION(@"🤝 [ScrcpyMenuView] Pinch and scroll gestures compete naturally");
        return NO;  // 不强制等待，让系统自然选择
    }
    
    // 不设置任何其他优先级，让手势系统根据手指数量自动选择
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 点击手势不需要等待其他手势失败（除了双击需要等待单击失败）
    return NO;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // 智能判断：基于手势特征决定是否应该开始
    if (gestureRecognizer == self.pinchGesture || gestureRecognizer == self.scrollGesture) {
        // 如果另一个双指手势已经在进行中，进行智能判断
        if (gestureRecognizer == self.pinchGesture && self.isScrolling) {
            // 如果已经在滚动，只有在明显的缩放动作时才允许切换到缩放
            // 检查是否有明显的缩放意图（两指距离变化）
            if (gestureRecognizer.numberOfTouches >= 2) {
                LOG_POSITION(@"🤔 [ScrcpyMenuView] Pinch gesture wants to start during scroll - allowing competition");
            }
            return YES; // 允许尝试，让系统决定
        }
        
        if (gestureRecognizer == self.scrollGesture && self.pinchGesture.state == UIGestureRecognizerStateChanged) {
            // 如果缩放手势已经在进行，通常不应该开始滚动
            LOG_POSITION(@"🤔 [ScrcpyMenuView] Scroll gesture wants to start during pinch - allowing competition");
            return YES; // 允许尝试
        }
    }
    
    return YES; // 默认允许所有手势开始
}

#pragma mark - Drag Gesture Handler

- (void)handleDrag:(UIPanGestureRecognizer *)gesture {
    LOG_POSITION(@"🎯 [ScrcpyMenuView] handleDrag called - state: %ld, deviceType: %ld", (long)gesture.state, (long)self.currentDeviceType);

    if (self.currentDeviceType != ScrcpyDeviceTypeVNC) {
        LOG_POSITION(@"⚠️ [ScrcpyMenuView] handleDrag ignored - not VNC device");
        return;
    }

    CGPoint location = [gesture locationInView:gesture.view];
    CGSize viewSize = gesture.view.bounds.size;

    LOG_POSITION(@"🎯 VNC Single-finger drag gesture - state: %ld, location: (%.1f, %.1f)",
                 (long)gesture.state, location.x, location.y);

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            self.dragStartLocation = location;
            self.currentDragOffset = CGPointZero;
            self.isDragging = YES;

            LOG_POSITION(@"🎯 VNC Single-finger drag began - start location: (%.1f, %.1f), viewSize: (%.1f, %.1f), isDragging: %@",
                         location.x, location.y, viewSize.width, viewSize.height, self.isDragging ? @"YES" : @"NO");

            [self notifyDelegateWithDragState:kDragStateBegan location:location viewSize:viewSize offset:self.currentDragOffset];
            break;
        }

        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [gesture translationInView:gesture.view];
            self.currentDragOffset = translation;
            CGPoint normalizedOffset = [self normalizedOffsetForTranslation:translation viewSize:viewSize];

            LOG_POSITION(@"🎯 VNC Single-finger drag changed - location: (%.1f, %.1f), translation: (%.1f, %.1f), normalized offset: (%.3f, %.3f)",
                         location.x, location.y, translation.x, translation.y, normalizedOffset.x, normalizedOffset.y);

            [self notifyDelegateWithDragState:kDragStateChanged location:location viewSize:viewSize offset:self.currentDragOffset];
            [self notifyDelegateWithNormalizedOffset:normalizedOffset viewSize:viewSize isEnd:NO];
            break;
        }

        case UIGestureRecognizerStateEnded: {
            CGPoint translation = [gesture translationInView:gesture.view];
            self.currentDragOffset = translation;
            self.totalDragOffset = CGPointMake(self.totalDragOffset.x + translation.x,
                                              self.totalDragOffset.y + translation.y);
            CGPoint normalizedOffset = [self normalizedOffsetForTranslation:translation viewSize:viewSize];

            LOG_POSITION(@"🎯 VNC Single-finger drag ended - location: (%.1f, %.1f), final translation: (%.1f, %.1f), normalized offset: (%.3f, %.3f)",
                         location.x, location.y, translation.x, translation.y, normalizedOffset.x, normalizedOffset.y);

            [self notifyDelegateWithDragState:kDragStateEnded location:location viewSize:viewSize offset:self.currentDragOffset];
            [self notifyDelegateWithNormalizedOffset:normalizedOffset viewSize:viewSize isEnd:YES];

            self.isDragging = NO;
            LOG_POSITION(@"🎯 VNC Single-finger drag ended - isDragging reset to: %@", self.isDragging ? @"YES" : @"NO");
            break;
        }

        case UIGestureRecognizerStateCancelled: {
            self.currentDragOffset = CGPointZero;

            LOG_POSITION(@"🎯 VNC Single-finger drag cancelled - location: (%.1f, %.1f)", location.x, location.y);

            [self notifyDelegateWithDragState:kDragStateCancelled location:location viewSize:viewSize offset:self.currentDragOffset];

            self.isDragging = NO;
            LOG_POSITION(@"🎯 VNC Single-finger drag cancelled - isDragging reset to: %@", self.isDragging ? @"YES" : @"NO");
            break;
        }

        default:
            break;
    }
}

#pragma mark - Scroll Gesture Handler

- (void)handleScroll:(UIPanGestureRecognizer *)gesture {
    LOG_POSITION(@"📜 [ScrcpyMenuView] handleScroll called - state: %ld, deviceType: %ld", (long)gesture.state, (long)self.currentDeviceType);
    
    if (self.currentDeviceType != ScrcpyDeviceTypeVNC) {
        LOG_POSITION(@"⚠️ [ScrcpyMenuView] handleScroll ignored - not VNC device");
        return;
    }
    
    // 双指滚动手势，用于滚动操作
    CGPoint location = [gesture locationInView:gesture.view];
    CGSize viewSize = gesture.view.bounds.size;
    
    LOG_POSITION(@"📜 VNC Two-finger scroll gesture - state: %ld, location: (%.1f, %.1f)", 
                 (long)gesture.state, location.x, location.y);
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            // 记录滚动开始位置并设置滚动状态
            self.dragStartLocation = location;
            self.currentDragOffset = CGPointZero;
            self.isScrolling = YES;
            
            LOG_POSITION(@"📜 VNC Two-finger scroll began - start location: (%.1f, %.1f), viewSize: (%.1f, %.1f), isScrolling: %@", 
                         location.x, location.y, viewSize.width, viewSize.height, self.isScrolling ? @"YES" : @"NO");
            
            // 发送滚动开始通知
            [self sendScrollNotificationWithState:kDragStateBegan 
                                          location:location 
                                          viewSize:viewSize 
                                            offset:CGPointZero];
            break;
        }
            
        case UIGestureRecognizerStateChanged: {
            // 计算当前滚动偏移量（相对于开始位置）
            CGPoint translation = [gesture translationInView:gesture.view];
            self.currentDragOffset = translation;
            
            LOG_POSITION(@"📜 VNC Two-finger scroll changed - location: (%.1f, %.1f), translation: (%.1f, %.1f)", 
                         location.x, location.y, translation.x, translation.y);
            
            // 发送滚动移动通知
            [self sendScrollNotificationWithState:kDragStateChanged 
                                          location:location 
                                          viewSize:viewSize 
                                            offset:translation];
            break;
        }
            
        case UIGestureRecognizerStateEnded: {
            // 计算最终滚动偏移量
            CGPoint translation = [gesture translationInView:gesture.view];
            self.currentDragOffset = translation;
            
            LOG_POSITION(@"📜 VNC Two-finger scroll ended - location: (%.1f, %.1f), final translation: (%.1f, %.1f)", 
                         location.x, location.y, translation.x, translation.y);
            
            // 发送滚动结束通知
            [self sendScrollNotificationWithState:kDragStateEnded 
                                          location:location 
                                          viewSize:viewSize 
                                            offset:translation];
            
            // 重置滚动状态
            self.isScrolling = NO;
            LOG_POSITION(@"📜 VNC Two-finger scroll ended - isScrolling reset to: %@", self.isScrolling ? @"YES" : @"NO");
            break;
        }
            
        case UIGestureRecognizerStateCancelled: {
            // 重置滚动偏移量
            self.currentDragOffset = CGPointZero;
            
            LOG_POSITION(@"📜 VNC Two-finger scroll cancelled - location: (%.1f, %.1f)", location.x, location.y);
            
            // 发送滚动取消通知
            [self sendScrollNotificationWithState:kDragStateCancelled 
                                          location:location 
                                          viewSize:viewSize 
                                            offset:CGPointZero];
            
            // 重置滚动状态
            self.isScrolling = NO;
            LOG_POSITION(@"📜 VNC Two-finger scroll cancelled - isScrolling reset to: %@", self.isScrolling ? @"YES" : @"NO");
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
    // 发送VNC拖拽偏移量通知（包含当前缩放倍数）
    NSDictionary *userInfo = @{
        kKeyNormalizedOffset: [NSValue valueWithCGPoint:normalizedOffset],
        kKeyViewSize: [NSValue valueWithCGSize:viewSize],
        kKeyZoomScale: @(self.currentZoomScale)
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCDragOffset object:nil userInfo:userInfo];
}

- (void)didDragEndWithNormalizedOffset:(CGPoint)normalizedOffset viewSize:(CGSize)viewSize {
    // 发送VNC拖拽结束偏移量通知（包含当前缩放倍数）
    NSDictionary *userInfo = @{
        kKeyNormalizedOffset: [NSValue valueWithCGPoint:normalizedOffset],
        kKeyViewSize: [NSValue valueWithCGSize:viewSize],
        kKeyZoomScale: @(self.currentZoomScale)
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCDragOffset object:nil userInfo:userInfo];
}

#pragma mark - VNC Scroll Event Handling

// 发送滚动事件通知
- (void)sendScrollNotificationWithState:(NSString *)state location:(CGPoint)location viewSize:(CGSize)viewSize offset:(CGPoint)offset {
    // 计算归一化的偏移量（相对于视图尺寸的比例）
    CGFloat normalizedOffsetX = offset.x / viewSize.width;
    CGFloat normalizedOffsetY = offset.y / viewSize.height;
    
    // 确保归一化偏移量在合理范围内
    normalizedOffsetX = MAX(-1.0, MIN(1.0, normalizedOffsetX));
    normalizedOffsetY = MAX(-1.0, MIN(1.0, normalizedOffsetY));
    
    CGPoint normalizedOffset = CGPointMake(normalizedOffsetX, normalizedOffsetY);
    
    LOG_POSITION(@"📜 [ScrcpyMenuView] Sending scroll notification - state: %@, offset: (%.1f, %.1f), normalized: (%.3f, %.3f)", 
                 state, offset.x, offset.y, normalizedOffset.x, normalizedOffset.y);
    
    // 发送VNC滚动事件通知
    NSDictionary *userInfo = @{
        kKeyState: state,
        kKeyLocation: [NSValue valueWithCGPoint:location],
        kKeyViewSize: [NSValue valueWithCGSize:viewSize],
        kKeyOffset: [NSValue valueWithCGPoint:offset],
        kKeyNormalizedOffset: [NSValue valueWithCGPoint:normalizedOffset],
        kKeyZoomScale: @(self.currentZoomScale),
        kKeyType: kMouseEventTypeScroll  // 添加滚动事件类型标识
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCScrollEvent object:nil userInfo:userInfo];
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

#pragma mark - Button Touch Event Handlers

- (void)buttonTouchDown:(UIButton *)sender {
    // Visual feedback for button press
    [self animateButton:sender pressed:YES];
}

- (void)buttonTouchUpInside:(UIButton *)sender {
    [self animateButton:sender pressed:NO];
    // Handle button action based on accessibility identifier
    NSString *buttonType = sender.accessibilityIdentifier;
    [self handleButtonAction:buttonType];
}

- (void)buttonTouchUpOutside:(UIButton *)sender {
    [self animateButton:sender pressed:NO];
}

- (void)buttonTouchCancel:(UIButton *)sender {
    [self animateButton:sender pressed:NO];
}

// Unified button animation helper
- (void)animateButton:(UIButton *)button pressed:(BOOL)pressed {
    [UIView animateWithDuration:0.1 animations:^{
        button.alpha = pressed ? 0.5 : 1.0;
        button.transform = pressed ? CGAffineTransformMakeScale(0.9, 0.9) : CGAffineTransformIdentity;
    }];
}

- (void)handleButtonAction:(NSString *)buttonType {
    if ([buttonType isEqualToString:kIconActionsButton]) {
        [self actionsButtonTapped:nil];
    } else if ([buttonType isEqualToString:kIconBackButton]) {
        [self backButtonTapped:nil];
    } else if ([buttonType isEqualToString:kIconHomeButton]) {
        [self homeButtonTapped:nil];
    } else if ([buttonType isEqualToString:kIconSwitchButton]) {
        [self switchButtonTapped:nil];
    } else if ([buttonType isEqualToString:kIconKeyboardButton]) {
        [self keyboardButtonTapped:nil];
    } else if ([buttonType isEqualToString:kIconClipboardSyncButton]) {
        // Post notification to request VNC clipboard sync
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationVNCSyncClipboardRequest object:nil];
    } else if ([buttonType isEqualToString:kIconDisconnectButton]) {
        [self disconnectButtonTapped:nil];
    }
}

#pragma mark - Actions Menu Implementation

- (void)showActionsMenu {
    NSLog(@"🔥 [ScrcpyMenuView] Showing Actions popup menu");
    
    // 如果已经显示了 popup，先隐藏它
    if (self.actionsPopupView) {
        [self hideActionsMenu];
        return;
    }
    
    // 获取当前设备的 actions
    ScrcpyActionsBridge *actionsBridge = [ScrcpyActionsBridge shared];
    self.actionsData = [actionsBridge getActionsForCurrentDevice];
    
    NSLog(@"🔥 [ScrcpyMenuView] Found %lu actions for current device", (unsigned long)self.actionsData.count);
    
    if (self.actionsData.count == 0) {
        NSLog(@"⚠️ [ScrcpyMenuView] No actions found for current device");
        [self showNoActionsMessage];
        return;
    }
    
    // 创建 popup 视图
    [self createActionsPopup];
    
    // 显示 popup
    [self showActionsPopup];
}

- (void)hideActionsMenu {
    NSLog(@"🔥 [ScrcpyMenuView] Hiding Actions popup menu");
    
    if (!self.actionsPopupView) {
        return;
    }
    
    // 移除手势识别器
    UIWindow *window = [self activeWindow];
    if (window && self.dismissGestureRecognizer) {
        [window removeGestureRecognizer:self.dismissGestureRecognizer];
        self.dismissGestureRecognizer = nil;
        NSLog(@"🔧 [ScrcpyMenuView] Removed dismiss gesture recognizer");
    }
    
    // 动画隐藏 popup
    [UIView animateWithDuration:0.2 animations:^{
        self.actionsPopupView.alpha = 0.0;
        self.actionsPopupView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [self.actionsPopupView removeFromSuperview];
        self.actionsPopupView = nil;
        self.actionsTableView = nil;
        self.actionsData = nil;
    }];
}

- (void)showNoActionsMessage {
    NSLog(@"⚠️ [ScrcpyMenuView] Showing no actions message");
    
    UIWindow *window = [self activeWindow];
    if (!window) return;
    
    // 创建临时提示视图
    UIView *messageView = [[UIView alloc] init];
    messageView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    messageView.layer.cornerRadius = 10.0;
    
    UILabel *messageLabel = [[UILabel alloc] init];
    messageLabel.text = @"No Actions Available";
    messageLabel.textColor = [UIColor whiteColor];
    messageLabel.font = [UIFont systemFontOfSize:16.0];
    messageLabel.textAlignment = NSTextAlignmentCenter;
    
    [messageView addSubview:messageLabel];
    
    // Layout
    CGFloat messageWidth = 180.0;
    CGFloat messageHeight = 60.0;
    messageView.frame = CGRectMake(0, 0, messageWidth, messageHeight);
    messageLabel.frame = messageView.bounds;

    // 计算位置（在 Actions 按钮上方，与按钮右对齐）
    // actionsButton 是 menuView 的子视图，需要从 menuView 坐标系转换到 window 坐标系
    CGRect actionsButtonFrame = [self.menuView convertRect:self.actionsButton.frame toView:window];

    // 使消息视图右边缘与按钮右边缘对齐
    CGFloat popupX = CGRectGetMaxX(actionsButtonFrame) - messageWidth;
    CGFloat popupY = actionsButtonFrame.origin.y - messageHeight - 10;

    // 确保在屏幕范围内
    popupX = MAX(10, MIN(popupX, window.bounds.size.width - messageWidth - 10));
    if (popupY < 50) {
        popupY = CGRectGetMaxY(actionsButtonFrame) + 10;
    }

    messageView.frame = CGRectMake(popupX, popupY, messageWidth, messageHeight);
    messageView.alpha = 0.0;
    messageView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    
    [window addSubview:messageView];
    
    // 显示动画
    [UIView animateWithDuration:0.2 animations:^{
        messageView.alpha = 1.0;
        messageView.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        // 2秒后自动隐藏
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.2 animations:^{
                messageView.alpha = 0.0;
            } completion:^(BOOL finished) {
                [messageView removeFromSuperview];
            }];
        });
    }];
}

- (void)createActionsPopup {
    NSLog(@"🔥 [ScrcpyMenuView] Creating Actions popup");
    
    UIWindow *window = [self activeWindow];
    if (!window) return;
    
    // 计算 popup 大小
    CGFloat popupWidth = 280.0;
    CGFloat cellHeight = 50.0;
    CGFloat maxHeight = MIN(self.actionsData.count * cellHeight + 20, window.bounds.size.height * 0.6);
    CGFloat popupHeight = maxHeight;
    
    // 创建 popup 容器
    self.actionsPopupView = [[UIView alloc] init];
    self.actionsPopupView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.9];
    self.actionsPopupView.layer.cornerRadius = 12.0;
    self.actionsPopupView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.actionsPopupView.layer.shadowOffset = CGSizeMake(0, 4);
    self.actionsPopupView.layer.shadowOpacity = 0.3;
    self.actionsPopupView.layer.shadowRadius = 8.0;
    self.actionsPopupView.userInteractionEnabled = YES;
    NSLog(@"🔧 [ScrcpyMenuView] Popup container created with userInteractionEnabled=YES");
    
    // 创建 TableView
    self.actionsTableView = [[UITableView alloc] init];
    self.actionsTableView.backgroundColor = [UIColor clearColor];
    self.actionsTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.actionsTableView.dataSource = self;
    self.actionsTableView.delegate = self;
    self.actionsTableView.rowHeight = cellHeight;
    self.actionsTableView.layer.cornerRadius = 8.0;
    self.actionsTableView.showsVerticalScrollIndicator = NO;
    self.actionsTableView.userInteractionEnabled = YES;
    self.actionsTableView.allowsSelection = YES;
    NSLog(@"🔧 [ScrcpyMenuView] TableView created with userInteractionEnabled=YES, allowsSelection=YES");
    
    // 注册 cell
    [self.actionsTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ActionCell"];
    
    [self.actionsPopupView addSubview:self.actionsTableView];
    
    // Layout TableView (留出一些边距)
    self.actionsTableView.frame = CGRectMake(10, 10, popupWidth - 20, popupHeight - 20);

    // 计算 popup 位置（在 Actions 按钮上方，与按钮右对齐）
    // actionsButton 是 menuView 的子视图，需要从 menuView 坐标系转换到 window 坐标系
    CGRect actionsButtonFrame = [self.menuView convertRect:self.actionsButton.frame toView:window];

    NSLog(@"🔧 [ScrcpyMenuView] Actions button frame in window: %@", NSStringFromCGRect(actionsButtonFrame));

    // 使 popup 右边缘与按钮右边缘对齐
    CGFloat popupX = CGRectGetMaxX(actionsButtonFrame) - popupWidth;
    CGFloat popupY = actionsButtonFrame.origin.y - popupHeight - 10;

    // 确保 popup 在屏幕范围内
    CGFloat minX = 10;
    CGFloat maxX = window.bounds.size.width - popupWidth - 10;
    popupX = MAX(minX, MIN(popupX, maxX));

    if (popupY < 50) {
        // 如果上方空间不够，显示在按钮下方
        popupY = CGRectGetMaxY(actionsButtonFrame) + 10;
    }

    // 确保 popup 不会超出屏幕底部
    if (popupY + popupHeight > window.bounds.size.height - 10) {
        popupY = window.bounds.size.height - popupHeight - 10;
    }

    self.actionsPopupView.frame = CGRectMake(popupX, popupY, popupWidth, popupHeight);
    
    NSLog(@"🔥 [ScrcpyMenuView] Popup frame: %@", NSStringFromCGRect(self.actionsPopupView.frame));
}

- (void)showActionsPopup {
    NSLog(@"🔥 [ScrcpyMenuView] Showing Actions popup");
    
    UIWindow *window = [self activeWindow];
    if (!window) return;
    
    // 初始状态
    self.actionsPopupView.alpha = 0.0;
    self.actionsPopupView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    
    // 添加到窗口
    [window addSubview:self.actionsPopupView];
    
    // 添加点击外部关闭的手势
    self.dismissGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissActionsPopup:)];
    self.dismissGestureRecognizer.cancelsTouchesInView = NO;  // 关键：不要取消其他视图的触摸事件
    [window addGestureRecognizer:self.dismissGestureRecognizer];
    NSLog(@"🔧 [ScrcpyMenuView] Added dismiss gesture with cancelsTouchesInView=NO");
    
    // 显示动画
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.actionsPopupView.alpha = 1.0;
        self.actionsPopupView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismissActionsPopup:(UITapGestureRecognizer *)gesture {
    UIWindow *window = [self activeWindow];
    if (!window || !self.actionsPopupView) {
        return;
    }
    
    // 获取在 window 中的点击位置
    CGPoint locationInWindow = [gesture locationInView:window];
    
    // 获取 popup 在 window 中的 frame
    CGRect popupFrameInWindow = self.actionsPopupView.frame;
    
    NSLog(@"🔍 [ScrcpyMenuView] Tap location in window: %@", NSStringFromCGPoint(locationInWindow));
    NSLog(@"🔍 [ScrcpyMenuView] Popup frame in window: %@", NSStringFromCGRect(popupFrameInWindow));
    
    // 如果点击在 popup 内部，不关闭
    if (CGRectContainsPoint(popupFrameInWindow, locationInWindow)) {
        NSLog(@"🔍 [ScrcpyMenuView] Tap inside popup - NOT closing");
        return;
    }
    
    NSLog(@"🔍 [ScrcpyMenuView] Tap outside popup - closing");
    
    // 移除手势识别器
    if (self.dismissGestureRecognizer) {
        [window removeGestureRecognizer:self.dismissGestureRecognizer];
        self.dismissGestureRecognizer = nil;
    }
    
    // 关闭 popup
    [self hideActionsMenu];
}

#pragma mark - TableView DataSource & Delegate

// Helper to check if "Send Files" should be shown (only for ADB devices)
- (BOOL)shouldShowSendFilesOption {
    return self.currentDeviceType == ScrcpyDeviceTypeADB;
}

// Helper to get the actual action index from table row
- (NSInteger)actionIndexFromRow:(NSInteger)row {
    return [self shouldShowSendFilesOption] ? row - 1 : row;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = self.actionsData.count;
    if ([self shouldShowSendFilesOption]) {
        count += 1; // Add "Send Files" row
    }
    NSLog(@"🔧 [ScrcpyMenuView] numberOfRowsInSection returning: %ld", (long)count);
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"🔧 [ScrcpyMenuView] cellForRowAtIndexPath called for row: %ld", (long)indexPath.row);
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActionCell" forIndexPath:indexPath];

    // 配置 cell 外观
    cell.backgroundColor = [UIColor clearColor];
    cell.selectedBackgroundView = [[UIView alloc] init];
    cell.selectedBackgroundView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];

    // Left align text
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    cell.detailTextLabel.textAlignment = NSTextAlignmentLeft;

    // Define consistent icon container size
    CGSize iconContainerSize = CGSizeMake(28, 28);
    UIImageSymbolConfiguration *largeConfig = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    UIImageSymbolConfiguration *smallConfig = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];

    // Check if this is the "Send Files" row (first row for ADB devices)
    if ([self shouldShowSendFilesOption] && indexPath.row == 0) {
        // Use SF Symbol for Send Files
        UIImage *sendIcon = [[UIImage systemImageNamed:@"square.and.arrow.up.fill" withConfiguration:largeConfig]
                             imageWithTintColor:[UIColor systemBlueColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        cell.imageView.image = [self imageWithIcon:sendIcon inSize:iconContainerSize];
        cell.textLabel.text = @"Send Files";
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = @"Push files to /sdcard/Download";
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
        return cell;
    }

    // Get actual action index
    NSInteger actionIndex = [self actionIndexFromRow:indexPath.row];
    if (actionIndex < 0 || actionIndex >= (NSInteger)self.actionsData.count) {
        return cell;
    }

    ScrcpyActionData *actionData = self.actionsData[actionIndex];

    // Use SF Symbol for custom actions (smaller icon, same container width)
    UIImage *actionIcon = [[UIImage systemImageNamed:@"terminal.fill" withConfiguration:smallConfig]
                           imageWithTintColor:[UIColor systemGrayColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    cell.imageView.image = [self imageWithIcon:actionIcon inSize:iconContainerSize];

    // 配置文本
    cell.textLabel.text = actionData.name;
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16.0];

    // 配置细节文本
    NSString *timingText = @"";
    if ([actionData.executionTiming isEqualToString:@"immediate"]) {
        timingText = @"Immediate";
    } else if ([actionData.executionTiming isEqualToString:@"delayed"]) {
        timingText = [NSString stringWithFormat:@"Delay %lds", (long)actionData.delaySeconds];
    } else {
        timingText = @"Confirm";
    }

    cell.detailTextLabel.text = timingText;
    cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"🔥 [ScrcpyMenuView] didSelectRowAtIndexPath called for row: %ld", (long)indexPath.row);
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    // Check if "Send Files" was tapped (first row for ADB devices)
    if ([self shouldShowSendFilesOption] && indexPath.row == 0) {
        NSLog(@"📤 [ScrcpyMenuView] Send Files selected");
        [self hideActionsMenu];
        [self showFilePicker];
        return;
    }

    // Get actual action index
    NSInteger actionIndex = [self actionIndexFromRow:indexPath.row];
    if (actionIndex < 0 || actionIndex >= (NSInteger)self.actionsData.count) {
        return;
    }

    ScrcpyActionData *selectedAction = self.actionsData[actionIndex];
    NSLog(@"🎯 [ScrcpyMenuView] Action selected: %@", selectedAction.name);

    // 检查是否需要确认，如果需要确认则不立即隐藏菜单
    BOOL requiresConfirmation = [selectedAction.executionTiming isEqualToString:@"confirmation"];

    // 执行选中的 action
    [self executeActionData:selectedAction];

    // 只有当不需要确认时才立即隐藏 popup
    if (!requiresConfirmation) {
        [self hideActionsMenu];
    }
    // 如果需要确认，菜单会在确认框关闭后自动隐藏
}

- (void)executeActionData:(ScrcpyActionData *)actionData {
    NSLog(@"🚀 [ScrcpyMenuView] Executing action on current session: %@", actionData.name);
    
    ScrcpyActionsBridge *actionsBridge = [ScrcpyActionsBridge shared];
    
    [actionsBridge executeActionOnCurrentSession:actionData
                                  statusCallback:^(NSInteger status, NSString * _Nullable message, BOOL isConnecting) {
                                      NSLog(@"📊 [ScrcpyMenuView] Action status: %ld, message: %@, connecting: %@", 
                                            (long)status, message, isConnecting ? @"YES" : @"NO");
                                  }
                                   errorCallback:^(NSString *title, NSString *message) {
                                       NSLog(@"❌ [ScrcpyMenuView] Action error: %@ - %@", title, message);
                                   }
                            confirmationCallback:^(ScrcpyActionData *action, void (^confirmCallback)(void)) {
                                NSLog(@"✋ [ScrcpyMenuView] Action requires confirmation: %@", action.name);
                                [self showActionConfirmation:action confirmCallback:confirmCallback];
                            }];
}

// Use the same global confirmation alert as ActionsView for consistency
- (void)showActionConfirmation:(ScrcpyActionData *)actionData confirmCallback:(void (^)(void))confirmCallback {
    NSLog(@"✋ [ScrcpyMenuView] Showing action confirmation (unified) for: %@", actionData.name);

    // Hide Actions popup first
    [self hideActionsMenu];

    // Present unified global confirmation using Swift presenter
    [ActionConfirmationPresenter showForActionId:actionData.actionId confirmCallback:confirmCallback];
}

- (void)cancelActionConfirmation:(UIButton *)sender {
    NSLog(@"❌ [ScrcpyMenuView] Action confirmation cancelled");
    [self hideActionConfirmation];
}

- (void)executeActionConfirmation:(UIButton *)sender {
    NSLog(@"✅ [ScrcpyMenuView] Action confirmation accepted");
    
    void (^confirmCallback)(void) = objc_getAssociatedObject(sender, "confirmCallback");
    if (confirmCallback) {
        confirmCallback();
    }
    
    [self hideActionConfirmation];
}

- (void)hideActionConfirmation {
    if (!self.actionConfirmationView) {
        return;
    }

    [UIView animateWithDuration:0.2 animations:^{
        self.actionConfirmationView.alpha = 0.0;
        self.actionConfirmationView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [self.actionConfirmationView removeFromSuperview];
        self.actionConfirmationView = nil;
    }];
}

#pragma mark - File Transfer

- (void)showFilePicker {
    NSLog(@"📂 [ScrcpyMenuView] Showing file picker");

    // Create document picker for selecting files
    NSArray *contentTypes = @[UTTypeItem, UTTypeData, UTTypeContent];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
                                              initForOpeningContentTypes:contentTypes
                                              asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;

    // Find the top view controller to present from
    UIViewController *topVC = [self topViewController];
    if (topVC) {
        [topVC presentViewController:picker animated:YES completion:nil];
    } else {
        NSLog(@"❌ [ScrcpyMenuView] Cannot present file picker - no top view controller");
    }
}

- (UIViewController *)topViewController {
    UIViewController *topVC = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) {
                    topVC = window.rootViewController;
                    while (topVC.presentedViewController) {
                        topVC = topVC.presentedViewController;
                    }
                    return topVC;
                }
            }
        }
    }
    return topVC;
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSLog(@"📂 [ScrcpyMenuView] Picked %lu files", (unsigned long)urls.count);

    if (urls.count == 0) {
        return;
    }

    // Store file URLs and start transfer
    self.pendingFileURLs = [urls mutableCopy];
    self.isFileTransferCancelled = NO;
    self.hasFileTransferError = NO;
    self.currentTransferIndex = 0;

    // Show progress popup
    [self showFileTransferProgress];

    // Start file transfer
    [self startFileTransfer];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    NSLog(@"📂 [ScrcpyMenuView] File picker cancelled");
}

#pragma mark - File Transfer Progress UI

- (void)showFileTransferProgress {
    NSLog(@"📤 [ScrcpyMenuView] Showing file transfer progress popup");

    UIWindow *window = [self activeWindow];
    if (!window) return;

    // Initialize dictionaries
    self.fileProgressViews = [NSMutableDictionary dictionary];
    self.fileStatusLabels = [NSMutableDictionary dictionary];

    // Calculate popup size
    CGFloat popupWidth = 320.0;
    CGFloat rowHeight = 60.0;
    CGFloat headerHeight = 50.0;
    CGFloat cancelButtonHeight = 50.0;
    CGFloat padding = 16.0;
    CGFloat maxContentHeight = MIN(self.pendingFileURLs.count * rowHeight, 300.0);
    CGFloat popupHeight = headerHeight + maxContentHeight + cancelButtonHeight + padding * 2;

    // Create popup container
    self.fileTransferPopupView = [[UIView alloc] init];
    self.fileTransferPopupView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.95];
    self.fileTransferPopupView.layer.cornerRadius = 16.0;
    self.fileTransferPopupView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.fileTransferPopupView.layer.shadowOffset = CGSizeMake(0, 4);
    self.fileTransferPopupView.layer.shadowOpacity = 0.4;
    self.fileTransferPopupView.layer.shadowRadius = 10.0;

    // Center the popup
    CGFloat popupX = (window.bounds.size.width - popupWidth) / 2;
    CGFloat popupY = (window.bounds.size.height - popupHeight) / 2;
    self.fileTransferPopupView.frame = CGRectMake(popupX, popupY, popupWidth, popupHeight);

    // Header label
    self.fileTransferHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, padding, popupWidth - padding * 2, 30)];
    self.fileTransferHeaderLabel.text = [NSString stringWithFormat:@"📤 Sending %lu file(s)...", (unsigned long)self.pendingFileURLs.count];
    self.fileTransferHeaderLabel.textColor = [UIColor whiteColor];
    self.fileTransferHeaderLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
    self.fileTransferHeaderLabel.textAlignment = NSTextAlignmentCenter;
    [self.fileTransferPopupView addSubview:self.fileTransferHeaderLabel];

    // Scroll view for file list
    self.fileTransferScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(padding, headerHeight, popupWidth - padding * 2, maxContentHeight)];
    self.fileTransferScrollView.showsVerticalScrollIndicator = YES;
    [self.fileTransferPopupView addSubview:self.fileTransferScrollView];

    // Add file rows
    CGFloat yOffset = 0;
    for (NSInteger i = 0; i < (NSInteger)self.pendingFileURLs.count; i++) {
        NSURL *fileURL = self.pendingFileURLs[i];
        NSString *fileName = fileURL.lastPathComponent;
        NSString *fileKey = [NSString stringWithFormat:@"%ld", (long)i];

        // File row container
        UIView *rowView = [[UIView alloc] initWithFrame:CGRectMake(0, yOffset, self.fileTransferScrollView.bounds.size.width, rowHeight - 4)];

        // File name label
        UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 4, rowView.bounds.size.width, 22)];
        nameLabel.text = fileName;
        nameLabel.textColor = [UIColor whiteColor];
        nameLabel.font = [UIFont systemFontOfSize:14.0];
        nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [rowView addSubview:nameLabel];

        // Progress view
        UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        progressView.frame = CGRectMake(0, 30, rowView.bounds.size.width, 4);
        progressView.progressTintColor = [UIColor systemBlueColor];
        progressView.trackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3];
        progressView.progress = 0.0;
        [rowView addSubview:progressView];
        self.fileProgressViews[fileKey] = progressView;

        // Status label
        UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 38, rowView.bounds.size.width, 18)];
        statusLabel.text = @"Waiting...";
        statusLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
        statusLabel.font = [UIFont systemFontOfSize:12.0];
        [rowView addSubview:statusLabel];
        self.fileStatusLabels[fileKey] = statusLabel;

        [self.fileTransferScrollView addSubview:rowView];
        yOffset += rowHeight;
    }
    self.fileTransferScrollView.contentSize = CGSizeMake(self.fileTransferScrollView.bounds.size.width, yOffset);

    // Cancel/Close button (capsule shape)
    CGFloat cancelButtonWidth = 120.0;
    self.fileTransferCloseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.fileTransferCloseButton.frame = CGRectMake((popupWidth - cancelButtonWidth) / 2, popupHeight - cancelButtonHeight - padding + 8, cancelButtonWidth, 36);
    self.fileTransferCloseButton.backgroundColor = [UIColor systemRedColor];
    self.fileTransferCloseButton.layer.cornerRadius = 18.0;
    [self.fileTransferCloseButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [self.fileTransferCloseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.fileTransferCloseButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    [self.fileTransferCloseButton addTarget:self action:@selector(cancelFileTransfer) forControlEvents:UIControlEventTouchUpInside];
    [self.fileTransferPopupView addSubview:self.fileTransferCloseButton];

    // Initial state
    self.fileTransferPopupView.alpha = 0.0;
    self.fileTransferPopupView.transform = CGAffineTransformMakeScale(0.9, 0.9);

    [window addSubview:self.fileTransferPopupView];

    // Animate in
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
        self.fileTransferPopupView.alpha = 1.0;
        self.fileTransferPopupView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hideFileTransferProgress {
    if (!self.fileTransferPopupView) return;

    [UIView animateWithDuration:0.2 animations:^{
        self.fileTransferPopupView.alpha = 0.0;
        self.fileTransferPopupView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [self.fileTransferPopupView removeFromSuperview];
        self.fileTransferPopupView = nil;
        self.fileTransferScrollView = nil;
        self.fileProgressViews = nil;
        self.fileStatusLabels = nil;
        self.pendingFileURLs = nil;
        self.fileTransferCloseButton = nil;
        self.fileTransferHeaderLabel = nil;
    }];
}

- (void)cancelFileTransfer {
    NSLog(@"❌ [ScrcpyMenuView] File transfer cancelled by user");
    self.isFileTransferCancelled = YES;
    [self hideFileTransferProgress];
}

- (void)updateFileProgress:(NSInteger)fileIndex progress:(float)progress status:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *fileKey = [NSString stringWithFormat:@"%ld", (long)fileIndex];
        UIProgressView *progressView = self.fileProgressViews[fileKey];
        UILabel *statusLabel = self.fileStatusLabels[fileKey];

        if (progressView) {
            [progressView setProgress:progress animated:YES];
        }
        if (statusLabel) {
            statusLabel.text = status;
            if ([status containsString:@"Complete"]) {
                statusLabel.textColor = [UIColor systemGreenColor];
            } else if ([status containsString:@"Failed"] || [status containsString:@"Cancelled"]) {
                statusLabel.textColor = [UIColor systemRedColor];
            }
        }
    });
}

#pragma mark - ADB File Transfer

- (void)startFileTransfer {
    if (self.isFileTransferCancelled) {
        return;
    }

    if (self.currentTransferIndex >= (NSInteger)self.pendingFileURLs.count) {
        NSLog(@"✅ [ScrcpyMenuView] All files transfer attempts completed");
        // Update UI to show completion state
        [self updateFileTransferCompletionUI];
        return;
    }

    NSURL *fileURL = self.pendingFileURLs[self.currentTransferIndex];
    [self transferFile:fileURL atIndex:self.currentTransferIndex];
}

- (void)updateFileTransferCompletionUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Update header
        if (self.hasFileTransferError) {
            self.fileTransferHeaderLabel.text = @"⚠️ Transfer Complete (with errors)";
            self.fileTransferHeaderLabel.textColor = [UIColor systemOrangeColor];
        } else {
            self.fileTransferHeaderLabel.text = @"✅ Transfer Complete";
            self.fileTransferHeaderLabel.textColor = [UIColor systemGreenColor];
        }

        // Update button to "Close" with appropriate color
        [UIView animateWithDuration:0.2 animations:^{
            [self.fileTransferCloseButton setTitle:@"Close" forState:UIControlStateNormal];
            self.fileTransferCloseButton.backgroundColor = self.hasFileTransferError ?
                [UIColor systemOrangeColor] : [UIColor systemGreenColor];
        }];
    });
}

- (void)transferFile:(NSURL *)fileURL atIndex:(NSInteger)index {
    NSLog(@"📤 [ScrcpyMenuView] Transferring file %ld: %@", (long)index, fileURL.lastPathComponent);

    // Update status to "Transferring..."
    [self updateFileProgress:index progress:0.1 status:@"Transferring..."];

    // Start security-scoped access
    BOOL accessGranted = [fileURL startAccessingSecurityScopedResource];
    if (!accessGranted) {
        NSLog(@"⚠️ [ScrcpyMenuView] Could not access security scoped resource");
    }

    // Get file path
    NSString *localPath = fileURL.path;
    NSString *fileName = fileURL.lastPathComponent;
    NSString *remotePath = [NSString stringWithFormat:@"/sdcard/Download/%@", fileName];

    NSLog(@"📤 [ScrcpyMenuView] ADB push: %@ -> %@", localPath, remotePath);

    // Build ADB push command (no need for -s flag, ADB uses the connected device)
    NSArray *command = @[@"push", localPath, remotePath];

    // Execute ADB command asynchronously
    __weak typeof(self) weakSelf = self;
    [[ADBClient shared] executeADBCommandAsync:command callback:^(NSString * _Nullable output, int returnCode) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // Stop security-scoped access
        if (accessGranted) {
            [fileURL stopAccessingSecurityScopedResource];
        }

        if (strongSelf.isFileTransferCancelled) {
            [strongSelf updateFileProgress:index progress:0.0 status:@"Cancelled"];
            return;
        }

        if (returnCode == 0) {
            NSLog(@"✅ [ScrcpyMenuView] File transferred successfully: %@", fileName);
            NSString *successStatus = [NSString stringWithFormat:@"✓ %@", remotePath];
            [strongSelf updateFileProgress:index progress:1.0 status:successStatus];
        } else {
            NSLog(@"❌ [ScrcpyMenuView] File transfer failed: %@ - %@", fileName, output);
            strongSelf.hasFileTransferError = YES;
            NSString *errorStatus = [NSString stringWithFormat:@"✗ %@", output ?: @"Unknown error"];
            if (errorStatus.length > 50) {
                errorStatus = [[errorStatus substringToIndex:47] stringByAppendingString:@"..."];
            }
            [strongSelf updateFileProgress:index progress:0.0 status:errorStatus];
        }

        // Transfer next file
        [strongSelf transferNextFile];
    }];

    // Simulate progress while waiting (since ADB doesn't provide progress)
    [self simulateProgressForFile:index];
}

- (void)simulateProgressForFile:(NSInteger)index {
    // Simulate progress updates while waiting for transfer
    __weak typeof(self) weakSelf = self;
    __block float progress = 0.1;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (progress < 0.9) {
            if (weakSelf.isFileTransferCancelled) break;
            if (weakSelf.currentTransferIndex != index) break;

            usleep(200000); // 200ms
            progress += 0.05;
            if (progress > 0.9) progress = 0.9;

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf || strongSelf.isFileTransferCancelled) return;
                if (strongSelf.currentTransferIndex != index) return;

                NSString *fileKey = [NSString stringWithFormat:@"%ld", (long)index];
                UIProgressView *progressView = strongSelf.fileProgressViews[fileKey];
                UILabel *statusLabel = strongSelf.fileStatusLabels[fileKey];
                if (progressView && statusLabel && [statusLabel.text isEqualToString:@"Transferring..."]) {
                    [progressView setProgress:progress animated:YES];
                }
            });
        }
    });
}

- (void)transferNextFile {
    self.currentTransferIndex++;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startFileTransfer];
    });
}

@end 

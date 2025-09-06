//
//  SDL_uikitviewcontroller+Extend.m
//  Scrcpy Remote
//
//  Created by Ethan on 1/4/25.
//

#import "SDL_uikitviewcontroller+Extend.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <SDL2/SDL_events.h>
#import <SDL2/SDL_system.h>
#import "ScrcpyClientWrapper.h"
#import "ADBClient.h"
#import "ScrcpyADBClient.h"
#import "ScrcpyRuntime.h"
#import "ScrcpyMenuView.h"
#import "ScrcpyInputMaskView.h"
#import "ScrcpyCommon.h"
#import "Scrcpy_Remote-Swift.h"

@interface SDL_uikitviewcontroller () <ScrcpyMenuViewDelegate>
@property (nonatomic, assign)   NSInteger  homeIndicatorHidden;
@end

@implementation SDL_uikitviewcontroller (Extend)

// Key for menuView associated object
static char menuViewKey;
static char inputMaskViewKey;

// Getter for menuView
- (ScrcpyMenuView *)menuView {
    return objc_getAssociatedObject(self, &menuViewKey);
}

// Setter for menuView
- (void)setMenuView:(ScrcpyMenuView *)menuView {
    objc_setAssociatedObject(self, &menuViewKey, menuView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Getter for inputMaskView
- (ScrcpyInputMaskView *)inputMaskView {
    return objc_getAssociatedObject(self, &inputMaskViewKey);
}

// Setter for inputMaskView
- (void)setInputMaskView:(ScrcpyInputMaskView *)inputMaskView {
    objc_setAssociatedObject(self, &inputMaskViewKey, inputMaskView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    // Update video layer frame
    for (CALayer *layer in self.view.layer.sublayers) {
        if ([layer isKindOfClass:AVSampleBufferDisplayLayer.class]) {
            layer.frame = self.view.bounds;
        }
    }
    
    // Update menu view layout if it exists
    if (self.menuView) {
        [self.menuView updateLayout];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // Initialize the ScrappyMenuView with appropriate size
    __weak typeof(self) weakSelf = self;
    self.menuView = [[ScrcpyMenuView alloc] initWithFrame:CGRectZero]; // Frame will be set correctly during initialization
    self.menuView.delegate = weakSelf;
    
    // 根据当前连接的设备类型配置菜单
    [self configureMenuForCurrentDeviceType];
    
    [self.menuView addToActiveWindow];
    
    // 监听键盘显示和隐藏的通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

-(void)viewWillUnload
{
    [super viewWillUnload];
    
    self.homeIndicatorHidden = 0;
    [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    NSLog(@"Reset ViewControllers HomeIndicatorAutoHidden.");
}

- (void)dealloc
{
    // 移除通知观察者
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Keyboard Notifications

- (void)keyboardWillShow:(NSNotification *)notification {
    // 当键盘显示时，创建并显示输入遮罩视图
    if (!self.inputMaskView) {
        self.inputMaskView = [[ScrcpyInputMaskView alloc] initWithFrame:self.view.bounds];
    }
    [self.inputMaskView showInView:self.view];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    // 当键盘隐藏时，移除输入遮罩视图
    [self.inputMaskView hide];
}

#pragma mark - Menu Configuration

- (void)configureMenuForCurrentDeviceType {
    // 获取当前设备类型
    SessionConnectionManager *connectionManager = [SessionConnectionManager shared];
    NSString *deviceTypeString = [connectionManager getCurrentDeviceType];
    
    // 使用便利方法转换设备类型
    ScrcpyDeviceType deviceType = [ScrcpyMenuView deviceTypeFromString:deviceTypeString];
    
    // 记录日志
    if (deviceTypeString) {
        NSLog(@"🎛️ [SDL_uikitviewcontroller] Configuring menu for %@ device", deviceTypeString);
    } else {
        NSLog(@"⚠️ [SDL_uikitviewcontroller] No current device type found, using ADB default");
    }
    
    // 配置菜单视图
    [self.menuView configureForDeviceType:deviceType];
}

#pragma mark - ScrappyMenuViewDelegate

- (void)didTapBackButton {
    // 发送 Back 按键事件 (Ctrl+B)
    ScrcpySendKeycodeEvent(SDL_SCANCODE_B, SDLK_b, KMOD_LCTRL);
}

- (void)didTapHomeButton {
    // 发送 Home 按键事件 (Ctrl+H)
    ScrcpySendKeycodeEvent(SDL_SCANCODE_H, SDLK_h, KMOD_LCTRL);
}

- (void)didTapSwitchButton {
    // 发送 Switch 按键事件 (Ctrl+S)
    ScrcpySendKeycodeEvent(SDL_SCANCODE_S, SDLK_s, KMOD_LCTRL);
}

- (void)didTapKeyboardButton {
    // Toggle keyboard
    SDL_StartTextInput();
}

- (void)didTapActionsButton {
    // 显示功能开发中的提示
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Actions", @"Actions title") 
                                                                   message:NSLocalizedString(@"This feature is under development, please wait.", @"WIP message") 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK button") 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    
    [alert addAction:okAction];
    
    // 在主线程中显示Alert
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)didTapDisconnectButton {
    // Post notification to disconnect
    [[NSNotificationCenter defaultCenter] postNotificationName:ScrcpyRequestDisconnectNotification object:nil];
}

#pragma mark - VNC Zoom Delegate Methods

- (void)didPinchWithScale:(CGFloat)scale {
    NSLog(@"🔍 [SDL_uikitviewcontroller] VNC pinch with scale: %.2f", scale);
    
    // 发送VNC缩放通知给VNCClient处理
    NSDictionary *userInfo = @{
        @"scale": @(scale),
        @"centerX": @(0.5), // 默认屏幕中心，后续可改为实际触摸中心
        @"centerY": @(0.5),
        @"isFinished": @(NO)
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyVNCZoomNotification" object:nil userInfo:userInfo];
}

- (void)didPinchWithScale:(CGFloat)scale centerX:(CGFloat)centerX centerY:(CGFloat)centerY {
    NSLog(@"🔍 [SDL_uikitviewcontroller] VNC pinch with scale: %.2f, center: (%.3f, %.3f)", scale, centerX, centerY);
    
    // 发送VNC缩放通知给VNCClient处理（包含实际触摸中心点）
    NSDictionary *userInfo = @{
        @"scale": @(scale),
        @"centerX": @(centerX),
        @"centerY": @(centerY),
        @"isFinished": @(NO)
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyVNCZoomNotification" object:nil userInfo:userInfo];
}

- (void)didPinchEndWithFinalScale:(CGFloat)finalScale {
    NSLog(@"🔍 [SDL_uikitviewcontroller] VNC pinch ended with final scale: %.2f", finalScale);
    
    // 发送VNC缩放结束通知给VNCClient处理
    NSDictionary *userInfo = @{
        @"scale": @(finalScale),
        @"centerX": @(0.5), // 默认屏幕中心，后续可改为实际触摸中心
        @"centerY": @(0.5),
        @"isFinished": @(YES)
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyVNCZoomNotification" object:nil userInfo:userInfo];
}

- (void)didPinchEndWithFinalScale:(CGFloat)finalScale centerX:(CGFloat)centerX centerY:(CGFloat)centerY {
    NSLog(@"🔍 [SDL_uikitviewcontroller] VNC pinch ended with final scale: %.2f, center: (%.3f, %.3f)", finalScale, centerX, centerY);
    
    // 发送VNC缩放结束通知给VNCClient处理（包含实际触摸中心点）
    NSDictionary *userInfo = @{
        @"scale": @(finalScale),
        @"centerX": @(centerX),
        @"centerY": @(centerY),
        @"isFinished": @(YES)
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyVNCZoomNotification" object:nil userInfo:userInfo];
}

#pragma mark - VNC Drag Gesture Delegate

- (void)didDragWithState:(NSString *)state location:(CGPoint)location viewSize:(CGSize)viewSize {
    NSLog(@"🎯 [SDL_uikitviewcontroller] VNC drag - state: %@, location: (%.1f, %.1f), viewSize: (%.1f, %.1f)", 
          state, location.x, location.y, viewSize.width, viewSize.height);
    
    // 发送VNC拖拽通知给VNCClient处理
    NSDictionary *userInfo = @{
        @"state": state,
        @"location": [NSValue valueWithCGPoint:location],
        @"viewSize": [NSValue valueWithCGSize:viewSize]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScrcpyVNCDragNotification" object:nil userInfo:userInfo];
}

@end

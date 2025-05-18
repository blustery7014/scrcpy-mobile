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
#import "ScrcpyMenuView.h"
#import "ScrcpyInputMaskView.h"

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
    self.menuView = [[ScrcpyMenuView alloc] initWithFrame:CGRectMake(0, 0, 60, 20)];
    self.menuView.delegate = weakSelf;
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
    // Show custom actions menu
}

- (void)didTapDisconnectButton {
    // Post notification to disconnect
    [[NSNotificationCenter defaultCenter] postNotificationName:ScrcpyRequestDisconnectNotification object:nil];
}

@end

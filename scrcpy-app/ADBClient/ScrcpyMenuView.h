#import <UIKit/UIKit.h>
#import <SDL2/SDL.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ScrcpyMenuViewDelegate <NSObject>

@optional
// 原有的代理方法
- (void)didTapBackButton;
- (void)didTapHomeButton;
- (void)didTapSwitchButton;
- (void)didTapKeyboardButton;
- (void)didTapActionsButton;
- (void)didTapDisconnectButton;

@end

@interface ScrcpyMenuView : UIView

@property (nonatomic, weak) id<ScrcpyMenuViewDelegate> delegate;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)addToActiveWindow;
- (void)updateLayout;

@end

NS_ASSUME_NONNULL_END 

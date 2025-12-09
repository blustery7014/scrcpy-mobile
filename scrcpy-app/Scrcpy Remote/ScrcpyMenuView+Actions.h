//
//  ScrcpyMenuView+Actions.h
//  Scrcpy Remote
//
//  Actions popup menu category for ScrcpyMenuView
//

#import "ScrcpyMenuView.h"

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyMenuView (Actions) <UITableViewDataSource, UITableViewDelegate>

// Actions Menu
- (void)showActionsMenu;
- (void)hideActionsMenu;

// UI Helpers
- (UIImage *)imageWithIcon:(UIImage *)icon inSize:(CGSize)size;

@end

NS_ASSUME_NONNULL_END

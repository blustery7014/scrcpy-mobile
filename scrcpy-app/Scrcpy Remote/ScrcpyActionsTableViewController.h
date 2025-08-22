//
//  ScrcpyActionsTableViewController.h
//  Scrcpy Remote
//
//  Created by Claude on 7/16/25.
//  Actions table view controller for managing device actions
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyActionsTableViewController : UITableViewController

/// Initialize with actions automatically loaded for current device
- (instancetype)init;

/// Reload actions from the current device
- (void)reloadActions;

@end

NS_ASSUME_NONNULL_END
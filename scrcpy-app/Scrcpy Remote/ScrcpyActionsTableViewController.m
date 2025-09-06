//
//  ScrcpyActionsTableViewController.m
//  Scrcpy Remote
//
//  Created by Claude on 7/16/25.
//  Actions table view controller for managing device actions
//

#import "ScrcpyActionsTableViewController.h"
#import "ScrcpyActionsBridge.h"

@interface ScrcpyActionsTableViewController ()

@property (nonatomic, strong) NSArray<ScrcpyActionData *> *actions;
@property (nonatomic, strong) ScrcpyActionsBridge *actionsBridge;

@end

@implementation ScrcpyActionsTableViewController

#pragma mark - Initialization

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = @"Actions";
        self.actionsBridge = [ScrcpyActionsBridge shared];
        [self loadActions];
        [self setupNavigationItems];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSLog(@"🔥 [ScrcpyActionsTableViewController] viewDidLoad called");
    
    // Ensure delegate and dataSource are set (UITableViewController should do this automatically, but let's be sure)
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    // Configure table view
    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    
    // Make sure user interaction is enabled
    self.tableView.userInteractionEnabled = YES;
    self.tableView.allowsSelection = YES;
    
    NSLog(@"🔥 [ScrcpyActionsTableViewController] Table view delegate: %@, dataSource: %@", 
          self.tableView.delegate, self.tableView.dataSource);
    NSLog(@"🔥 [ScrcpyActionsTableViewController] Table view interaction enabled: %@, selection allowed: %@", 
          self.tableView.userInteractionEnabled ? @"YES" : @"NO",
          self.tableView.allowsSelection ? @"YES" : @"NO");
    
    // Register cell class
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ActionCell"];
}

#pragma mark - Setup

- (void)setupNavigationItems {
    // Close button
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithTitle:@"Close"
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(closeButtonTapped:)];
    self.navigationItem.leftBarButtonItem = closeButton;
    
    // Refresh button
    UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                   target:self
                                                                                   action:@selector(refreshButtonTapped:)];
    self.navigationItem.rightBarButtonItem = refreshButton;
}

#pragma mark - Actions Loading

- (void)loadActions {
    NSLog(@"🔥 [ScrcpyActionsTableViewController] Loading actions for current device");
    
    self.actions = [self.actionsBridge getActionsForCurrentDevice];
    
    NSLog(@"🔥 [ScrcpyActionsTableViewController] Loaded %lu actions", (unsigned long)self.actions.count);
    
    for (NSUInteger i = 0; i < self.actions.count; i++) {
        ScrcpyActionData *action = self.actions[i];
        NSLog(@"🔥 [ScrcpyActionsTableViewController] Action %lu: %@ (ID: %@)", i, action.name, action.actionId);
    }
    
    // Update UI on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"🔥 [ScrcpyActionsTableViewController] Reloading table data on main thread");
        [self.tableView reloadData];
        [self updateEmptyState];
    });
}

- (void)reloadActions {
    [self loadActions];
}

- (void)updateEmptyState {
    if (self.actions.count == 0) {
        [self showEmptyState];
    } else {
        [self hideEmptyState];
    }
}

- (void)showEmptyState {
    UILabel *emptyLabel = [[UILabel alloc] init];
    emptyLabel.text = @"No actions available for current device";
    emptyLabel.textColor = [UIColor secondaryLabelColor];
    emptyLabel.font = [UIFont systemFontOfSize:16];
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    emptyLabel.numberOfLines = 0;
    
    UIView *emptyView = [[UIView alloc] init];
    [emptyView addSubview:emptyLabel];
    
    emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [emptyLabel.centerXAnchor constraintEqualToAnchor:emptyView.centerXAnchor],
        [emptyLabel.centerYAnchor constraintEqualToAnchor:emptyView.centerYAnchor],
        [emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:emptyView.leadingAnchor constant:20],
        [emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:emptyView.trailingAnchor constant:-20]
    ]];
    
    self.tableView.backgroundView = emptyView;
}

- (void)hideEmptyState {
    self.tableView.backgroundView = nil;
}

#pragma mark - Actions

- (void)closeButtonTapped:(UIBarButtonItem *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)refreshButtonTapped:(UIBarButtonItem *)sender {
    [self reloadActions];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSLog(@"🔥 [ScrcpyActionsTableViewController] numberOfRowsInSection called, returning: %lu", (unsigned long)self.actions.count);
    return self.actions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"🔥 [ScrcpyActionsTableViewController] cellForRowAtIndexPath called for row: %ld", (long)indexPath.row);
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActionCell" forIndexPath:indexPath];
    
    if (indexPath.row >= self.actions.count) {
        NSLog(@"❌ [ScrcpyActionsTableViewController] ERROR: IndexPath.row (%ld) >= actions.count (%lu) in cellForRowAtIndexPath", (long)indexPath.row, (unsigned long)self.actions.count);
        return cell;
    }
    
    ScrcpyActionData *action = self.actions[indexPath.row];
    NSLog(@"🔥 [ScrcpyActionsTableViewController] Configuring cell for action: %@", action.name);
    
    // Configure cell appearance
    [self configureCell:cell withAction:action];
    
    // Ensure cell is selectable
    cell.userInteractionEnabled = YES;
    
    return cell;
}

- (void)configureCell:(UITableViewCell *)cell withAction:(ScrcpyActionData *)action {
    // Main text
    cell.textLabel.text = action.name;
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.textLabel.textColor = [UIColor labelColor];
    
    // Detail text with device type and timing
    NSString *deviceTypeText = action.deviceType;
    NSString *timingText = [self displayTextForExecutionTiming:action.executionTiming];
    
    NSMutableString *detailText = [NSMutableString stringWithFormat:@"%@ • %@", deviceTypeText, timingText];
    
    // Add delay info for delayed actions
    if ([action.executionTiming isEqualToString:@"delayed"]) {
        [detailText appendFormat:@" (%lds)", (long)action.delaySeconds];
    }
    
    cell.detailTextLabel.text = detailText;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    
    // Configure cell style
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    // Device type icon
    NSString *iconName = [self iconNameForDeviceType:action.deviceType];
    if (iconName) {
        UIImage *icon = [UIImage systemImageNamed:iconName];
        if (icon) {
            cell.imageView.image = icon;
            cell.imageView.tintColor = [self colorForDeviceType:action.deviceType];
        }
    }
}

- (NSString *)displayTextForExecutionTiming:(NSString *)timing {
    if ([timing isEqualToString:@"immediate"]) {
        return @"Execute Immediately";
    } else if ([timing isEqualToString:@"delayed"]) {
        return @"Execute After Delay";
    } else {
        return @"Wait for Confirmation";
    }
}

- (NSString *)iconNameForDeviceType:(NSString *)deviceType {
    if ([deviceType isEqualToString:@"VNC"]) {
        return @"desktopcomputer";
    } else if ([deviceType isEqualToString:@"ADB"]) {
        return @"smartphone";
    }
    return @"questionmark.circle";
}

- (UIColor *)colorForDeviceType:(NSString *)deviceType {
    if ([deviceType isEqualToString:@"VNC"]) {
        return [UIColor systemBlueColor];
    } else if ([deviceType isEqualToString:@"ADB"]) {
        return [UIColor systemGreenColor];
    }
    return [UIColor systemGrayColor];
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"🔥 [ScrcpyActionsTableViewController] didSelectRowAtIndexPath called! Row: %ld, Section: %ld", (long)indexPath.row, (long)indexPath.section);
    NSLog(@"🔥 [ScrcpyActionsTableViewController] Actions array count: %lu", (unsigned long)self.actions.count);
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.row >= self.actions.count) {
        NSLog(@"❌ [ScrcpyActionsTableViewController] ERROR: IndexPath.row (%ld) >= actions.count (%lu)", (long)indexPath.row, (unsigned long)self.actions.count);
        return;
    }
    
    ScrcpyActionData *action = self.actions[indexPath.row];
    NSLog(@"🔥 [ScrcpyActionsTableViewController] Selected action: %@", action.name);
    [self executeAction:action];
}

#pragma mark - Action Execution

- (void)executeAction:(ScrcpyActionData *)action {
    NSLog(@"[ScrcpyActionsTableViewController] Executing action: %@", action.name);
    NSLog(@"[ScrcpyActionsTableViewController] Action details - ID: %@, DeviceType: %@, Timing: %@", 
          action.actionId, action.deviceType, action.executionTiming);
    
    // Show loading indicator
    [self showLoadingForAction:action];
    
    // Execute action through bridge
    [self.actionsBridge executeAction:action
                       statusCallback:^(NSInteger status, NSString * _Nullable message, BOOL isConnecting) {
                           dispatch_async(dispatch_get_main_queue(), ^{
                               [self handleStatusUpdate:status message:message isConnecting:isConnecting];
                           });
                       }
                        errorCallback:^(NSString *title, NSString *message) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [self handleError:title message:message];
                            });
                        }
                confirmationCallback:^(ScrcpyActionData *confirmAction, void (^confirmCallback)(void)) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self showConfirmationForAction:confirmAction completion:confirmCallback];
                    });
                }];
}

- (void)showLoadingForAction:(ScrcpyActionData *)action {
    // Could show a loading indicator or progress HUD here
    NSLog(@"[ScrcpyActionsTableViewController] Starting execution for action: %@", action.name);
}

- (void)handleStatusUpdate:(NSInteger)status message:(NSString *)message isConnecting:(BOOL)isConnecting {
    NSLog(@"[ScrcpyActionsTableViewController] Status update - Status: %ld, Message: %@, Connecting: %@", 
          (long)status, message ?: @"(nil)", isConnecting ? @"YES" : @"NO");
    
    // Handle status updates (could show progress, update UI, etc.)
    if (message) {
        // Could show a toast or update status label
        // For now, show an alert to make sure we see the status
        UIAlertController *statusAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Status Update", @"Status update alert title")
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK button")
                                                           style:UIAlertActionStyleDefault
                                                         handler:nil];
        [statusAlert addAction:okAction];
        
        [self presentViewController:statusAlert animated:YES completion:nil];
    }
}

- (void)handleError:(NSString *)title message:(NSString *)message {
    NSLog(@"[ScrcpyActionsTableViewController] Error - Title: %@, Message: %@", title, message);
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK button")
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showConfirmationForAction:(ScrcpyActionData *)action completion:(void (^)(void))completion {
    NSLog(@"[ScrcpyActionsTableViewController] Showing confirmation for action: %@", action.name);
    NSLog(@"[ScrcpyActionsTableViewController] Action details for confirmation - ID: %@, Type: %@, Timing: %@", 
          action.actionId, action.deviceType, action.executionTiming);
    
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to execute '%@'?\n\nAction ID: %@\nDevice Type: %@\nTiming: %@", @"Confirmation message with details"), 
                         action.name, action.actionId, action.deviceType, action.executionTiming];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Confirm Action", @"Confirm action alert title")
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *executeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Execute", @"Execute button")
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * _Nonnull alertAction) {
                                                             NSLog(@"[ScrcpyActionsTableViewController] User confirmed action execution");
                                                             completion();
                                                         }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil];
    
    [alert addAction:executeAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end

//
//  ScrcpyActionsBridge.m
//  Scrcpy Remote
//
//  Created by Claude on 7/15/25.
//  Bridge for accessing Swift ActionManager and SessionConnectionManager from Objective-C
//

#import "ScrcpyActionsBridge.h"
#import "ScrcpyCommon.h"
#import "scrcpy-porting.h"
#import "Scrcpy_Remote-Swift.h"

@implementation ScrcpyActionData
@end

@implementation ScrcpyActionsBridge

+ (instancetype)shared {
    static ScrcpyActionsBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

#pragma mark - ActionManager Bridge Methods

- (NSArray<ScrcpyActionData *> *)getActionsForCurrentDevice {
    NSLog(@"[ScrcpyActionsBridge] getActionsForCurrentDevice called");
    
    // Get current session
    SessionConnectionManager *connectionManager = [SessionConnectionManager shared];
    ScrcpySessionModel *currentSession = connectionManager.currentSession;
    
    if (!currentSession) {
        NSLog(@"[ScrcpyActionsBridge] No current session found");
        return @[];
    }
    
    if (!currentSession.id) {
        NSLog(@"[ScrcpyActionsBridge] Current session exists but has no ID");
        return @[];
    }
    
    NSLog(@"[ScrcpyActionsBridge] Current session deviceId: %@", currentSession.deviceId.UUIDString);
    
    NSArray<ScrcpyActionData *> *actions = [self getActionsForDeviceId:currentSession.deviceId.UUIDString];
    NSLog(@"[ScrcpyActionsBridge] Found %lu actions for current device", (unsigned long)actions.count);
    
    return actions;
}

- (NSArray<ScrcpyActionData *> *)getActionsForDeviceId:(NSString *)deviceId {
    NSLog(@"[ScrcpyActionsBridge] getActionsForDeviceId called with deviceId: %@", deviceId);
    
    // Get ActionManager
    ActionManager *actionManager = [ActionManager shared];
    NSLog(@"[ScrcpyActionsBridge] ActionManager obtained: %@", actionManager);
    
    // Convert string to UUID
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:deviceId];
    if (!uuid) {
        NSLog(@"[ScrcpyActionsBridge] Failed to create UUID from deviceId: %@", deviceId);
        return @[];
    }
    
    // Get actions for device
    NSArray<ScrcpyAction *> *actions = [actionManager getActionsFor:uuid];
    NSLog(@"[ScrcpyActionsBridge] Swift actions retrieved: %lu actions", (unsigned long)actions.count);
    
    // Convert Swift ScrcpyAction objects to Objective-C ScrcpyActionData objects
    NSMutableArray<ScrcpyActionData *> *actionDataArray = [NSMutableArray array];
    
    for (ScrcpyAction *action in actions) {
        NSLog(@"[ScrcpyActionsBridge] Converting action: %@ (ID: %@)", action.name, action.id.UUIDString);
        ScrcpyActionData *actionData = [[ScrcpyActionData alloc] init];
        actionData.actionId = action.id.UUIDString;
        actionData.name = action.name;
        
        // Convert device type using intValue
        actionData.deviceType = (action.deviceTypeIntValue == 0) ? @"VNC" : @"ADB";
        
        // Convert execution timing using intValue
        switch (action.executionTimingIntValue) {
            case 1: // immediate
                actionData.executionTiming = @"immediate";
                break;
            case 2: // delayed
                actionData.executionTiming = @"delayed";
                break;
            case 0: // confirmation
            default:
                actionData.executionTiming = @"confirmation";
                break;
        }
        
        actionData.delaySeconds = action.delaySeconds;
        
        [actionDataArray addObject:actionData];
    }
    
    NSLog(@"[ScrcpyActionsBridge] Converted %lu actions to ScrcpyActionData objects", (unsigned long)actionDataArray.count);
    return [actionDataArray copy];
}

- (BOOL)hasActionsForCurrentDevice {
    NSArray<ScrcpyActionData *> *actions = [self getActionsForCurrentDevice];
    return actions.count > 0;
}

#pragma mark - SessionConnectionManager Bridge Methods

- (BOOL)hasActiveSession {
    SessionConnectionManager *connectionManager = [SessionConnectionManager shared];
    return connectionManager.currentSession != nil;
}

- (NSString * _Nullable)getCurrentSessionId {
    SessionConnectionManager *connectionManager = [SessionConnectionManager shared];
    ScrcpySessionModel *currentSession = connectionManager.currentSession;
    return currentSession ? currentSession.id.UUIDString : nil;
}

- (NSString * _Nullable)getCurrentDeviceType {
    SessionConnectionManager *connectionManager = [SessionConnectionManager shared];
    return [connectionManager getCurrentDeviceType];
}

#pragma mark - Action Execution Methods

- (void)executeAction:(ScrcpyActionData *)actionData
       statusCallback:(ScrcpyActionStatusCallback)statusCallback
        errorCallback:(ScrcpyActionErrorCallback)errorCallback
confirmationCallback:(ScrcpyActionConfirmationCallback _Nullable)confirmationCallback {
    
    NSLog(@"[ScrcpyActionsBridge] executeAction called with action: %@ (ID: %@)", actionData.name, actionData.actionId);
    
    // Get ActionManager and find the original ScrcpyAction
    ActionManager *actionManager = [ActionManager shared];
    NSLog(@"[ScrcpyActionsBridge] ActionManager retrieved: %@", actionManager);
    
    NSUUID *actionId = [[NSUUID alloc] initWithUUIDString:actionData.actionId];
    
    if (!actionId) {
        errorCallback(@"Invalid Action", @"Action ID is invalid");
        return;
    }
    
    ScrcpyAction *action = [actionManager getActionBy:actionId];
    NSLog(@"[ScrcpyActionsBridge] Action retrieved from ActionManager: %@", action);
    if (!action) {
        NSLog(@"[ScrcpyActionsBridge] ERROR: Action not found for ID: %@", actionId.UUIDString);
        errorCallback(@"Action Not Found", @"The specified action could not be found");
        return;
    }
    
    // Get current session
    SessionConnectionManager *connectionManager = [SessionConnectionManager shared];
    ScrcpySessionModel *currentSession = connectionManager.currentSession;
    NSLog(@"[ScrcpyActionsBridge] Current session: %@", currentSession);
    
    if (!currentSession) {
        errorCallback(@"No Active Session", @"No active session found. Please connect to a device first.");
        return;
    }
    
    // Create Swift callback blocks
    void (^swiftStatusCallback)(enum ScrcpyStatus, NSString *, BOOL) = ^(enum ScrcpyStatus status, NSString *message, BOOL isConnecting) {
        statusCallback((NSInteger)status, message, isConnecting);
    };
    
    void (^swiftErrorCallback)(NSString *, NSString *) = ^(NSString *title, NSString *message) {
        errorCallback(title, message);
    };
    
    void (^swiftConfirmationCallback)(ScrcpyAction *, void (^)(void)) = nil;
    if (confirmationCallback) {
        swiftConfirmationCallback = ^(ScrcpyAction *confirmAction, void (^confirmCallback)(void)) {
            // Convert Swift action back to Objective-C action data
            ScrcpyActionData *confirmActionData = [[ScrcpyActionData alloc] init];
            confirmActionData.actionId = confirmAction.id.UUIDString;
            confirmActionData.name = confirmAction.name;
            confirmActionData.deviceType = (confirmAction.deviceTypeIntValue == 0) ? @"VNC" : @"ADB";
            
            switch (confirmAction.executionTimingIntValue) {
                case 1: // immediate
                    confirmActionData.executionTiming = @"immediate";
                    break;
                case 2: // delayed
                    confirmActionData.executionTiming = @"delayed";
                    break;
                case 0: // confirmation
                default:
                    confirmActionData.executionTiming = @"confirmation";
                    break;
            }
            
            confirmActionData.delaySeconds = confirmAction.delaySeconds;
            
            confirmationCallback(confirmActionData, confirmCallback);
        };
    }
    
    // Execute the action using SessionConnectionManager
    NSLog(@"[ScrcpyActionsBridge] About to call connectToSessionWithAction with session: %@, action: %@", currentSession.sessionName, action.name);
    [connectionManager connectToSessionWithAction:currentSession
                                           action:action
                                   statusCallback:swiftStatusCallback
                                    errorCallback:swiftErrorCallback
                       actionConfirmationCallback:swiftConfirmationCallback];
    NSLog(@"[ScrcpyActionsBridge] connectToSessionWithAction call completed");
}

- (void)executeActionOnCurrentSession:(ScrcpyActionData *)actionData
                       statusCallback:(ScrcpyActionStatusCallback)statusCallback
                        errorCallback:(ScrcpyActionErrorCallback)errorCallback
               confirmationCallback:(ScrcpyActionConfirmationCallback _Nullable)confirmationCallback {
    
    NSLog(@"[ScrcpyActionsBridge] executeActionOnCurrentSession called with action: %@ (ID: %@)", actionData.name, actionData.actionId);
    
    // Get ActionManager and find the original ScrcpyAction
    ActionManager *actionManager = [ActionManager shared];
    NSLog(@"[ScrcpyActionsBridge] ActionManager retrieved: %@", actionManager);
    
    NSUUID *actionId = [[NSUUID alloc] initWithUUIDString:actionData.actionId];
    
    if (!actionId) {
        errorCallback(@"Invalid Action", @"Action ID is invalid");
        return;
    }
    
    ScrcpyAction *action = [actionManager getActionBy:actionId];
    NSLog(@"[ScrcpyActionsBridge] Action retrieved from ActionManager: %@", action);
    if (!action) {
        NSLog(@"[ScrcpyActionsBridge] ERROR: Action not found for ID: %@", actionId.UUIDString);
        errorCallback(@"Action Not Found", @"The specified action could not be found");
        return;
    }
    
    // Get current session
    SessionConnectionManager *connectionManager = [SessionConnectionManager shared];
    ScrcpySessionModel *currentSession = connectionManager.currentSession;
    NSLog(@"[ScrcpyActionsBridge] Current session: %@", currentSession);
    
    if (!currentSession) {
        errorCallback(@"No Active Session", @"No active session found. Please connect to a device first.");
        return;
    }
    
    // Create Swift callback blocks
    void (^swiftStatusCallback)(enum ScrcpyStatus, NSString *, BOOL) = ^(enum ScrcpyStatus status, NSString *message, BOOL isConnecting) {
        statusCallback((NSInteger)status, message, isConnecting);
    };
    
    void (^swiftErrorCallback)(NSString *, NSString *) = ^(NSString *title, NSString *message) {
        errorCallback(title, message);
    };
    
    void (^swiftConfirmationCallback)(ScrcpyAction *, void (^)(void)) = nil;
    if (confirmationCallback) {
        swiftConfirmationCallback = ^(ScrcpyAction *confirmAction, void (^confirmCallback)(void)) {
            // Convert Swift action back to Objective-C action data
            ScrcpyActionData *confirmActionData = [[ScrcpyActionData alloc] init];
            confirmActionData.actionId = confirmAction.id.UUIDString;
            confirmActionData.name = confirmAction.name;
            confirmActionData.deviceType = (confirmAction.deviceTypeIntValue == 0) ? @"VNC" : @"ADB";
            
            switch (confirmAction.executionTimingIntValue) {
                case 1: // immediate
                    confirmActionData.executionTiming = @"immediate";
                    break;
                case 2: // delayed
                    confirmActionData.executionTiming = @"delayed";
                    break;
                case 0: // confirmation
                default:
                    confirmActionData.executionTiming = @"confirmation";
                    break;
            }
            
            confirmActionData.delaySeconds = confirmAction.delaySeconds;
            
            confirmationCallback(confirmActionData, confirmCallback);
        };
    }
    
    // Execute the action on current session without reconnecting
    NSLog(@"[ScrcpyActionsBridge] About to call executeActionOnCurrentSession with action: %@", action.name);
    [connectionManager executeActionOnCurrentSession:action
                                      statusCallback:swiftStatusCallback
                                       errorCallback:swiftErrorCallback
                          actionConfirmationCallback:swiftConfirmationCallback];
    NSLog(@"[ScrcpyActionsBridge] executeActionOnCurrentSession call completed");
}

@end

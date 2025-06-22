//
//  ScrcpyConstants.m
//  Scrcpy Remote
//
//  Created by Claude on 6/19/25.
//

#import "ScrcpyConstants.h"

// MARK: - Icon Constants

// System Icon Names
NSString * const kIconCapsuleHandle = @"ellipsis";
NSString * const kIconBackButton = @"arrow.left";
NSString * const kIconHomeButton = @"house.circle";
NSString * const kIconSwitchButton = @"square.circle";
NSString * const kIconKeyboardButton = @"keyboard";
NSString * const kIconActionsButton = @"ellipsis.circle";
NSString * const kIconDisconnectButton = @"xmark.circle";

// UserDefaults Keys
NSString * const kUserDefaultsPositionRatioX = @"ScrcpyMenuPositionRatioX";
NSString * const kUserDefaultsPositionRatioY = @"ScrcpyMenuPositionRatioY";

// Notification Names
NSString * const kNotificationVNCDrag = @"ScrcpyVNCDragNotification";
NSString * const kNotificationVNCDragOffset = @"ScrcpyVNCDragOffsetNotification";
NSString * const kNotificationVNCMouseEvent = @"ScrcpyVNCMouseEventNotification";

// Device Types
NSString * const kDeviceTypeVNC = @"vnc";
NSString * const kDeviceTypeADB = @"adb";

// Mouse Event Types
NSString * const kMouseEventTypeMove = @"mouseMove";
NSString * const kMouseEventTypeDragStart = @"mouseDragStart";
NSString * const kMouseEventTypeDrag = @"mouseDrag";
NSString * const kMouseEventTypeDragEnd = @"mouseDragEnd";
NSString * const kMouseEventTypeClick = @"mouseClick";

// Drag States
NSString * const kDragStateBegan = @"began";
NSString * const kDragStateChanged = @"changed";
NSString * const kDragStateEnded = @"ended";
NSString * const kDragStateCancelled = @"cancelled";

// Dictionary Keys
NSString * const kKeyState = @"state";
NSString * const kKeyLocation = @"location";
NSString * const kKeyViewSize = @"viewSize";
NSString * const kKeyOffset = @"offset";
NSString * const kKeyNormalizedOffset = @"normalizedOffset";
NSString * const kKeyType = @"type";
NSString * const kKeyIsRightClick = @"isRightClick";

// Button Type Names
NSString * const kButtonTypeBack = @"back";
NSString * const kButtonTypeHome = @"home";
NSString * const kButtonTypeSwitch = @"switch";
NSString * const kButtonTypeKeyboard = @"keyboard";
NSString * const kButtonTypeActions = @"actions";
NSString * const kButtonTypeDisconnect = @"disconnect";
NSString * const kButtonTypeUnknown = @"unknown";

// Log Labels
NSString * const kLogLabelRight = @"Right";
NSString * const kLogLabelLeft = @"Left";
//
//  ScrcpyConstants.h
//  Scrcpy Remote
//
//  Created by Claude on 6/19/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Icon Constants

// System Icon Names
extern NSString * const kIconCapsuleHandle;
extern NSString * const kIconBackButton;
extern NSString * const kIconHomeButton;
extern NSString * const kIconSwitchButton;
extern NSString * const kIconKeyboardButton;
extern NSString * const kIconActionsButton;
extern NSString * const kIconDisconnectButton;

// UserDefaults Keys
extern NSString * const kUserDefaultsPositionRatioX;
extern NSString * const kUserDefaultsPositionRatioY;

// Notification Names
extern NSString * const kNotificationVNCDrag;
extern NSString * const kNotificationVNCDragOffset;
extern NSString * const kNotificationVNCMouseEvent;
extern NSString * const kNotificationVNCScrollEvent;

// Device Types
extern NSString * const kDeviceTypeVNC;
extern NSString * const kDeviceTypeADB;

// Mouse Event Types
extern NSString * const kMouseEventTypeMove;
extern NSString * const kMouseEventTypeDragStart;
extern NSString * const kMouseEventTypeDrag;
extern NSString * const kMouseEventTypeDragEnd;
extern NSString * const kMouseEventTypeClick;
extern NSString * const kMouseEventTypeScroll;

// Drag States
extern NSString * const kDragStateBegan;
extern NSString * const kDragStateChanged;
extern NSString * const kDragStateEnded;
extern NSString * const kDragStateCancelled;

// Dictionary Keys
extern NSString * const kKeyState;
extern NSString * const kKeyLocation;
extern NSString * const kKeyViewSize;
extern NSString * const kKeyOffset;
extern NSString * const kKeyNormalizedOffset;
extern NSString * const kKeyZoomScale;
extern NSString * const kKeyType;
extern NSString * const kKeyIsRightClick;

// Button Type Names
extern NSString * const kButtonTypeBack;
extern NSString * const kButtonTypeHome;
extern NSString * const kButtonTypeSwitch;
extern NSString * const kButtonTypeKeyboard;
extern NSString * const kButtonTypeActions;
extern NSString * const kButtonTypeDisconnect;
extern NSString * const kButtonTypeUnknown;

// Log Labels
extern NSString * const kLogLabelRight;
extern NSString * const kLogLabelLeft;

NS_ASSUME_NONNULL_END
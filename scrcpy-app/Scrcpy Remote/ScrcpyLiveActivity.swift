import Foundation
import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Bridge File
// 
// This file serves as a bridge between the main app and the Live Activity Widget Extension.
// 
// Architecture:
// - ScrcpyLiveActivityAttributes is defined in ScrcpyLiveActivityWidget/ScrcpyLiveActivityAttributes.swift
// - Live Activity Widget implementation is in ScrcpyLiveActivityWidget Extension
// - Main app uses ScrcpyLiveActivityManager to control Live Activities
//
// Benefits of this architecture:
// 1. Clean separation of concerns
// 2. Widget Extension can have its own @main entry point
// 3. Better modularity and maintainability
// 4. Follows Apple's recommended practices
//
// Note: The main app imports the Widget Extension's ScrcpyLiveActivityAttributes 
// through target dependencies and uses it via ScrcpyLiveActivityManager.



 
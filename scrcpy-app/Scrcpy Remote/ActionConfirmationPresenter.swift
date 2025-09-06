//
//  ActionConfirmationPresenter.swift
//  Scrcpy Remote
//
//  Created by AI on 2025-09-06.
//

import Foundation
import UIKit

@objcMembers
class ActionConfirmationPresenter: NSObject {
    /// Presents a unified global confirmation alert for an action ID.
    /// - Parameters:
    ///   - actionId: The UUID string of the action to confirm.
    ///   - confirmCallback: Callback executed when user confirms.
    @objc class func showForActionId(_ actionId: String, confirmCallback: @escaping () -> Void) {
        guard let uuid = UUID(uuidString: actionId) else {
            print("❌ [ActionConfirmationPresenter] Invalid actionId: \(actionId). Executing callback directly.")
            confirmCallback()
            return
        }

        let actionManager = ActionManager.shared
        guard let action = actionManager.getActionBy(uuid) else {
            print("❌ [ActionConfirmationPresenter] Action not found for id: \(actionId). Executing callback directly.")
            confirmCallback()
            return
        }

        // Present the same global confirmation used by ActionsView
        WindowUtil.showGlobalActionConfirmation(action: action) {
            confirmCallback()
        }
    }
}


//
//  ActionCreationFlow.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/8/24.
//

import SwiftUI

// MARK: - New Action View

struct NewActionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var actionName = ""
    @State private var selectedDevice: ScrcpySession? = nil
    @State private var currentStep = 1
    @State private var selectedVNCQuickActions: Set<VNCQuickAction> = []
    @State private var adbCommands = ""
    @State private var executionTiming: ExecutionTiming = .confirmation
    @State private var delaySeconds: Int = 3
    @State private var showingDeviceSelector = false
    
    // VNC action states
    @State private var vncInputKeysConfig = VNCInputKeysConfig()
    @State private var showingVNCKeySelector = false
    @State private var lastSelectedPCKeyCategory: PCKeyCategory = .letters
    
    // New ADB action states
    @State private var selectedADBActionType: ADBActionType = .homeKey
    @State private var adbInputKeysConfig = ADBInputKeysConfig()
    @State private var adbShellConfig = ADBShellConfig()
    @State private var showingKeySelector = false
    @State private var lastSelectedKeyCategory: KeyCategory = .letters
    
    let onSave: (ScrcpyAction) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Step indicator
                StepIndicatorView(currentStep: currentStep, totalSteps: 3)
                    .padding()
                
                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        if currentStep == 1 {
                            DeviceSelectionView(
                                selectedDevice: $selectedDevice,
                                onDeviceDoubleTap: {
                                    if selectedDevice != nil {
                                        handleNext()
                                    }
                                }
                            )
                        } else if currentStep == 2 {
                            Step2View(
                                deviceType: selectedDevice?.deviceType ?? "vnc",
                                selectedVNCQuickActions: $selectedVNCQuickActions,
                                vncInputKeysConfig: $vncInputKeysConfig,
                                adbCommands: $adbCommands,
                                selectedADBActionType: $selectedADBActionType,
                                adbInputKeysConfig: $adbInputKeysConfig,
                                adbShellConfig: $adbShellConfig,
                                executionTiming: $executionTiming,
                                delaySeconds: $delaySeconds,
                                onVNCActionDoubleTap: {
                                    if !selectedVNCQuickActions.isEmpty {
                                        handleNext()
                                    }
                                },
                                onShowKeySelector: {
                                    showingKeySelector = true
                                },
                                onShowVNCKeySelector: {
                                    showingVNCKeySelector = true
                                }
                            )
                        } else {
                            Step3View(
                                actionName: $actionName,
                                onSave: {
                                    saveAction()
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("New Action")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: HStack {
                    if currentStep > 1 {
                        Button("Back") {
                            currentStep -= 1
                        }
                    }
                    
                    if currentStep < 3 {
                        Button("Next") {
                            handleNext()
                        }
                        .disabled(!canProceedToNext())
                    } else {
                        Button("Save") {
                            saveAction()
                        }
                        .disabled(actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            )
        }
        .sheet(isPresented: $showingKeySelector) {
            KeySelectorView(defaultCategory: lastSelectedKeyCategory) { keyCode in
                let keyAction = ADBKeyAction(keyCode: keyCode.rawValue, keyName: keyCode.displayName)
                adbInputKeysConfig.keys.append(keyAction)
                lastSelectedKeyCategory = keyCode.category
            }
        }
        .sheet(isPresented: $showingVNCKeySelector) {
            VNCKeySelectorView(defaultCategory: lastSelectedPCKeyCategory) { keyCode, modifiers in
                let keyAction = VNCKeyAction(keyCode: keyCode.rawValue, keyName: keyCode.displayName, modifiers: modifiers)
                vncInputKeysConfig.keys.append(keyAction)
                lastSelectedPCKeyCategory = keyCode.category
            }
        }
    }
    
    private func generateDefaultActionName() {
        guard let device = selectedDevice else { return }
        
        var baseName = ""
        let deviceName = device.sessionModel.sessionName.isEmpty ? "Device" : device.sessionModel.sessionName
        
        if device.sessionModel.deviceType == .vnc {
            if selectedVNCQuickActions.isEmpty {
                baseName = "Connect to \(deviceName)"
            } else {
                let actionNames = selectedVNCQuickActions.map { $0.rawValue }
                baseName = "\(deviceName) - \(actionNames.joined(separator: ", "))"
            }
        } else {
            switch selectedADBActionType {
            case .homeKey:
                baseName = "\(deviceName) - Home Key"
            case .switchKey:
                baseName = "\(deviceName) - Switch Key"
            case .inputKeys:
                if !adbInputKeysConfig.keys.isEmpty {
                    baseName = "\(deviceName) - Key Input"
                } else {
                    baseName = "\(deviceName) - Input Keys"
                }
            case .shellCommands:
                baseName = "\(deviceName) - Shell Commands"
            }
        }
        
        actionName = generateUniqueActionName(baseName: baseName)
    }
    
    private func generateUniqueActionName(baseName: String) -> String {
        let existingNames = ActionManager.shared.actions.map { $0.name }
        
        if !existingNames.contains(baseName) {
            return baseName
        }
        
        var counter = 1
        var uniqueName = "\(baseName) \(counter)"
        
        while existingNames.contains(uniqueName) {
            counter += 1
            uniqueName = "\(baseName) \(counter)"
        }
        
        return uniqueName
    }
    
    private func saveAction() {
        guard !actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        var action = ScrcpyAction()
        action.name = actionName
        
        if let device = selectedDevice {
            action.deviceId = device.id
            action.deviceType = device.sessionModel.deviceType
            action.executionTiming = executionTiming
            action.delaySeconds = delaySeconds
            
            if device.sessionModel.deviceType == .vnc {
                action.vncQuickActions = Array(selectedVNCQuickActions)
                action.vncInputKeysConfig = vncInputKeysConfig
            } else {
                action.adbActionType = selectedADBActionType
                action.adbInputKeysConfig = adbInputKeysConfig
                action.adbShellConfig = adbShellConfig
                // Keep legacy support
                action.adbCommands = adbCommands
            }
        }
        
        onSave(action)
        dismiss()
    }
    
    private func handleNext() {
        if currentStep == 2 {
            // Only generate default name if no name has been set
            if actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                generateDefaultActionName()
            }
        }
        if currentStep < 3 {
            currentStep += 1
        }
    }
    
    private func canProceedToNext() -> Bool {
        switch currentStep {
        case 1:
            return selectedDevice != nil
        case 2:
            guard let device = selectedDevice else { return false }
            if device.sessionModel.deviceType == .vnc {
                if !selectedVNCQuickActions.isEmpty {
                    // Check specific VNC action requirements
                    if selectedVNCQuickActions.contains(.inputKeys) {
                        return !vncInputKeysConfig.keys.isEmpty
                    } else {
                        return true // Sync Clipboard doesn't need additional config
                    }
                } else {
                    return false
                }
            } else {
                // Check based on selected ADB action type
                switch selectedADBActionType {
                case .homeKey, .switchKey:
                    return true // These don't need additional configuration
                case .inputKeys:
                    return !adbInputKeysConfig.keys.isEmpty
                case .shellCommands:
                    return !adbShellConfig.commands.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        case 3:
            return !actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }
    
    private func resetForm() {
        actionName = ""
        selectedDevice = nil
        currentStep = 1
        selectedVNCQuickActions.removeAll()
        vncInputKeysConfig = VNCInputKeysConfig()
        adbCommands = ""
        executionTiming = .confirmation
        delaySeconds = 3
    }
}

// MARK: - Edit Action View

struct EditActionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var actionName: String
    @State private var selectedDevice: ScrcpySession? = nil
    @State private var currentStep = 1
    @State private var selectedVNCQuickActions: Set<VNCQuickAction>
    @State private var adbCommands: String
    @State private var executionTiming: ExecutionTiming = .confirmation
    @State private var delaySeconds: Int = 3
    @State private var savedSessions: [ScrcpySession] = []
    
    // VNC action states
    @State private var vncInputKeysConfig: VNCInputKeysConfig
    @State private var showingVNCKeySelector = false
    @State private var lastSelectedPCKeyCategory: PCKeyCategory = .letters
    
    // ADB action states  
    @State private var showingKeySelector = false
    @State private var lastSelectedKeyCategory: KeyCategory = .letters
    @State private var selectedADBActionType: ADBActionType
    @State private var adbInputKeysConfig: ADBInputKeysConfig
    @State private var adbShellConfig: ADBShellConfig
    
    let action: ScrcpyAction
    let onSave: (ScrcpyAction) -> Void
    
    init(action: ScrcpyAction, onSave: @escaping (ScrcpyAction) -> Void) {
        self.action = action
        self.onSave = onSave
        // Initialize state with action data
        self._actionName = State(initialValue: action.name)
        self._selectedVNCQuickActions = State(initialValue: Set(action.vncQuickActions))
        self._adbCommands = State(initialValue: action.adbCommands)
        self._executionTiming = State(initialValue: action.executionTiming)
        self._delaySeconds = State(initialValue: action.delaySeconds)
        self._vncInputKeysConfig = State(initialValue: action.vncInputKeysConfig)
        self._selectedADBActionType = State(initialValue: action.adbActionType)
        self._adbInputKeysConfig = State(initialValue: action.adbInputKeysConfig)
        self._adbShellConfig = State(initialValue: action.adbShellConfig)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Step indicator
                StepIndicatorView(currentStep: currentStep, totalSteps: 3)
                    .padding()
                
                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        if currentStep == 1 {
                            DeviceSelectionView(
                                selectedDevice: $selectedDevice,
                                onDeviceDoubleTap: {
                                    if selectedDevice != nil {
                                        handleNext()
                                    }
                                }
                            )
                        } else if currentStep == 2 {
                            Step2View(
                                deviceType: selectedDevice?.deviceType ?? action.deviceType.rawValue,
                                selectedVNCQuickActions: $selectedVNCQuickActions,
                                vncInputKeysConfig: $vncInputKeysConfig,
                                adbCommands: $adbCommands,
                                selectedADBActionType: $selectedADBActionType,
                                adbInputKeysConfig: $adbInputKeysConfig,
                                adbShellConfig: $adbShellConfig,
                                executionTiming: $executionTiming,
                                delaySeconds: $delaySeconds,
                                onVNCActionDoubleTap: {
                                    if !selectedVNCQuickActions.isEmpty {
                                        handleNext()
                                    }
                                },
                                onShowKeySelector: {
                                    showingKeySelector = true
                                },
                                onShowVNCKeySelector: {
                                    showingVNCKeySelector = true
                                }
                            )
                        } else {
                            Step3View(
                                actionName: $actionName,
                                onSave: {
                                    saveAction()
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Edit Action")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: HStack {
                    if currentStep > 1 {
                        Button("Back") {
                            currentStep -= 1
                        }
                    }
                    
                    if currentStep < 3 {
                        Button("Next") {
                            handleNext()
                        }
                        .disabled(!canProceedToNext())
                    } else {
                        Button("Save") {
                            saveAction()
                        }
                        .disabled(actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            )
        }
        .sheet(isPresented: $showingKeySelector) {
            KeySelectorView(defaultCategory: lastSelectedKeyCategory) { keyCode in
                let keyAction = ADBKeyAction(keyCode: keyCode.rawValue, keyName: keyCode.displayName)
                adbInputKeysConfig.keys.append(keyAction)
                lastSelectedKeyCategory = keyCode.category
            }
        }
        .sheet(isPresented: $showingVNCKeySelector) {
            VNCKeySelectorView(defaultCategory: lastSelectedPCKeyCategory) { keyCode, modifiers in
                let keyAction = VNCKeyAction(keyCode: keyCode.rawValue, keyName: keyCode.displayName, modifiers: modifiers)
                vncInputKeysConfig.keys.append(keyAction)
                lastSelectedPCKeyCategory = keyCode.category
            }
        }
        .onAppear {
            loadSavedSessions()
            // Find and select the associated device
            if let deviceId = action.deviceId {
                selectedDevice = savedSessions.first { $0.id == deviceId }
            }
        }
    }
    
    private func handleNext() {
        if currentStep == 2 {
            // Only generate default name if no name has been set
            if actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                generateDefaultActionName()
            }
        }
        if currentStep < 3 {
            currentStep += 1
        }
    }
    
    private func canProceedToNext() -> Bool {
        switch currentStep {
        case 1:
            return selectedDevice != nil
        case 2:
            guard let device = selectedDevice else { return false }
            if device.sessionModel.deviceType == .vnc {
                if !selectedVNCQuickActions.isEmpty {
                    // Check specific VNC action requirements
                    if selectedVNCQuickActions.contains(.inputKeys) {
                        return !vncInputKeysConfig.keys.isEmpty
                    } else {
                        return true // Sync Clipboard doesn't need additional config
                    }
                } else {
                    return false
                }
            } else {
                // Check based on selected ADB action type
                switch selectedADBActionType {
                case .homeKey, .switchKey:
                    return true // These don't need additional configuration
                case .inputKeys:
                    return !adbInputKeysConfig.keys.isEmpty
                case .shellCommands:
                    return !adbShellConfig.commands.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        case 3:
            return !actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }
    
    private func generateDefaultActionName() {
        guard let device = selectedDevice else { return }
        
        var baseName = ""
        let deviceName = device.sessionModel.sessionName.isEmpty ? "Device" : device.sessionModel.sessionName
        
        if device.sessionModel.deviceType == .vnc {
            if selectedVNCQuickActions.isEmpty {
                baseName = "Connect to \(deviceName)"
            } else {
                let actionNames = selectedVNCQuickActions.map { $0.rawValue }
                baseName = "\(deviceName) - \(actionNames.joined(separator: ", "))"
            }
        } else {
            switch selectedADBActionType {
            case .homeKey:
                baseName = "\(deviceName) - Home Key"
            case .switchKey:
                baseName = "\(deviceName) - Switch Key"
            case .inputKeys:
                if !adbInputKeysConfig.keys.isEmpty {
                    baseName = "\(deviceName) - Key Input"
                } else {
                    baseName = "\(deviceName) - Input Keys"
                }
            case .shellCommands:
                baseName = "\(deviceName) - Shell Commands"
            }
        }
        
        let existingNames = ActionManager.shared.actions.filter { $0.id != action.id }.map { $0.name }
        actionName = generateUniqueActionName(baseName: baseName, existingNames: existingNames)
    }
    
    private func generateUniqueActionName(baseName: String, existingNames: [String]) -> String {
        if !existingNames.contains(baseName) {
            return baseName
        }
        
        var counter = 1
        var uniqueName = "\(baseName) \(counter)"
        
        while existingNames.contains(uniqueName) {
            counter += 1
            uniqueName = "\(baseName) \(counter)"
        }
        
        return uniqueName
    }
    
    private func saveAction() {
        guard !actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Create a deep copy of the original action using JSON serialization to avoid reference issues
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(action)
            
            let decoder = JSONDecoder()
            let updatedAction = try decoder.decode(ScrcpyAction.self, from: data)
            
            // Update the properties with new values
            updatedAction.name = actionName
            
            if let device = selectedDevice {
                updatedAction.deviceId = device.id
                updatedAction.deviceType = device.sessionModel.deviceType
                updatedAction.executionTiming = executionTiming
                updatedAction.delaySeconds = delaySeconds
                
                if device.sessionModel.deviceType == .vnc {
                    updatedAction.vncQuickActions = Array(selectedVNCQuickActions)
                    updatedAction.vncInputKeysConfig = vncInputKeysConfig
                } else {
                    updatedAction.adbActionType = selectedADBActionType
                    updatedAction.adbInputKeysConfig = adbInputKeysConfig
                    updatedAction.adbShellConfig = adbShellConfig
                    updatedAction.adbCommands = adbCommands
                }
            }
            
            print("📝 [EditActionView] Saving edited action: '\(updatedAction.name)' with ID: \(updatedAction.id)")
            onSave(updatedAction)
            dismiss()
        } catch {
            print("❌ [EditActionView] Failed to create deep copy for editing: \(error)")
        }
    }
    
    private func resetForm() {
        actionName = action.name
        selectedVNCQuickActions = Set(action.vncQuickActions)
        vncInputKeysConfig = action.vncInputKeysConfig
        adbCommands = action.adbCommands
        executionTiming = action.executionTiming
        delaySeconds = action.delaySeconds
        currentStep = 1
    }
    
    private func loadSavedSessions() {
        savedSessions = SessionManager.shared.loadSessions().map {
            ScrcpySession(sessionModel: $0)
        }
    }
}
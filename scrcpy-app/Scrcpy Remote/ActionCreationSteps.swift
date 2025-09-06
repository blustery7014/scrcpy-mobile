//
//  ActionCreationSteps.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/8/24.
//

import SwiftUI

// MARK: - Step Indicator View

struct StepIndicatorView: View {
    let currentStep: Int
    let totalSteps: Int
    
    private let stepTitles = ["Device*", "Actions*", "Name*"]
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress bar
            HStack(spacing: 0) {
                ForEach(1...totalSteps, id: \.self) { step in
                    Rectangle()
                        .fill(
                            step <= currentStep 
                            ? LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.gray.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(height: 6)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                    
                    if step < totalSteps {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 8, height: 6)
                    }
                }
            }
            .clipShape(Capsule())
            
            // Step indicators with labels
            HStack {
                ForEach(1...totalSteps, id: \.self) { step in
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    step <= currentStep 
                                    ? LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .frame(width: 32, height: 32)
                                .shadow(color: step <= currentStep ? Color.blue.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
                            
                            if step < currentStep {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Text("\(step)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(step == currentStep ? .white : .gray)
                            }
                        }
                        .scaleEffect(step == currentStep ? 1.1 : 1.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: currentStep)
                        
                        Text(LocalizedStringKey(stepTitles[step - 1]))
                            .font(.caption)
                            .fontWeight(step == currentStep ? .semibold : .regular)
                            .foregroundColor(step <= currentStep ? .primary : .secondary)
                            .animation(.easeInOut(duration: 0.2), value: currentStep)
                    }
                    
                    if step < totalSteps {
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Step 1 View (Device Selection)

struct DeviceSelectionView: View {
    @Binding var selectedDevice: ScrcpySession?
    @State private var savedSessions: [ScrcpySession] = []
    
    var onDeviceDoubleTap: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Device Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Device")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Choose a device to associate with this action")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if savedSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.title)
                            .foregroundColor(.gray)
                        Text("No saved devices")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Please create a session first in the Sessions tab")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(160), spacing: 12), count: 2), spacing: 12) {
                        ForEach(savedSessions) { session in
                            DeviceCardView(
                                session: session,
                                isSelected: selectedDevice?.id == session.id,
                                onTap: {
                                    selectedDevice = session
                                },
                                onDoubleTap: {
                                    selectedDevice = session
                                    onDeviceDoubleTap?()
                                }
                            )
                        }
                    }
                }
            }
            
            if selectedDevice == nil {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.orange)
                        Text("Please select a device to continue")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            Spacer()
        }
        .onAppear {
            loadSavedSessions()
        }
    }
    
    private func loadSavedSessions() {
        savedSessions = SessionManager.shared.loadSessions().map {
            ScrcpySession(sessionModel: $0)
        }
    }
}

// MARK: - Step 2 View (Action Configuration)

struct Step2View: View {
    let deviceType: String
    @Binding var selectedVNCQuickActions: Set<VNCQuickAction>
    @Binding var vncInputKeysConfig: VNCInputKeysConfig
    @Binding var adbCommands: String
    @Binding var selectedADBActionType: ADBActionType
    @Binding var adbInputKeysConfig: ADBInputKeysConfig
    @Binding var adbShellConfig: ADBShellConfig
    @Binding var executionTiming: ExecutionTiming
    @Binding var delaySeconds: Int
    
    var onVNCActionDoubleTap: (() -> Void)? = nil
    var onShowKeySelector: (() -> Void)? = nil
    var onShowVNCKeySelector: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Configure Actions")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("*")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }
            
            Text("Select at least one action to perform when executing this action")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if deviceType == "vnc" {
                // VNC Quick Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("VNC Quick Actions")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Select actions to perform on the VNC device")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(VNCQuickAction.allCases, id: \.self) { action in
                            QuickActionCardView(
                                action: action,
                                isSelected: selectedVNCQuickActions.contains(action),
                                onTap: {
                                    if selectedVNCQuickActions.contains(action) {
                                        selectedVNCQuickActions.remove(action)
                                    } else {
                                        selectedVNCQuickActions.insert(action)
                                    }
                                },
                                onDoubleTap: {
                                    if !selectedVNCQuickActions.contains(action) {
                                        selectedVNCQuickActions.insert(action)
                                    }
                                    onVNCActionDoubleTap?()
                                }
                            )
                        }
                    }
                    
                    // VNC Input Keys Configuration
                    if selectedVNCQuickActions.contains(.inputKeys) {
                        VNCInputKeysConfigView(
                            config: $vncInputKeysConfig,
                            onShowKeySelector: onShowVNCKeySelector
                        )
                    }
                }
            } else {
                // ADB Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("ADB Actions")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Select the type of action to perform on the Android device")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // ADB Action Type Selection
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(ADBActionType.allCases, id: \.self) { actionType in
                            ADBActionTypeCardView(
                                actionType: actionType,
                                isSelected: selectedADBActionType == actionType,
                                onTap: {
                                    selectedADBActionType = actionType
                                }
                            )
                        }
                    }
                    
                    // Configuration based on selected action type
                    switch selectedADBActionType {
                    case .homeKey, .switchKey:
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("No additional configuration needed")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                Spacer()
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                    case .inputKeys:
                        ADBInputKeysConfigView(
                            config: $adbInputKeysConfig,
                            onShowKeySelector: onShowKeySelector
                        )
                        
                    case .shellCommands:
                        ADBShellConfigView(config: $adbShellConfig)
                    }
                }
            }
            
            // Execution Timing Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Execution Timing")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("*")
                        .font(.headline)
                        .foregroundColor(.red)
                }
                
                Text("Choose when to execute the actions after connection")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    ForEach(ExecutionTiming.allCases, id: \.self) { timing in
                        ExecutionTimingCardView(
                            timing: timing,
                            isSelected: executionTiming == timing,
                            delaySeconds: delaySeconds,
                            onTap: {
                                executionTiming = timing
                            },
                            onDelayChange: { newDelay in
                                delaySeconds = newDelay
                            }
                        )
                    }
                }
            }
            
            // Validation feedback
            if deviceType == "vnc" {
                if selectedVNCQuickActions.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Please select at least one VNC action")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity)
                } else if selectedVNCQuickActions.contains(.inputKeys) && vncInputKeysConfig.keys.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Please configure keys for Input Keys action")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(String(
                            format: NSLocalizedString("%d action(s) selected", comment: "Count of selected actions"),
                            selectedVNCQuickActions.count
                        ))
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity)
                }
            } else {
                // ADB validation - only show general validation for non-shell actions
                switch selectedADBActionType {
                case .homeKey, .switchKey:
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Action configured")
                            .font(.subheadline)
                            .foregroundColor(.green)
                        Spacer()
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity)
                case .inputKeys:
                    // Input keys validation is handled within ADBInputKeysConfigView
                    EmptyView()
                case .shellCommands:
                    // Shell commands validation is handled within ADBShellConfigView
                    EmptyView()
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("Actions are required to create a meaningful automation")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("Tap Next in the top-right corner when ready")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Step 3 View (Action Name)

struct Step3View: View {
    @Binding var actionName: String
    
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Name Your Action")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("A default name has been generated based on your selections. You can modify it if needed.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Action Name")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("*")
                        .font(.headline)
                        .foregroundColor(.red)
                }
                
                TextField("Enter action name", text: $actionName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.body)
                
                if actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text("Action name is required")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Action name looks good")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                    .frame(maxWidth: .infinity)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Tips:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text("• Use descriptive names like 'Connect to Dev Server'")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("• Include device name for easy identification")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("• Names are automatically numbered if duplicates exist")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            VStack(spacing: 16) {
                Button(action: onSave) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Action")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        !actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.gray], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(12)
                    .shadow(color: !actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.blue.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
                }
                .disabled(actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .scaleEffect(!actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1.0 : 0.95)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: actionName.isEmpty)
                
                Text("Your action will be saved and ready to use")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

//
//  ActionsView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/8/24.
//

import SwiftUI

// MARK: - Action Models

struct ScrcpyAction: Codable, Identifiable {
    var id = UUID()
    var name: String = ""
    var deviceId: UUID? = nil
    var deviceType: SessionDeviceType = .vnc
    var vncQuickActions: [VNCQuickAction] = []
    var adbCommands: String = ""
    var createdAt: Date = Date()
    
    init() {}
    
    init(name: String, deviceId: UUID, deviceType: SessionDeviceType) {
        self.name = name
        self.deviceId = deviceId
        self.deviceType = deviceType
    }
}

enum VNCQuickAction: String, Codable, CaseIterable {
    case missionControl = "Mission Control"
    case desktop = "Desktop"
    case launchpad = "Launchpad"
    case inputText = "Input Text"
    case screenshot = "Screenshot"
    case clipboard = "Clipboard"
    
    var icon: String {
        switch self {
        case .missionControl: return "rectangle.3.group"
        case .desktop: return "desktopcomputer"
        case .launchpad: return "grid"
        case .inputText: return "keyboard"
        case .screenshot: return "camera"
        case .clipboard: return "doc.on.clipboard"
        }
    }
    
    var description: String {
        switch self {
        case .missionControl: return "Show Mission Control"
        case .desktop: return "Show Desktop"
        case .launchpad: return "Open Launchpad"
        case .inputText: return "Input text to remote device"
        case .screenshot: return "Take screenshot"
        case .clipboard: return "Sync clipboard"
        }
    }
}

// MARK: - ActionsView

struct ActionsView: View {
    @StateObject private var actionManager = ActionManager.shared
    @State private var showingNewAction = false
    @State private var editingAction: ScrcpyAction? = nil
    @State private var showingDeleteAlert = false
    @State private var actionToDelete: ScrcpyAction? = nil
    
    var body: some View {
        Group {
            if actionManager.actions.isEmpty {
                VStack {
                    Image(systemName: "inset.filled.rectangle.and.cursorarrow")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.gray)
                    Text("No Scrcpy Actions")
                        .font(.title2)
                        .bold()
                        .padding(2)
                    Text("Start a new scrcpy action by tapping the + button.\nActions are used to start scrcpy sessions and execute custom actions automatically.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.init(top: 1, leading: 20, bottom: 1, trailing: 20))
                        .multilineTextAlignment(.center)
                }
            } else {
                List(actionManager.actions) { action in
                    ActionRowView(action: action)
                        .contextMenu {
                            Button(action: {
                                // TODO: Execute action
                            }) {
                                Label("Execute Action", systemImage: "play")
                            }
                            Button(action: {
                                editingAction = action
                            }) {
                                Label("Edit Action", systemImage: "pencil")
                            }
                            Button(role: .destructive, action: {
                                actionToDelete = action
                                showingDeleteAlert = true
                            }) {
                                Label("Delete Action", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle("Scrcpy Actions")
        .sheet(isPresented: $showingNewAction) {
            NewActionView { action in
                actionManager.saveAction(action)
            }
        }
        .sheet(item: $editingAction) { action in
            EditActionView(action: action) { updatedAction in
                actionManager.saveAction(updatedAction)
            }
        }
        .alert("Delete Action", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let action = actionToDelete {
                    actionManager.deleteAction(id: action.id)
                }
                actionToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                actionToDelete = nil
            }
        } message: {
            if let action = actionToDelete {
                Text("Are you sure you want to delete '\(action.name)'?")
            }
        }
    }
}

// MARK: - Action Row View

struct ActionRowView: View {
    let action: ScrcpyAction
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(action.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(action.deviceType.rawValue.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(action.deviceType == .vnc ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                    )
            }
            
            Spacer()
            
            Button(action: {
                // TODO: Execute action
            }) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Action View

struct NewActionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var actionName = ""
    @State private var selectedDevice: ScrcpySession? = nil
    @State private var currentStep = 1
    @State private var selectedVNCQuickActions: Set<VNCQuickAction> = []
    @State private var adbCommands = ""
    @State private var showingDeviceSelector = false
    
    let onSave: (ScrcpyAction) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Step indicator
                StepIndicatorView(currentStep: currentStep, totalSteps: 2)
                    .padding()
                
                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        if currentStep == 1 {
                            Step1View(
                                actionName: $actionName,
                                selectedDevice: $selectedDevice,
                                onNext: {
                                    if !actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedDevice != nil {
                                        currentStep = 2
                                    }
                                }
                            )
                        } else {
                            Step2View(
                                deviceType: selectedDevice?.deviceType ?? "vnc",
                                selectedVNCQuickActions: $selectedVNCQuickActions,
                                adbCommands: $adbCommands,
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
                trailing: Button("Reset") {
                    resetForm()
                }
            )
        }
    }
    
    private func saveAction() {
        guard let device = selectedDevice else { return }
        
        var action = ScrcpyAction(
            name: actionName,
            deviceId: device.id,
            deviceType: device.sessionModel.deviceType
        )
        
        if device.sessionModel.deviceType == .vnc {
            action.vncQuickActions = Array(selectedVNCQuickActions)
        } else {
            action.adbCommands = adbCommands
        }
        
        onSave(action)
        dismiss()
    }
    
    private func resetForm() {
        actionName = ""
        selectedDevice = nil
        currentStep = 1
        selectedVNCQuickActions.removeAll()
        adbCommands = ""
    }
}

// MARK: - Step Indicator View

struct StepIndicatorView: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Text("\(step)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )
                
                if step < totalSteps {
                    Rectangle()
                        .fill(step < currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
    }
}

// MARK: - Step 1 View (Device Selection)

struct Step1View: View {
    @Binding var actionName: String
    @Binding var selectedDevice: ScrcpySession?
    @State private var savedSessions: [ScrcpySession] = []
    
    let onNext: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Action Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Action Name")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                TextField("Enter action name", text: $actionName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Device Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Device")
                    .font(.headline)
                    .foregroundColor(.primary)
                
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
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(savedSessions) { session in
                            DeviceCardView(
                                session: session,
                                isSelected: selectedDevice?.id == session.id
                            ) {
                                selectedDevice = session
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Next Button
            Button(action: onNext) {
                Text("Next")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        (!actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedDevice != nil) 
                        ? Color.blue 
                        : Color.gray
                    )
                    .cornerRadius(12)
            }
            .disabled(actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDevice == nil)
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

// MARK: - Device Card View

struct DeviceCardView: View {
    let session: ScrcpySession
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Device Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
                        .frame(width: 60, height: 60)
                    
                    Image(session.deviceType == "vnc" ? "vnc" : "android")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundColor(isSelected ? .white : .primary)
                }
                
                // Device Info
                VStack(spacing: 4) {
                    Text(session.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Text("\(session.sessionModel.hostReal):\(session.sessionModel.port)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Step 2 View (Action Configuration)

struct Step2View: View {
    let deviceType: String
    @Binding var selectedVNCQuickActions: Set<VNCQuickAction>
    @Binding var adbCommands: String
    
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
                                isSelected: selectedVNCQuickActions.contains(action)
                            ) {
                                if selectedVNCQuickActions.contains(action) {
                                    selectedVNCQuickActions.remove(action)
                                } else {
                                    selectedVNCQuickActions.insert(action)
                                }
                            }
                        }
                    }
                }
            } else {
                // ADB Commands
                VStack(alignment: .leading, spacing: 12) {
                    Text("ADB Commands")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Enter shell commands to execute on the Android device")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Supported commands:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("• sleep <seconds> - Wait for specified time\n• while <condition>; do <command>; done - Loop\n• for <var> in <list>; do <command>; done - For loop\n• Basic shell commands: ls, cd, pwd, etc.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    TextEditor(text: $adbCommands)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            
            Spacer()
            
            // Save Button
            Button(action: onSave) {
                Text("Save Action")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
    }
}

// MARK: - Quick Action Card View

struct QuickActionCardView: View {
    let action: VNCQuickAction
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: action.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                
                Text(action.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
                
                Text(action.description)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
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
    @State private var savedSessions: [ScrcpySession] = []
    
    let action: ScrcpyAction
    let onSave: (ScrcpyAction) -> Void
    
    init(action: ScrcpyAction, onSave: @escaping (ScrcpyAction) -> Void) {
        self.action = action
        self.onSave = onSave
        
        // Initialize state with action data
        self._actionName = State(initialValue: action.name)
        self._selectedVNCQuickActions = State(initialValue: Set(action.vncQuickActions))
        self._adbCommands = State(initialValue: action.adbCommands)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Step indicator
                StepIndicatorView(currentStep: currentStep, totalSteps: 2)
                    .padding()
                
                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        if currentStep == 1 {
                            Step1View(
                                actionName: $actionName,
                                selectedDevice: $selectedDevice,
                                onNext: {
                                    if !actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedDevice != nil {
                                        currentStep = 2
                                    }
                                }
                            )
                        } else {
                            Step2View(
                                deviceType: selectedDevice?.deviceType ?? action.deviceType.rawValue,
                                selectedVNCQuickActions: $selectedVNCQuickActions,
                                adbCommands: $adbCommands,
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
                trailing: Button("Reset") {
                    resetForm()
                }
            )
        }
        .onAppear {
            loadSavedSessions()
            // Find and select the associated device
            if let deviceId = action.deviceId {
                selectedDevice = savedSessions.first { $0.id == deviceId }
            }
        }
    }
    
    private func saveAction() {
        guard let device = selectedDevice else { return }
        
        var updatedAction = ScrcpyAction()
        updatedAction.id = action.id  // 保持原有的 ID
        updatedAction.name = actionName
        updatedAction.deviceId = device.id
        updatedAction.deviceType = device.sessionModel.deviceType
        updatedAction.createdAt = action.createdAt  // 保持原有的创建时间
        
        if device.sessionModel.deviceType == .vnc {
            updatedAction.vncQuickActions = Array(selectedVNCQuickActions)
        } else {
            updatedAction.adbCommands = adbCommands
        }
        
        onSave(updatedAction)
        dismiss()
    }
    
    private func resetForm() {
        actionName = action.name
        selectedVNCQuickActions = Set(action.vncQuickActions)
        adbCommands = action.adbCommands
        currentStep = 1
    }
    
    private func loadSavedSessions() {
        savedSessions = SessionManager.shared.loadSessions().map {
            ScrcpySession(sessionModel: $0)
        }
    }
}

#Preview {
    ActionsView()
}

import SwiftUI
import ActivityKit
import WidgetKit
import os

@available(iOS 16.1, *)
struct LiveActivityDebugView: View {
    @State private var isActivityRunning = false
    @State private var currentActivity: Activity<ScrcpyLiveActivityAttributes>?
    @State private var selectedStatusIndex = 1 // Default to Connecting
    @State private var sessionName = "Mi Pad 5"
    @State private var hostAddress = "192.168.1.100"
    @State private var port = "5555"
    @State private var deviceType = "Android"
    @State private var isUsingTailscale = false
    @State private var statusMessage = ""
    
    private let logger = Logger(subsystem: "com.mobile.scrcpy-ios", category: "LiveActivityDebug")
    
    // Status options for picker
    // Based on the original enum in ../porting/libs/include/scrcpy-porting.h
    private let statusOptions: [(String, UInt32)] = [
        ("Disconnected", 0),
        ("ADB Connected", 1),
        ("SDL Inited", 2),
        ("Window Created", 3),
        ("Connecting", 4),
        ("Connection Failed", 5),
        ("Connected", 6),
        ("Window Appeared", 7)
    ]
    
    private var selectedStatus: ScrcpyStatus? {
        return ScrcpyStatus(rawValue: statusOptions[selectedStatusIndex].1)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Activity Status") {
                    HStack {
                        Text("Active Live Activity:")
                        Spacer()
                        Text(isActivityRunning ? "Running" : "Stopped")
                            .foregroundColor(isActivityRunning ? .green : .secondary)
                            .fontWeight(.medium)
                    }
                    
                    if isActivityRunning {
                        Button("Stop Activity") {
                            stopTestActivity()
                        }
                        .foregroundColor(.red)
                    } else {
                        Button("Start Activity") {
                            startTestActivity()
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                Section("Session Configuration") {
                    HStack {
                        Text("Session Name")
                        Spacer()
                        TextField("Device Name", text: $sessionName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 150)
                    }
                    
                    HStack {
                        Text("Host Address")
                        Spacer()
                        TextField("IP Address", text: $hostAddress)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
                    }
                    
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", text: $port)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                    }
                    
                    Picker("Device Type", selection: $deviceType) {
                        Text("Android").tag("Android")
                        Text("iOS").tag("iOS")
                        Text("Unknown").tag("Unknown")
                    }
                    
                    Toggle("Using Tailscale", isOn: $isUsingTailscale)
                }
                
                Section("Status Control") {
                    Picker("Connection Status", selection: $selectedStatusIndex) {
                        ForEach(0..<statusOptions.count, id: \.self) { index in
                            Text(statusOptions[index].0).tag(index)
                        }
                    }
                    
                    HStack {
                        Text("Status Message")
                        Spacer()
                        TextField("Custom message", text: $statusMessage)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 200)
                    }
                    
                    if isActivityRunning {
                        Button("Update Activity") {
                            updateTestActivity()
                        }
                        .foregroundColor(.orange)
                    }
                }
                
                Section("System Activities") {
                    Button("List All Activities") {
                        listAllActivities()
                    }
                    
                    Button("Stop All Activities") {
                        stopAllActivities()
                    }
                    .foregroundColor(.red)
                }
                
                Section("Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Live Activity Debug Tool")
                            .font(.headline)
                        
                        Text("This tool helps you test and debug Live Activity functionality. You can:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Start/stop test activities")
                            Text("• Change connection status")
                            Text("• Test different device types")
                            Text("• Verify Tailscale indicators")
                            Text("• Check lock screen & Dynamic Island display")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                
                Section("Status Debug") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Status Debug:")
                            .font(.caption)
                            .fontWeight(.bold)
                        
                        Text("Selected Index: \(selectedStatusIndex)")
                            .font(.caption2)
                        
                        Text("Status Raw Value: \(statusOptions[selectedStatusIndex].1)")
                            .font(.caption2)
                        
                        Text("Status Description: \(selectedStatus?.description ?? "Unknown")")
                            .font(.caption2)
                        
                        Text("Is Connected: \(selectedStatus?.isFullyConnected ?? false)")
                            .font(.caption2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Live Activity Debug")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            checkCurrentActivities()
        }
    }
    
    // MARK: - Methods
    
    private func startTestActivity() {
        logger.info("🧪 [LiveActivityDebug] Starting test activity")
        
        guard let status = selectedStatus else {
            logger.error("❌ [LiveActivityDebug] Invalid status selected")
            return
        }
        
        let contentState = ScrcpyLiveActivityAttributes.ContentState(
            sessionName: sessionName,
            deviceType: deviceType,
            hostAddress: hostAddress,
            port: port,
            connectionStatus: statusMessage.isEmpty ? status.description : statusMessage,
            connectionStatusCode: Int(status.rawValue),
            isConnected: status.isFullyConnected,
            startTime: Date(),
            isUsingTailscale: isUsingTailscale
        )
        
        let attributes = ScrcpyLiveActivityAttributes(
            activityId: "debug-activity-\(UUID().uuidString)"
        )
        
        do {
            let activity = try Activity<ScrcpyLiveActivityAttributes>.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil
            )
            
            currentActivity = activity
            isActivityRunning = true
            
            logger.info("✅ [LiveActivityDebug] Test activity started successfully")
            
        } catch {
            logger.error("❌ [LiveActivityDebug] Failed to start test activity: \(error.localizedDescription)")
        }
    }
    
    private func updateTestActivity() {
        guard let activity = currentActivity else {
            logger.warning("⚠️ [LiveActivityDebug] No active test activity to update")
            return
        }
        
        guard let status = selectedStatus else {
            logger.error("❌ [LiveActivityDebug] Invalid status selected")
            return
        }
        
        logger.info("🔄 [LiveActivityDebug] Updating test activity")
        
        let currentState = activity.contentState
        let newContentState = ScrcpyLiveActivityAttributes.ContentState(
            sessionName: sessionName,
            deviceType: deviceType,
            hostAddress: hostAddress,
            port: port,
            connectionStatus: statusMessage.isEmpty ? status.description : statusMessage,
            connectionStatusCode: Int(status.rawValue),
            isConnected: status.isFullyConnected,
            startTime: currentState.startTime,
            isUsingTailscale: isUsingTailscale
        )
        
        Task {
            do {
                await activity.update(using: newContentState)
                logger.info("✅ [LiveActivityDebug] Test activity updated successfully")
            } catch {
                logger.error("❌ [LiveActivityDebug] Failed to update test activity: \(error.localizedDescription)")
            }
        }
    }
    
    private func stopTestActivity() {
        guard let activity = currentActivity else {
            logger.info("ℹ️ [LiveActivityDebug] No active test activity to stop")
            return
        }
        
        logger.info("🛑 [LiveActivityDebug] Stopping test activity")
        
        Task {
            await activity.end(dismissalPolicy: .immediate)
            logger.info("✅ [LiveActivityDebug] Test activity stopped successfully")
        }
        
        currentActivity = nil
        isActivityRunning = false
    }
    
    private func listAllActivities() {
        logger.info("📋 [LiveActivityDebug] Listing all activities")
        
        let activities = Activity<ScrcpyLiveActivityAttributes>.activities
        logger.info("Found \(activities.count) activities")
        
        for activity in activities {
            logger.info("Activity: \(activity.id) - \(activity.contentState.sessionName)")
        }
    }
    
    private func stopAllActivities() {
        logger.info("🧹 [LiveActivityDebug] Stopping all activities")
        
        Task {
            for activity in Activity<ScrcpyLiveActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
                logger.info("🗑️ [LiveActivityDebug] Ended activity: \(activity.id)")
            }
        }
        
        currentActivity = nil
        isActivityRunning = false
    }
    
    private func checkCurrentActivities() {
        let activities = Activity<ScrcpyLiveActivityAttributes>.activities
        if let activity = activities.first {
            currentActivity = activity
            isActivityRunning = true
            
            // 从活动中加载当前状态
            let state = activity.contentState
            sessionName = state.sessionName
            hostAddress = state.hostAddress
            port = state.port
            deviceType = state.deviceType
            isUsingTailscale = state.isUsingTailscale
            
            // 设置状态
            let statusValue = UInt32(state.connectionStatusCode)
            if let index = statusOptions.firstIndex(where: { $0.1 == statusValue }) {
                selectedStatusIndex = index
            } else {
                selectedStatusIndex = 0 // Default to Disconnected
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
@available(iOS 16.1, *)
struct LiveActivityDebugView_Previews: PreviewProvider {
    static var previews: some View {
        LiveActivityDebugView()
    }
}
#endif 

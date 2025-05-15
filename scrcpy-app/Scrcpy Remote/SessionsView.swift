//
//  SessionsView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/8/24.
//

import SwiftUI

struct ScrcpySession: Codable, Identifiable {
    var id: UUID {
        sessionModel.id
    }
    var title: String {
        "\(sessionModel.hostReal):\(sessionModel.port)"
    }
    var imageName: String = ""
    var deviceType: String {
        sessionModel.deviceType.rawValue
    }
    
    var backgroundColor: LinearGradient {
        // Background color based on UUID to randomize colors
        let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .red, .yellow]
        // Convert title to fixed int
        let titleNumber = title.unicodeScalars.map { code in
            Int(code.value)
        }.reduce(0, +)
        let index = titleNumber % colors.count
        let color = colors[abs(index)]
        // Gradient for background
        return LinearGradient(gradient: Gradient(colors: [color.opacity(0.9), color.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
    }
    
    var sessionModel: ScrcpySessionModel = ScrcpySessionModel()
    
    init() {}
    
    init(sessionModel: ScrcpySessionModel) {
        self.sessionModel = sessionModel
    }
}

struct SessionsView: View {
    var savedSessions: [ScrcpySession] = []
    var onDeleteSession: ((UUID) -> Void)?
    var onConnectSession: ((ScrcpySession) -> Void)?
    var onEditSession: ((ScrcpySession) -> Void)?
    
    @State private var testingLatencySessionId: UUID? = nil
    @State private var latencyResults: [UUID: Double] = [:]
    @State private var latencyErrors: [UUID: String] = [:]
    @State private var isRefreshing: Bool = false

    var body: some View {
        NavigationView {
            if savedSessions.isEmpty {
                VStack {
                    Image(systemName: "inset.filled.rectangle.badge.record")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.gray)
                    Text("No Scrcpy Sessions")
                        .font(.title2)
                        .bold()
                        .padding(2)
                    Text("Start a new scrcpy session by tapping the + button.\nSessions will be saved here for quick access.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.init(top: 1, leading: 20, bottom: 1, trailing: 20))
                        .multilineTextAlignment(.center)
                }
            } else {
                List(savedSessions) { session in
                    ZStack {
                        Image(session.imageName)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .background(session.backgroundColor)
                            .clipped()
                            .cornerRadius(10)
                            .overlay(
                                Text(session.title)
                                    .font(.headline)
                                    .bold()
                                    .foregroundColor(.white)
                                    .padding()
                                    .cornerRadius(10)
                                    .padding(0),
                                alignment: .bottomLeading
                            )
                            .overlay(
                                VStack {
                                    HStack(spacing: 8) {
                                        latencyTestView(for: session)
                                        Text(session.deviceType)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .padding(2)
                                            .padding(.horizontal, 6)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(15)
                                    }
                                }
                                .padding(),
                                alignment: .bottomTrailing
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 0)
                            )
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.bottom, session.id == savedSessions.last?.id ? 16 : 8)
                    .padding(.top, session.id == savedSessions.first?.id ? 16 : 8)
                    .padding(.horizontal, 12)
                    .listRowSeparator(.hidden)
                    .contextMenu {
                        Button(action: {
                            onConnectSession?(session)
                        }) {
                            Label("Connect Session", systemImage: "play")
                        }
                        Button(action: {
                            onEditSession?(session)
                        }) {
                            Label("Edit Session", systemImage: "pencil")
                        }
                        Button(action: {
                            
                        }) {
                            Label("Copy URL Scheme", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive, action: {
                            onDeleteSession?(session.id)
                        }) {
                            Label("Delete Session", systemImage: "trash")
                        }
                    }
                    .onTapGesture {
                        onConnectSession?(session)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    isRefreshing = true
                    // Reset all latency results
                    latencyResults = [:]
                    latencyErrors = [:]
                    // Start testing all sessions sequentially
                    testSessionsSequentially(sessions: savedSessions)
                    // Mark refresh as complete
                    isRefreshing = false
                }
                .onAppear {
                    // Auto-test latency for all sessions when view appears
                    // Using a sequential approach with delays to avoid network congestion
                    if !savedSessions.isEmpty {
                        testSessionsSequentially(sessions: savedSessions)
                    }
                }
            }
        }
    }
    
    // Test sessions one by one with a delay between each test
    private func testSessionsSequentially(sessions: [ScrcpySession], index: Int = 0) {
        guard index < sessions.count else { return }
        
        // Check if any latency test is already in progress
        if testingLatencySessionId != nil {
            // Try again after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                testSessionsSequentially(sessions: sessions, index: index)
            }
            return
        }
        
        let session = sessions[index]
        testLatency(for: session)
        
        // Schedule next test with delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            testSessionsSequentially(sessions: sessions, index: index + 1)
        }
    }
    
    @ViewBuilder
    private func latencyTestView(for session: ScrcpySession) -> some View {
        Button(action: {
            testLatency(for: session)
        }) {
            HStack(spacing: 4) {
                if testingLatencySessionId == session.id {
                    // Show spinner while testing
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 12, height: 12)
                } else if let latency = latencyResults[session.id] {
                    // Show latency result with color and icon based on value
                    HStack(spacing: 2) {
                        Text("\(Int(latency))ms")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(latencyColor(for: latency))
                        
                        Image(systemName: latencyIcon(for: latency))
                            .font(.system(size: 8))
                            .foregroundColor(latencyColor(for: latency))
                    }
                } else if latencyErrors[session.id] != nil {
                    // Show error icon
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.yellow)
                        .font(.system(size: 12))
                }
                
                Image(systemName: "wifi")
                    .foregroundColor(.white)
                    .font(.system(size: 12))
            }
            .padding(5)
            .padding(.horizontal, 6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(15)
        }
        .buttonStyle(BorderlessButtonStyle()) // Prevent tap propagation
        .disabled(testingLatencySessionId != nil)
    }
    
    private func testLatency(for session: ScrcpySession) {
        // Clear previous results for this session
        latencyResults[session.id] = nil
        latencyErrors[session.id] = nil
        
        // Set testing state
        testingLatencySessionId = session.id
        
        // Initialize ADBLatencyTester
        let tester = ADBLatencyTester(session: session.sessionModel.toDict())
        
        // Run latency test with 1 iterations for an average
        tester.testAverageLatency(withCount: 1) { latency, error in
            DispatchQueue.main.async {
                if let latency = latency?.doubleValue {
                    latencyResults[session.id] = latency
                } else if let error = error {
                    latencyErrors[session.id] = error.localizedDescription
                }
                
                // Reset testing state
                testingLatencySessionId = nil
            }
        }
    }
    
    // Helper function to determine color based on latency value
    private func latencyColor(for latency: Double) -> Color {
        switch latency {
        case ..<60:
            return .green       // Excellent latency
        case 60..<150:
            return .yellow      // Good latency
        default:
            return .red         // Poor latency
        }
    }
    
    // Helper function to determine icon based on latency value
    private func latencyIcon(for latency: Double) -> String {
        switch latency {
        case ..<60:
            return "bolt.fill"        // Fast/lightning icon for excellent latency
        case 60..<150:
            return "checkmark.circle"  // Checkmark for good latency
        default:
            return "exclamationmark.triangle"  // Warning for poor latency
        }
    }
}

struct SessionsView_Previews: PreviewProvider {
    static var previews: some View {
        SessionsView(savedSessions: [
            ScrcpySession(sessionModel: ScrcpySessionModel(host: "test.example.com", port: "5091")),
            ScrcpySession(sessionModel: ScrcpySessionModel(host: "scrcpy.link", port: "5555")),
            ScrcpySession(sessionModel: ScrcpySessionModel(host: "adb://myphone.link", port: "15680"))
        ])
    }
}

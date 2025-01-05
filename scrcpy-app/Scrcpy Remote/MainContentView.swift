//
//  ContentView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/5/24.
//

import SwiftUI

struct MainContentView: View {
    @State private var selectedTab = 0
    @State private var isSettingsPresented = false
    @State private var isSessionCreatePresented = false
    @State private var isSessionConnecting = false
    @EnvironmentObject var appSettings: AppSettings
    @State var savedSessions: [ScrcpySession]
    @State var editingSession: ScrcpySession?
    
    init() {
        savedSessions = SessionManager.shared.loadSessions().map {
            ScrcpySession(sessionModel: $0)
        }
    }
    
    init(sessions: [ScrcpySession]) {
        savedSessions = sessions
    }
    
    func reloadSessions() {
        savedSessions = SessionManager.shared.loadSessions().map {
            ScrcpySession(sessionModel: $0)
        }
        print("Reloaded sessions:", savedSessions.count)
    }

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                SessionsView(savedSessions: savedSessions, onDeleteSession: { id in
                    print("Deleting session:", id)
                    SessionManager.shared.deleteSession(id: id)
                    reloadSessions()
                }, onConnectSession: { session in
                    print("Connecting to session:", session.title)
                    isSessionConnecting = true
                    
                    // Connect to session
                    DispatchQueue.main.async {
                        ScrcpyClientWrapper().startClient(session.sessionModel.toDict(), completion: { statusCode, message in
                            switch statusCode.rawValue {
                            case ScrcpyStatusConnected.rawValue:
                                print("Connected to session:", session.title)
                                isSessionConnecting = false
                            case ScrcpyStatusConnectingFailed.rawValue:
                                print("Failed to connect to session:", session.title)
                                isSessionConnecting = false
                            default:
                                print("Connection status:", statusCode, message)
                            }
                        })
                    }
                }, onEditSession: { session in
                    print("Editing session:", session.title)
                    editingSession = session
                })
                    .tabItem {
                        Image(systemName: "rectangle.stack")
                        Text("Sessions")
                    }
                    .tag(0)
                ActionsView()
                    .tabItem {
                        Image(systemName: "play.square.stack.fill")
                        Text("Actions")
                    }
                    .tag(1)
            }
            .navigationBarTitle(
                selectedTab == 0 ? "Scrcpy Sessions" : "Scrcpy Actions",
                displayMode: .inline
            )
            .navigationBarItems(leading: Button(action: {
                isSettingsPresented.toggle()
            }) {
                Image(systemName: "gear")
            }.disabled(isSessionConnecting), trailing: Button(action: {
                if selectedTab == 0 {
                    isSessionCreatePresented.toggle()
                }
            }) {
                Image(systemName: "plus")
            }.disabled(isSessionConnecting))
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
            }
            .sheet(isPresented: $isSessionCreatePresented, onDismiss: {
                // Reset editing session
                editingSession = nil
                
                // Reload sessions
                reloadSessions()
            }) {
                SessionCreateView()
            }
            .sheet(item: $editingSession, onDismiss: {
                // Reset editing session
                editingSession = nil
                
                // Reload sessions
                reloadSessions()
            }) { item in
                SessionCreateView(sessionModel: item.sessionModel)
            }
            .overlay {
                if isSessionConnecting {
                    Color.gray.opacity(0.2)
                        .ignoresSafeArea()
                        .animation(.easeInOut, value: true)
                    ProgressView("Connecting..\n")
                        .multilineTextAlignment(.center)
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(width: 140, height: 140)
                        .tint(.white)
                        .background(.black.opacity(0.75))
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .bold))
                        .cornerRadius(16)
                        .overlay {
                            Button(action: {
                                isSessionConnecting = false
                            }) {
                                Label("Cancel", systemImage: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 6)
                                    .foregroundColor(.white)
                                    .background(.red.opacity(0.6))
                                    .cornerRadius(20)
                                    .clipped()
                            }
                            .offset(x: 0, y: 35)
                        }
                }
            }
        }
    }
}

#Preview {
    MainContentView(sessions: [
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "test.abc.com", port: "5555")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "vnc://myvnc.com", port: "5901")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "adb://test.example.com", port: "1555")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "10.1.1.1", port: "8080")),
        ScrcpySession(sessionModel: ScrcpySessionModel(host: "test2.examle.com", port: "5555"))
    ])
}

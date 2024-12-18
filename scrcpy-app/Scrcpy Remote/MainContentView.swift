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
                        ScrcpyClientWrapper().startClient(session.sessionModel.toDict())
                    }
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
                reloadSessions()
            }) {
                SessionCreateView()
            }
            .overlay {
                if isSessionConnecting {
                    Color.gray.opacity(0.2)
                        .ignoresSafeArea()
                        .animation(.easeInOut, value: true)
                    ProgressView("Connecting..\n")
                        .multilineTextAlignment(.center)
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(2)
                        .frame(width: 140, height: 140)
                        .tint(.white)
                        .background(.black.opacity(0.75))
                        .foregroundColor(.white)
                        .font(.system(size: 7, weight: .bold))
                        .cornerRadius(16)
                        .overlay {
                            Button(action: {
                                isSessionConnecting = false
                            }) {
                                Label("Cancel", systemImage: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .foregroundColor(.red)
                                    .background(.black.opacity(0.9))
                                    .cornerRadius(20)
                                    .clipped()
                            }
                            .offset(x: 0, y: 42)
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

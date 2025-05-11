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
                                    Text(session.deviceType)
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                        .padding(2)
                                        .padding(.leading, 6)
                                        .padding(.trailing, 6)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(12)
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
            }
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

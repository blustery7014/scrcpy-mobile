//
//  SessionCreateView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/8/24.
//

import SwiftUI

struct SessionCreateView: View {
    @State var sessionModel = ScrcpySessionModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Form {
            Section(header: Text("Remote Device")) {
                TextField("Host", text: $sessionModel.host)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                TextField("Port", text: $sessionModel.port)
                    .keyboardType(.numberPad)
            }
            
            if sessionModel.deviceType == .vnc {
                Section(header: Text("VNC Session Options")) {
                    TextField("VNC User", text: $sessionModel.vncOptions.vncUser)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled(true)
                    SecureField("VNC Password", text: $sessionModel.vncOptions.vncPassword)
                        .textContentType(.password)
                }
            }
            if sessionModel.deviceType == .adb {
                Section(header: Text("ADB Session Options")) {
                    TextField("Max Screen Size", text: $sessionModel.adbOptions.maxScreenSize)
                        .keyboardType(.numberPad)
                    TextField("Bit Rate", text: $sessionModel.adbOptions.bitRate)
                        .autocapitalization(.none)
                        .autocorrectionDisabled(true)
                    NavigationLink(destination: VideoEncoderSelectionView(selectedEncoder: $sessionModel.adbOptions.videoEncoder)) {
                        HStack {
                            Text("Video Encoder")
                            Spacer()
                            Text(sessionModel.adbOptions.videoEncoder)
                        }
                    }
                    TextField("Max FPS", text: $sessionModel.adbOptions.maxFPS)
                        .keyboardType(.numberPad)
                    Toggle("Enable Audio (Android 11+)", isOn: $sessionModel.adbOptions.enableAudio)
                }
            }

            Section(header: Text("Other Options")) {
                Toggle("Power Saving Mode", isOn: $sessionModel.powerSavingMode)
            }

            Section {
                Button(action: {
                    // Save session
                    SessionManager.shared.saveSession(sessionModel)
                    
                    // Pop back
                    dismiss()
                }) {
                    Text("Save Session")
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            Section {
                Button(action: {
                    // Copy URL Scheme
                }) {
                    Text("Copy URL Scheme")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .foregroundColor(.secondary)
            }
        }
        .navigationBarTitle("Create Session", displayMode: .inline)
    }
}

struct VideoEncoderSelectionView: View {
    @Binding var selectedEncoder: String

    var body: some View {
        Form {
            TextField("Custom Encoder", text: $selectedEncoder)
            // Add more encoder options here
        }
        .navigationBarTitle("Select Video Encoder", displayMode: .inline)
    }
}

struct CreateSessionView_Previews: PreviewProvider {
    static var previews: some View {
        SessionCreateView()
    }
}

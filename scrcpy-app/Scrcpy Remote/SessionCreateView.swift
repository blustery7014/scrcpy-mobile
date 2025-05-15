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
                    TextField("Bit Rate, Default: 4M or 4000K", text: $sessionModel.adbOptions.bitRate)
                        .autocapitalization(.none)
                        .autocorrectionDisabled(true)
                        .onChange(of: sessionModel.adbOptions.bitRate) { newValue in
                            if !newValue.isEmpty {
                                let filteredValue = filterBitRateInput(newValue)
                                if filteredValue != newValue {
                                    sessionModel.adbOptions.bitRate = filteredValue
                                }
                            }
                        }
                    Picker("Video Codec", selection: $sessionModel.adbOptions.videoCodec) {
                        ForEach(ADBCodec.allCases, id: \.self) { codec in
                            Text(codec.rawValue)
                        }
                    }
                    NavigationLink(destination: VideoEncoderSelectionView(selectedEncoder: $sessionModel.adbOptions.videoEncoder)) {
                        HStack {
                            Text("Video Encoder")
                            Spacer()
                            Text(sessionModel.adbOptions.videoEncoder)
                        }
                    }
                    TextField("Max FPS, Default: 60", text: $sessionModel.adbOptions.maxFPS)
                        .keyboardType(.numberPad)
                    Toggle("Enable Audio (Android 11+)", isOn: $sessionModel.adbOptions.enableAudio)
                    if sessionModel.adbOptions.enableAudio {
                        HStack {
                            Text("Volume Scale")
                            Spacer()
                            Text(String(format: "%.1fx", sessionModel.adbOptions.volumeScale))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $sessionModel.adbOptions.volumeScale, in: 0...50, step: 0.1)
                    }
                    Toggle("Enable Clipboard Sync", isOn: $sessionModel.adbOptions.enableClipboardSync)
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

private func filterBitRateInput(_ input: String) -> String {
    // If it's a valid number, return as is
    if let _ = Int(input) {
        return input
    }
    
    // Check if it ends with K or M (case insensitive)
    let upperInput = input.uppercased()
    if upperInput.hasSuffix("K") || upperInput.hasSuffix("M") {
        let numberPart = String(input.dropLast())
        if let _ = Int(numberPart) {
            return input
        }
    }
    
    // Filter out invalid characters, keeping only numbers and K/M
    let filtered = input.filter { char in
        char.isNumber || char.uppercased() == "K" || char.uppercased() == "M"
    }
    
    // If the filtered string ends with K or M, ensure there are numbers before it
    if filtered.uppercased().hasSuffix("K") || filtered.uppercased().hasSuffix("M") {
        let numberPart = String(filtered.dropLast())
        if let _ = Int(numberPart) {
            return filtered
        }
    }
    
    // If we have numbers, return just the numbers
    if let _ = Int(filtered) {
        return filtered
    }
    
    return ""
}

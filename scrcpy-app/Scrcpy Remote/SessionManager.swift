//
//  SessionManager.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/14/24.
//

import KeychainSwift
import Foundation

// VNC压缩等级枚举
enum VNCCompressionLevel: String, Codable, CaseIterable {
    case none = "none"
    case standard = "standard"
    case maximum = "maximum"
    
    var displayName: String {
        switch self {
        case .none:
            return "不压缩"
        case .standard:
            return "标准压缩"
        case .maximum:
            return "最大压缩"
        }
    }
    
    var compressionValue: Int {
        switch self {
        case .none:
            return 0
        case .standard:
            return 6
        case .maximum:
            return 9
        }
    }
}

// VNC质量等级枚举
enum VNCQualityLevel: String, Codable, CaseIterable {
    case lowest = "lowest"      // rfbEncodingQualityLevel0
    case low = "low"           // rfbEncodingQualityLevel2
    case standard = "standard"  // rfbEncodingQualityLevel5
    case high = "high"         // rfbEncodingQualityLevel7
    case highest = "highest"    // rfbEncodingQualityLevel9
    
    var displayName: String {
        switch self {
        case .lowest:
            return "最低质量"
        case .low:
            return "低质量"
        case .standard:
            return "标准质量"
        case .high:
            return "高质量"
        case .highest:
            return "最高质量"
        }
    }
    
    var qualityValue: Int {
        switch self {
        case .lowest:
            return 0
        case .low:
            return 2
        case .standard:
            return 5
        case .high:
            return 7
        case .highest:
            return 9
        }
    }
}

// VNC Session Model can be saved to AppStorage
struct VNCSessionOptions: Codable, Identifiable {
    var id = UUID()
    var vncUser: String = ""
    var vncPassword: String = ""
    var compressionLevel: VNCCompressionLevel = .standard
    var qualityLevel: VNCQualityLevel = .standard
    
    init() { }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.vncUser = try container.decodeIfPresent(String.self, forKey: .vncUser) ?? ""
        self.vncPassword = try container.decodeIfPresent(String.self, forKey: .vncPassword) ?? ""
        self.compressionLevel = try container.decodeIfPresent(VNCCompressionLevel.self, forKey: .compressionLevel) ?? .standard
        self.qualityLevel = try container.decodeIfPresent(VNCQualityLevel.self, forKey: .qualityLevel) ?? .standard
    }
}

// Video Codec Enum for ADB Session
enum ADBVideoCodec: String, Codable, CaseIterable {
    case h264 = "h264"
    case h265 = "h265"
}

// Audio Codec Enum for ADB Session
enum ADBAudioCodec: String, Codable, CaseIterable {
    case opus = "opus"
    case aac = "aac"
    case flac = "flac"
    case raw = "raw"
}

// ADB Session Model can be saved to AppStorage
struct ADBSessionOptions: Codable, Identifiable {
    var id = UUID()
    var maxScreenSize: String = ""
    var bitRate: String = ""
    var videoCodec: ADBVideoCodec = .h264
    var videoEncoder: String = ""
    var audioCodec: ADBAudioCodec = .opus
    var audioEncoder: String = ""
    var maxFPS: String = "60"
    var enableAudio: Bool = false
    var enableClipboardSync: Bool = true
    var volumeScale: Double = 1.0
    
    // 新虚拟显示器选项
    var startNewDisplay: Bool = false
    var displayWidth: String = ""
    var displayHeight: String = ""
    var displayDPI: String = "240"
    
    // 连接后关闭远程屏幕选项
    var turnScreenOff: Bool = true
    
    // 保持远程设备唤醒选项
    var stayAwake: Bool = false
    
    // 断开连接后关闭远程屏幕选项
    var powerOffOnClose: Bool = false
    
    // 强制 ADB 转发连接选项
    var forceAdbForward: Bool = false
    
    init() { }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode with default values for backward compatibility
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.maxScreenSize = try container.decodeIfPresent(String.self, forKey: .maxScreenSize) ?? ""
        self.bitRate = try container.decodeIfPresent(String.self, forKey: .bitRate) ?? ""
        self.videoEncoder = try container.decodeIfPresent(String.self, forKey: .videoEncoder) ?? ""
        self.audioCodec = try container.decodeIfPresent(ADBAudioCodec.self, forKey: .audioCodec) ?? .opus
        self.audioEncoder = try container.decodeIfPresent(String.self, forKey: .audioEncoder) ?? ""
        self.maxFPS = try container.decodeIfPresent(String.self, forKey: .maxFPS) ?? "60"
        self.enableAudio = try container.decodeIfPresent(Bool.self, forKey: .enableAudio) ?? false
        self.videoCodec = try container.decodeIfPresent(ADBVideoCodec.self, forKey: .videoCodec) ?? .h264
        self.enableClipboardSync = try container.decodeIfPresent(Bool.self, forKey: .enableClipboardSync) ?? true
        self.volumeScale = try container.decodeIfPresent(Double.self, forKey: .volumeScale) ?? 1.0
        
        // 解码新虚拟显示器选项
        self.startNewDisplay = try container.decodeIfPresent(Bool.self, forKey: .startNewDisplay) ?? false
        self.displayWidth = try container.decodeIfPresent(String.self, forKey: .displayWidth) ?? ""
        self.displayHeight = try container.decodeIfPresent(String.self, forKey: .displayHeight) ?? ""
        self.displayDPI = try container.decodeIfPresent(String.self, forKey: .displayDPI) ?? "240"
        
        // 解码连接后关闭远程屏幕选项，默认为 true
        self.turnScreenOff = try container.decodeIfPresent(Bool.self, forKey: .turnScreenOff) ?? true
        
        // 解码保持远程设备唤醒选项，默认为 false
        self.stayAwake = try container.decodeIfPresent(Bool.self, forKey: .stayAwake) ?? false
        
        // 解码断开连接后关闭远程屏幕选项，默认为 true
        self.powerOffOnClose = try container.decodeIfPresent(Bool.self, forKey: .powerOffOnClose) ?? true
        
        // 解码强制 ADB 转发连接选项，默认为 false
        self.forceAdbForward = try container.decodeIfPresent(Bool.self, forKey: .forceAdbForward) ?? false
    }
}

// Enum for device types
enum SessionDeviceType: String, Codable, CaseIterable {
    case vnc = "vnc"
    case adb = "adb"
}

// A ScrcpySession Model can be saved to AppStorage
struct ScrcpySessionModel: Codable, Identifiable {
    var id = UUID()
    var host: String
    var port: String
    var sessionName: String = ""
    var useTailscale: Bool = false
    
    var hostReal: String {
        get {
            // Strip vnc:// and adb://
            return host.replacingOccurrences(of: "vnc://", with: "").replacingOccurrences(of: "adb://", with: "")
        }
    }
    
    var deviceType: SessionDeviceType {
        get {
            // If host has explicit scheme prefix, use it
            if host.starts(with: "vnc://") {
                return .vnc
            }
            if host.starts(with: "adb://") {
                return .adb
            }
            
            // Auto-detect based on port number
            if let portNumber = Int(port) {
                // VNC ports: < 5555, 590x (5900-5909), or 1590x (15900-15909)
                if portNumber < 5555 || 
                   (portNumber >= 5900 && portNumber <= 5909) ||
                   (portNumber >= 15900 && portNumber <= 15909) {
                    return .vnc
                }
                // All other ports default to ADB
                return .adb
            }
            
            // Default fallback to VNC if port is not a valid number
            return .vnc
        }
    }
    
    var vncOptions: VNCSessionOptions = VNCSessionOptions()
    var adbOptions: ADBSessionOptions = ADBSessionOptions()
    
    init() {
        host = ""
        port = ""
        sessionName = ""
        useTailscale = false
    }
    
    init(host: String, port: String) {
        self.host = host
        self.port = port
        self.sessionName = ""
        self.useTailscale = false
    }
    
    init(host: String, port: String, sessionName: String = "") {
        self.host = host
        self.port = port
        self.sessionName = sessionName
        self.useTailscale = false
    }
    
    // Custom decoder for backward compatibility
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode required fields
        self.id = try container.decode(UUID.self, forKey: .id)
        self.host = try container.decode(String.self, forKey: .host)
        self.port = try container.decode(String.self, forKey: .port)
        
        // Decode optional fields with default values for backward compatibility
        self.sessionName = try container.decodeIfPresent(String.self, forKey: .sessionName) ?? ""
        self.useTailscale = try container.decodeIfPresent(Bool.self, forKey: .useTailscale) ?? false
        
        // Decode nested objects with error handling
        do {
            self.vncOptions = try container.decode(VNCSessionOptions.self, forKey: .vncOptions)
        } catch {
            self.vncOptions = VNCSessionOptions()
        }
        
        do {
            self.adbOptions = try container.decode(ADBSessionOptions.self, forKey: .adbOptions)
        } catch {
            self.adbOptions = ADBSessionOptions()
        }
    }
    
    func toDict() -> [String: Any] {
        do {
            let jsonData = try JSONEncoder().encode(self)
            guard var dictionary = try JSONSerialization.jsonObject(with: jsonData, options: .allowFragments) as? [String: Any] else {
                return [:]
            }
            dictionary["hostReal"] = hostReal
            dictionary["deviceType"] = deviceType.rawValue
            return dictionary
        } catch {
            print("Error encoding or serializing: \(error)")
            return [:]
        }
    }
}

class SessionManager {
    static let shared = SessionManager()
    private let keychain = KeychainSwift()
    
    private let sessionKey = "scrcpy.sessions"
    
    private init() {
        keychain.synchronizable = true
    }
    
    func saveSession(_ session: ScrcpySessionModel) {
        // Save session to keychain
        var sessions = loadSessions()
        
        // Check if session already exists
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            print("Updating session at index:", index)
            sessions[index] = session
            let data = try! JSONEncoder().encode(sessions)
            keychain.set(data, forKey: sessionKey)
            return
        }
        
        sessions.append(session)
        let data = try! JSONEncoder().encode(sessions)
        keychain.set(data, forKey: sessionKey)
    }
    
    func loadSessions() -> [ScrcpySessionModel] {
        // Load saved sessions from keychain
        if let data = keychain.getData(sessionKey) {
            do {
                let sessions = try JSONDecoder().decode([ScrcpySessionModel].self, from: data)
                return sessions
            } catch {
                print("Failed to decode sessions:", error)
                return []
            }
        }
        print("No sessions found")
        return []
    }
    
    func getSession(at index: Int) -> ScrcpySessionModel? {
        // Get session at index
        let sessions = loadSessions()
        if index < sessions.count {
            return sessions[index]
        }
        return nil
    }
    
    func getSession(id: UUID) -> ScrcpySessionModel? {
        // Get session by id
        let sessions = loadSessions()
        return sessions.first { $0.id == id }
    }
    
    func getSession(byName name: String) -> ScrcpySessionModel? {
        // Get session by name
        let sessions = loadSessions()
        return sessions.first { $0.sessionName.lowercased() == name.lowercased() }
    }
    
    func getSessions(host: String, port: String) -> [ScrcpySessionModel] {
        // Get sessions by host and port
        let sessions = loadSessions()
        return sessions.filter { $0.host == host && $0.port == port }
    }
    
    func deleteSession(id: UUID) {
        // Delete session by id
        var sessions = loadSessions()
        sessions.removeAll { $0.id == id }
        let data = try! JSONEncoder().encode(sessions)
        keychain.set(data, forKey: sessionKey)
    }
    
    func deleteSession(at index: Int) {
        // Delete session at index
        var sessions = loadSessions()
        sessions.remove(at: index)
        let data = try! JSONEncoder().encode(sessions)
        keychain.set(data, forKey: sessionKey)
    }
    
    func updateSession(at index: Int, with session: ScrcpySessionModel) {
        // Update session at index
        var sessions = loadSessions()
        sessions[index] = session
        let data = try! JSONEncoder().encode(sessions)
        keychain.set(data, forKey: sessionKey)
    }
    
    func clearSessions() {
        // Clear all saved sessions
        keychain.delete(sessionKey)
    }
}

// MARK: - Action Manager

class ActionManager: ObservableObject {
    static let shared = ActionManager()
    
    private let actionsKey = "ScrcpyActions"
    
    @Published var actions: [ScrcpyAction] = []
    
    private init() {
        loadActions()
    }
    
    func loadActions() {
        if let data = UserDefaults.standard.data(forKey: actionsKey) {
            do {
                let decoder = JSONDecoder()
                actions = try decoder.decode([ScrcpyAction].self, from: data)
                print("📋 [ActionManager] Loaded \(actions.count) actions")
            } catch {
                print("❌ [ActionManager] Failed to decode actions: \(error)")
                actions = []
            }
        } else {
            actions = []
        }
    }
    
    func saveAction(_ action: ScrcpyAction) {
        // Update existing action or add new one
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            actions[index] = action
        } else {
            actions.append(action)
        }
        
        saveActions()
    }
    
    func deleteAction(id: UUID) {
        actions.removeAll { $0.id == id }
        saveActions()
    }

    func duplicateAction(_ action: ScrcpyAction) {
        var newAction = action
        newAction.id = UUID() // Assign a new ID
        newAction.name = findNextAvailableName(for: action.name)
        newAction.createdAt = Date() // Update creation date
        
        actions.append(newAction)
        saveActions()
    }

    private func findNextAvailableName(for baseName: String) -> String {
        let existingNames = Set(actions.map { $0.name })
        var newName = baseName
        var counter = 1
        
        // Regex to find a number suffix like " (1)"
        let regex = try! NSRegularExpression(pattern: "^(.*?)(?:\\s*\\(\\d+\\))?$")
        let baseNameMatches = regex.matches(in: baseName, range: NSRange(baseName.startIndex..., in: baseName))
        
        var coreName = baseName
        if let match = baseNameMatches.first {
            if let coreRange = Range(match.range(at: 1), in: baseName) {
                coreName = String(baseName[coreRange])
            }
        }
        
        // Clean up trailing spaces from the core name
        coreName = coreName.trimmingCharacters(in: .whitespaces)
        
        while true {
            if counter == 1 && !existingNames.contains(newName) {
                return newName
            }
            
            newName = "\(coreName) (\(counter))"
            
            if !existingNames.contains(newName) {
                return newName
            }
            counter += 1
        }
    }
    
    private func saveActions() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(actions)
            UserDefaults.standard.set(data, forKey: actionsKey)
            print("💾 [ActionManager] Saved \(actions.count) actions")
        } catch {
            print("❌ [ActionManager] Failed to encode actions: \(error)")
        }
    }
    
    func getAction(by id: UUID) -> ScrcpyAction? {
        return actions.first { $0.id == id }
    }
    
    func getActions(for deviceId: UUID) -> [ScrcpyAction] {
        return actions.filter { $0.deviceId == deviceId }
    }
}

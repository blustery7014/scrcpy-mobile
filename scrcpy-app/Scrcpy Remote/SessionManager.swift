//
//  SessionManager.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/14/24.
//

import KeychainSwift
import Foundation

// VNC Session Model can be saved to AppStorage
struct VNCSessionOptions: Codable, Identifiable {
    var id = UUID()
    var vncUser: String = ""
    var vncPassword: String = ""
    
    init() { }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.vncUser = try container.decode(String.self, forKey: .vncUser)
        self.vncPassword = try container.decode(String.self, forKey: .vncPassword)
    }
}

// Codec Enum for ADB Session
enum ADBCodec: String, Codable, CaseIterable {
    case h264 = "h264"
    case h265 = "h265"
}

// ADB Session Model can be saved to AppStorage
struct ADBSessionOptions: Codable, Identifiable {
    var id = UUID()
    var maxScreenSize: String = ""
    var bitRate: String = ""
    var videoCodec: ADBCodec = .h264
    var videoEncoder: String = ""
    var maxFPS: String = "60"
    var enableAudio: Bool = false
    var enableClipboardSync: Bool = true
    var volumeScale: Double = 1.0
    
    init() { }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.maxScreenSize = try container.decode(String.self, forKey: .maxScreenSize)
        self.bitRate = try container.decode(String.self, forKey: .bitRate)
        self.videoEncoder = try container.decode(String.self, forKey: .videoEncoder)
        self.maxFPS = try container.decode(String.self, forKey: .maxFPS)
        do {
            self.enableAudio = try container.decode(Bool.self, forKey: .enableAudio)
        } catch {
            self.enableAudio = false
        }
        do {
            self.videoCodec = try container.decode(ADBCodec.self, forKey: .videoCodec)
        } catch {
            self.videoCodec = .h264
        }
        do {
            self.enableClipboardSync = try container.decode(Bool.self, forKey: .enableClipboardSync)
        } catch {
            self.enableClipboardSync = true
        }
        do {
            self.volumeScale = try container.decode(Double.self, forKey: .volumeScale)
        } catch {
            self.volumeScale = 1.0
        }
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
    
    var hostReal: String {
        get {
            // Strip vnc:// and adb://
            return host.replacingOccurrences(of: "vnc://", with: "").replacingOccurrences(of: "adb://", with: "")
        }
    }
    
    var deviceType: SessionDeviceType {
        get {
            if host.starts(with: "vnc://") || (5900...5909).contains(Int(port) ?? 0) {
                return .vnc
            }
            
            if host.starts(with: "adb://") || port.lengthOfBytes(using: .utf8) >= 4 {
                return .adb
            }
            
            return .vnc
        }
    }
    
    var vncOptions: VNCSessionOptions = VNCSessionOptions()
    var adbOptions: ADBSessionOptions = ADBSessionOptions()
    
    init() {
        host = ""
        port = ""
    }
    
    init(host: String, port: String) {
        self.host = host
        self.port = port
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

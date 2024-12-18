//
//  Scrcpy_Remote_Tests.swift
//  Scrcpy Remote Tests
//
//  Created by Ethan on 12/14/24.
//

import Testing
@testable import Scrcpy_Remote

struct Scrcpy_Remote_Tests {

    @Test func sessionManager_save() async throws {
        let sessionManager = SessionManager.shared
        var session = ScrcpySessionModel()
        session.host = "127.0.0.1"
        session.port = "5901"
        session.vncOptions.vncUser = "user"
        session.vncOptions.vncPassword = "password"
        sessionManager.saveSession(session)
        
        print("Saved session:", session)
    }
    
    @Test func sessionManager_load() async throws {
        let sessionManager = SessionManager.shared
        let sessions = sessionManager.loadSessions()
        print("Loaded sessions:", sessions)
    }

}

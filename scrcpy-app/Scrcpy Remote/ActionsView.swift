//
//  ActionsView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/8/24.
//

import SwiftUI
import UIKit

// MARK: - Action Models

enum ExecutionTiming: String, Codable, CaseIterable {
    case confirmation = "confirmation"
    case immediate = "immediate"
    case delayed = "delayed"
    
    var displayName: String {
        switch self {
        case .immediate: return "Execute Immediately"
        case .delayed: return "Execute After Delay"
        case .confirmation: return "Wait for Confirmation"
        }
    }
    
    var description: String {
        switch self {
        case .immediate: return "Actions will execute right after connection"
        case .delayed: return "Actions will execute after specified delay"
        case .confirmation: return "Actions will wait for manual confirmation"
        }
    }
    
    var icon: String {
        switch self {
        case .immediate: return "bolt.fill"
        case .delayed: return "clock.fill"
        case .confirmation: return "hand.raised.fill"
        }
    }
}

struct ScrcpyAction: Codable, Identifiable {
    var id = UUID()
    var name: String = ""
    var deviceId: UUID? = nil
    var deviceType: SessionDeviceType = .vnc
    var vncQuickActions: [VNCQuickAction] = []
    var adbCommands: String = ""
    var executionTiming: ExecutionTiming = .confirmation
    var delaySeconds: Int = 3
    var createdAt: Date = Date()
    
    // New ADB action properties
    var adbActionType: ADBActionType = .homeKey
    var adbInputKeysConfig: ADBInputKeysConfig = ADBInputKeysConfig()
    var adbShellConfig: ADBShellConfig = ADBShellConfig()
    
    init() {}
    
    init(name: String, deviceId: UUID, deviceType: SessionDeviceType) {
        self.name = name
        self.deviceId = deviceId
        self.deviceType = deviceType
    }
}

enum VNCQuickAction: String, Codable, CaseIterable {
    case missionControl = "Mission Control"
    case desktop = "Desktop"
    case launchpad = "Launchpad"
    case inputText = "Input Text"
    case screenshot = "Screenshot"
    case clipboard = "Clipboard"
    
    var icon: String {
        switch self {
        case .missionControl: return "rectangle.3.group"
        case .desktop: return "desktopcomputer"
        case .launchpad: return "grid"
        case .inputText: return "keyboard"
        case .screenshot: return "camera"
        case .clipboard: return "doc.on.clipboard"
        }
    }
    
    var description: String {
        switch self {
        case .missionControl: return "Show Mission Control"
        case .desktop: return "Show Desktop"
        case .launchpad: return "Open Launchpad"
        case .inputText: return "Input text to remote device"
        case .screenshot: return "Take screenshot"
        case .clipboard: return "Sync clipboard"
        }
    }
}

enum ADBActionType: String, Codable, CaseIterable {
    case homeKey = "Home Key"
    case switchKey = "Switch Key"
    case inputKeys = "Input Keys"
    case shellCommands = "Shell Commands"
    
    var icon: String {
        switch self {
        case .homeKey: return "house.fill"
        case .switchKey: return "arrow.triangle.2.circlepath"
        case .inputKeys: return "keyboard"
        case .shellCommands: return "terminal"
        }
    }
    
    var description: String {
        switch self {
        case .homeKey: return "Execute ADB Home key (keyevent 3)"
        case .switchKey: return "Execute ADB App Switch key (keyevent 187)"
        case .inputKeys: return "Execute ADB custom key sequence"
        case .shellCommands: return "Execute ADB shell commands"
        }
    }
}

struct ADBKeyAction: Codable, Identifiable {
    var id = UUID()
    var keyCode: Int
    var keyName: String
    
    init(keyCode: Int, keyName: String) {
        self.keyCode = keyCode
        self.keyName = keyName
    }
}

struct ADBInputKeysConfig: Codable {
    var keys: [ADBKeyAction] = []
    var intervalMs: Int = 100
}

struct ADBShellConfig: Codable {
    var commands: String = ""
    var intervalMs: Int = 0
}

enum AndroidKeyCode: Int, CaseIterable {
    // Basic Keys
    case unknown = 0
    case softLeft = 1
    case softRight = 2
    case home = 3
    case back = 4
    case call = 5
    case endCall = 6
    
    // Numbers
    case num0 = 7, num1 = 8, num2 = 9, num3 = 10, num4 = 11, num5 = 12, num6 = 13, num7 = 14, num8 = 15, num9 = 16
    
    // Special Characters
    case star = 17
    case pound = 18
    
    // D-Pad Navigation
    case dpadUp = 19
    case dpadDown = 20
    case dpadLeft = 21
    case dpadRight = 22
    case dpadCenter = 23
    
    // Volume & Hardware
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case camera = 27
    case clear = 28
    
    // Letters A-Z
    case a = 29, b = 30, c = 31, d = 32, e = 33, f = 34, g = 35, h = 36, i = 37, j = 38
    case k = 39, l = 40, m = 41, n = 42, o = 43, p = 44, q = 45, r = 46, s = 47, t = 48
    case u = 49, v = 50, w = 51, x = 52, y = 53, z = 54
    
    // Punctuation
    case comma = 55
    case period = 56
    case altLeft = 57
    case altRight = 58
    case shiftLeft = 59
    case shiftRight = 60
    case tab = 61
    case space = 62
    case sym = 63
    case explorer = 64
    case envelope = 65
    case enter = 66
    case del = 67
    case grave = 68
    case minus = 69
    case equals = 70
    case leftBracket = 71
    case rightBracket = 72
    case backslash = 73
    case semicolon = 74
    case apostrophe = 75
    case slash = 76
    case at = 77
    case num = 78
    case headsethook = 79
    case focus = 80
    case plus = 81
    case menu = 82
    case notification = 83
    case search = 84
    
    // Media Keys
    case mediaPlayPause = 85
    case mediaStop = 86
    case mediaNext = 87
    case mediaPrevious = 88
    case mediaRewind = 89
    case mediaFastForward = 90
    case mute = 91
    
    // Navigation
    case pageUp = 92
    case pageDown = 93
    case pictsymbols = 94
    case switchCharset = 95
    
    // Gaming
    case buttonA = 96
    case buttonB = 97
    case buttonC = 98
    case buttonX = 99
    case buttonY = 100
    case buttonZ = 101
    case buttonL1 = 102
    case buttonR1 = 103
    case buttonL2 = 104
    case buttonR2 = 105
    case buttonThumbL = 106
    case buttonThumbR = 107
    case buttonStart = 108
    case buttonSelect = 109
    case buttonMode = 110
    
    // Function Keys
    case escape = 111
    case forwardDel = 112
    case ctrlLeft = 113
    case ctrlRight = 114
    case capsLock = 115
    case scrollLock = 116
    case metaLeft = 117
    case metaRight = 118
    case function = 119
    case sysrq = 120
    case `break` = 121
    case moveHome = 122
    case moveEnd = 123
    case insert = 124
    case forward = 125
    case mediaPlay = 126
    case mediaPause = 127
    case mediaClose = 128
    case mediaEject = 129
    case mediaRecord = 130
    
    // F-Keys
    case f1 = 131, f2 = 132, f3 = 133, f4 = 134, f5 = 135, f6 = 136
    case f7 = 137, f8 = 138, f9 = 139, f10 = 140, f11 = 141, f12 = 142
    
    // Numeric Keypad
    case numLock = 143
    case numpad0 = 144, numpad1 = 145, numpad2 = 146, numpad3 = 147, numpad4 = 148
    case numpad5 = 149, numpad6 = 150, numpad7 = 151, numpad8 = 152, numpad9 = 153
    case numpadDivide = 154
    case numpadMultiply = 155
    case numpadSubtract = 156
    case numpadAdd = 157
    case numpadDot = 158
    case numpadComma = 159
    case numpadEnter = 160
    case numpadEquals = 161
    case numpadLeftParen = 162
    case numpadRightParen = 163
    
    // International
    case volumeMute = 164
    case info = 165
    case channelUp = 166
    case channelDown = 167
    case zoomIn = 168
    case zoomOut = 169
    case tv = 170
    case window = 171
    case guide = 172
    case dvr = 173
    case bookmark = 174
    case captions = 175
    case settings = 176
    case tvPower = 177
    case tvInput = 178
    case stbInput = 179
    case stbPower = 180
    case avrPower = 181
    case avrInput = 182
    case progRed = 183
    case progGreen = 184
    case progYellow = 185
    case progBlue = 186
    case appSwitch = 187
    case button1 = 188, button2 = 189, button3 = 190, button4 = 191, button5 = 192
    case button6 = 193, button7 = 194, button8 = 195, button9 = 196, button10 = 197
    case button11 = 198, button12 = 199, button13 = 200, button14 = 201, button15 = 202, button16 = 203
    
    // Language Switch
    case languageSwitch = 204
    
    // Manner Mode
    case mannerMode = 205
    
    // 3D Mode
    case the3dMode = 206
    
    // Contacts
    case contacts = 207
    case calendar = 208
    case music = 209
    case calculator = 210
    
    // Japanese Keys
    case zenkakuHankaku = 211
    case eisu = 212
    case muhenkan = 213
    case henkan = 214
    case katakanahiragana = 215
    case yen = 216
    case ro = 217
    case kana = 218
    case assist = 219
    case brightnessDown = 220
    case brightnessUp = 221
    
    // Media Controls
    case mediaAudioTrack = 222
    case sleep = 223
    case wakeup = 224
    case pairing = 225
    case mediaTopMenu = 226
    case the11 = 227, the12 = 228
    case lastChannel = 229
    case tvDataService = 230
    case voiceAssist = 231
    case tvRadioService = 232
    case tvTeletext = 233
    case tvNumberEntry = 234
    case tvTerrestrialAnalog = 235
    case tvTerrestrialDigital = 236
    case tvSatellite = 237
    case tvSatelliteBs = 238
    case tvSatelliteCs = 239
    case tvSatelliteService = 240
    case tvNetwork = 241
    case tvAntennaCable = 242
    case tvInputHdmi1 = 243, tvInputHdmi2 = 244, tvInputHdmi3 = 245, tvInputHdmi4 = 246
    case tvInputComposite1 = 247, tvInputComposite2 = 248
    case tvInputComponent1 = 249, tvInputComponent2 = 250
    case tvInputVga1 = 251
    case tvAudioDescription = 252
    case tvAudioDescriptionMixUp = 253
    case tvAudioDescriptionMixDown = 254
    case tvZoomMode = 255
    case tvContentsMenu = 256
    case tvMediaContextMenu = 257
    case tvTimerProgramming = 258
    case help = 259
    
    // Navigation Cluster
    case navigatePrevious = 260
    case navigateNext = 261
    case navigateIn = 262
    case navigateOut = 263
    
    // Primary Stem
    case stemPrimary = 264
    case stem1 = 265, stem2 = 266, stem3 = 267
    
    // Generic Stem
    case dpadUpLeft = 268
    case dpadDownLeft = 269
    case dpadUpRight = 270
    case dpadDownRight = 271
    
    // Skip Media
    case mediaSkipForward = 272
    case mediaSkipBackward = 273
    case mediaStepForward = 274
    case mediaStepBackward = 275
    case softSleep = 276
    
    // Cut/Copy/Paste
    case cut = 277
    case copy = 278
    case paste = 279
    
    // System Navigation
    case systemNavigationUp = 280
    case systemNavigationDown = 281
    case systemNavigationLeft = 282
    case systemNavigationRight = 283
    
    // All Apps
    case allApps = 284
    
    // Refresh
    case refresh = 285
    
    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .softLeft: return "Soft Left"
        case .softRight: return "Soft Right"
        case .home: return "Home"
        case .back: return "Back"
        case .call: return "Call"
        case .endCall: return "End Call"
        case .num0: return "0"
        case .num1: return "1"
        case .num2: return "2"
        case .num3: return "3"
        case .num4: return "4"
        case .num5: return "5"
        case .num6: return "6"
        case .num7: return "7"
        case .num8: return "8"
        case .num9: return "9"
        case .star: return "*"
        case .pound: return "#"
        case .dpadUp: return "D-pad Up"
        case .dpadDown: return "D-pad Down"
        case .dpadLeft: return "D-pad Left"
        case .dpadRight: return "D-pad Right"
        case .dpadCenter: return "D-pad Center"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .power: return "Power"
        case .camera: return "Camera"
        case .clear: return "Clear"
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .h: return "H"
        case .i: return "I"
        case .j: return "J"
        case .k: return "K"
        case .l: return "L"
        case .m: return "M"
        case .n: return "N"
        case .o: return "O"
        case .p: return "P"
        case .q: return "Q"
        case .r: return "R"
        case .s: return "S"
        case .t: return "T"
        case .u: return "U"
        case .v: return "V"
        case .w: return "W"
        case .x: return "X"
        case .y: return "Y"
        case .z: return "Z"
        case .comma: return ","
        case .period: return "."
        case .altLeft: return "Alt Left"
        case .altRight: return "Alt Right"
        case .shiftLeft: return "Shift Left"
        case .shiftRight: return "Shift Right"
        case .tab: return "Tab"
        case .space: return "Space"
        case .sym: return "Sym"
        case .explorer: return "Explorer"
        case .envelope: return "Envelope"
        case .enter: return "Enter"
        case .del: return "Delete"
        case .grave: return "`"
        case .minus: return "-"
        case .equals: return "="
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .backslash: return "\\"
        case .semicolon: return ";"
        case .apostrophe: return "'"
        case .slash: return "/"
        case .at: return "@"
        case .num: return "Num"
        case .headsethook: return "Headset Hook"
        case .focus: return "Focus"
        case .plus: return "+"
        case .menu: return "Menu"
        case .notification: return "Notification"
        case .search: return "Search"
        case .mediaPlayPause: return "Play/Pause"
        case .mediaStop: return "Stop"
        case .mediaNext: return "Next"
        case .mediaPrevious: return "Previous"
        case .mediaRewind: return "Rewind"
        case .mediaFastForward: return "Fast Forward"
        case .mute: return "Mute"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .pictsymbols: return "Pictsymbols"
        case .switchCharset: return "Switch Charset"
        case .buttonA: return "Button A"
        case .buttonB: return "Button B"
        case .buttonC: return "Button C"
        case .buttonX: return "Button X"
        case .buttonY: return "Button Y"
        case .buttonZ: return "Button Z"
        case .buttonL1: return "L1"
        case .buttonR1: return "R1"
        case .buttonL2: return "L2"
        case .buttonR2: return "R2"
        case .buttonThumbL: return "Left Thumb"
        case .buttonThumbR: return "Right Thumb"
        case .buttonStart: return "Start"
        case .buttonSelect: return "Select"
        case .buttonMode: return "Mode"
        case .escape: return "Escape"
        case .forwardDel: return "Forward Delete"
        case .ctrlLeft: return "Ctrl Left"
        case .ctrlRight: return "Ctrl Right"
        case .capsLock: return "Caps Lock"
        case .scrollLock: return "Scroll Lock"
        case .metaLeft: return "Meta Left"
        case .metaRight: return "Meta Right"
        case .function: return "Function"
        case .sysrq: return "SysRq"
        case .break: return "Break"
        case .moveHome: return "Home"
        case .moveEnd: return "End"
        case .insert: return "Insert"
        case .forward: return "Forward"
        case .mediaPlay: return "Play"
        case .mediaPause: return "Pause"
        case .mediaClose: return "Close"
        case .mediaEject: return "Eject"
        case .mediaRecord: return "Record"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .numLock: return "Num Lock"
        case .numpad0: return "Numpad 0"
        case .numpad1: return "Numpad 1"
        case .numpad2: return "Numpad 2"
        case .numpad3: return "Numpad 3"
        case .numpad4: return "Numpad 4"
        case .numpad5: return "Numpad 5"
        case .numpad6: return "Numpad 6"
        case .numpad7: return "Numpad 7"
        case .numpad8: return "Numpad 8"
        case .numpad9: return "Numpad 9"
        case .numpadDivide: return "Numpad /"
        case .numpadMultiply: return "Numpad *"
        case .numpadSubtract: return "Numpad -"
        case .numpadAdd: return "Numpad +"
        case .numpadDot: return "Numpad ."
        case .numpadComma: return "Numpad ,"
        case .numpadEnter: return "Numpad Enter"
        case .numpadEquals: return "Numpad ="
        case .numpadLeftParen: return "Numpad ("
        case .numpadRightParen: return "Numpad )"
        case .volumeMute: return "Volume Mute"
        case .info: return "Info"
        case .channelUp: return "Channel Up"
        case .channelDown: return "Channel Down"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .tv: return "TV"
        case .window: return "Window"
        case .guide: return "Guide"
        case .dvr: return "DVR"
        case .bookmark: return "Bookmark"
        case .captions: return "Captions"
        case .settings: return "Settings"
        case .tvPower: return "TV Power"
        case .tvInput: return "TV Input"
        case .stbInput: return "STB Input"
        case .stbPower: return "STB Power"
        case .avrPower: return "AVR Power"
        case .avrInput: return "AVR Input"
        case .progRed: return "Red"
        case .progGreen: return "Green"
        case .progYellow: return "Yellow"
        case .progBlue: return "Blue"
        case .appSwitch: return "App Switch"
        case .button1: return "Button 1"
        case .button2: return "Button 2"
        case .button3: return "Button 3"
        case .button4: return "Button 4"
        case .button5: return "Button 5"
        case .button6: return "Button 6"
        case .button7: return "Button 7"
        case .button8: return "Button 8"
        case .button9: return "Button 9"
        case .button10: return "Button 10"
        case .button11: return "Button 11"
        case .button12: return "Button 12"
        case .button13: return "Button 13"
        case .button14: return "Button 14"
        case .button15: return "Button 15"
        case .button16: return "Button 16"
        case .languageSwitch: return "Language Switch"
        case .mannerMode: return "Manner Mode"
        case .the3dMode: return "3D Mode"
        case .contacts: return "Contacts"
        case .calendar: return "Calendar"
        case .music: return "Music"
        case .calculator: return "Calculator"
        case .zenkakuHankaku: return "Zenkaku/Hankaku"
        case .eisu: return "Eisu"
        case .muhenkan: return "Muhenkan"
        case .henkan: return "Henkan"
        case .katakanahiragana: return "Katakana/Hiragana"
        case .yen: return "Yen"
        case .ro: return "Ro"
        case .kana: return "Kana"
        case .assist: return "Assist"
        case .brightnessDown: return "Brightness Down"
        case .brightnessUp: return "Brightness Up"
        case .mediaAudioTrack: return "Audio Track"
        case .sleep: return "Sleep"
        case .wakeup: return "Wake Up"
        case .pairing: return "Pairing"
        case .mediaTopMenu: return "Top Menu"
        case .the11: return "11"
        case .the12: return "12"
        case .lastChannel: return "Last Channel"
        case .tvDataService: return "TV Data Service"
        case .voiceAssist: return "Voice Assist"
        case .tvRadioService: return "TV Radio Service"
        case .tvTeletext: return "TV Teletext"
        case .tvNumberEntry: return "TV Number Entry"
        case .tvTerrestrialAnalog: return "TV Terrestrial Analog"
        case .tvTerrestrialDigital: return "TV Terrestrial Digital"
        case .tvSatellite: return "TV Satellite"
        case .tvSatelliteBs: return "TV Satellite BS"
        case .tvSatelliteCs: return "TV Satellite CS"
        case .tvSatelliteService: return "TV Satellite Service"
        case .tvNetwork: return "TV Network"
        case .tvAntennaCable: return "TV Antenna Cable"
        case .tvInputHdmi1: return "HDMI 1"
        case .tvInputHdmi2: return "HDMI 2"
        case .tvInputHdmi3: return "HDMI 3"
        case .tvInputHdmi4: return "HDMI 4"
        case .tvInputComposite1: return "Composite 1"
        case .tvInputComposite2: return "Composite 2"
        case .tvInputComponent1: return "Component 1"
        case .tvInputComponent2: return "Component 2"
        case .tvInputVga1: return "VGA 1"
        case .tvAudioDescription: return "Audio Description"
        case .tvAudioDescriptionMixUp: return "Audio Description Mix Up"
        case .tvAudioDescriptionMixDown: return "Audio Description Mix Down"
        case .tvZoomMode: return "TV Zoom Mode"
        case .tvContentsMenu: return "TV Contents Menu"
        case .tvMediaContextMenu: return "TV Media Context Menu"
        case .tvTimerProgramming: return "TV Timer Programming"
        case .help: return "Help"
        case .navigatePrevious: return "Navigate Previous"
        case .navigateNext: return "Navigate Next"
        case .navigateIn: return "Navigate In"
        case .navigateOut: return "Navigate Out"
        case .stemPrimary: return "Stem Primary"
        case .stem1: return "Stem 1"
        case .stem2: return "Stem 2"
        case .stem3: return "Stem 3"
        case .dpadUpLeft: return "D-pad Up-Left"
        case .dpadDownLeft: return "D-pad Down-Left"
        case .dpadUpRight: return "D-pad Up-Right"
        case .dpadDownRight: return "D-pad Down-Right"
        case .mediaSkipForward: return "Skip Forward"
        case .mediaSkipBackward: return "Skip Backward"
        case .mediaStepForward: return "Step Forward"
        case .mediaStepBackward: return "Step Backward"
        case .softSleep: return "Soft Sleep"
        case .cut: return "Cut"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .systemNavigationUp: return "System Navigation Up"
        case .systemNavigationDown: return "System Navigation Down"
        case .systemNavigationLeft: return "System Navigation Left"
        case .systemNavigationRight: return "System Navigation Right"
        case .allApps: return "All Apps"
        case .refresh: return "Refresh"
        }
    }
    
    var category: KeyCategory {
        switch self {
        case .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z:
            return .letters
        case .num0, .num1, .num2, .num3, .num4, .num5, .num6, .num7, .num8, .num9, .numpad0, .numpad1, .numpad2, .numpad3, .numpad4, .numpad5, .numpad6, .numpad7, .numpad8, .numpad9:
            return .numbers
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .dpadCenter, .dpadUpLeft, .dpadDownLeft, .dpadUpRight, .dpadDownRight, .navigatePrevious, .navigateNext, .navigateIn, .navigateOut, .systemNavigationUp, .systemNavigationDown, .systemNavigationLeft, .systemNavigationRight:
            return .navigation
        case .home, .back, .menu, .search, .notification, .appSwitch, .settings, .allApps, .assist, .voiceAssist, .help:
            return .system
        case .volumeUp, .volumeDown, .power, .mute, .volumeMute, .camera, .call, .endCall, .headsethook, .brightnessUp, .brightnessDown, .sleep, .wakeup:
            return .hardware
        case .mediaPlayPause, .mediaPlay, .mediaPause, .mediaStop, .mediaNext, .mediaPrevious, .mediaRewind, .mediaFastForward, .mediaSkipForward, .mediaSkipBackward, .mediaStepForward, .mediaStepBackward, .mediaClose, .mediaEject, .mediaRecord, .mediaAudioTrack, .mediaTopMenu:
            return .media
        case .enter, .del, .tab, .space, .escape, .forwardDel, .clear, .insert, .pageUp, .pageDown, .moveHome, .moveEnd, .numpadEnter, .refresh:
            return .control
        case .altLeft, .altRight, .shiftLeft, .shiftRight, .ctrlLeft, .ctrlRight, .metaLeft, .metaRight, .capsLock, .scrollLock, .numLock, .function:
            return .modifiers
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
            return .control
        default:
            return .others
        }
    }
}

enum KeyCategory: String, CaseIterable {
    case letters = "Letters"
    case numbers = "Numbers"
    case navigation = "Navigation"
    case system = "System"
    case hardware = "Hardware"
    case media = "Media"
    case control = "Control"
    case modifiers = "Modifiers"
    case others = "Others"
    
    var icon: String {
        switch self {
        case .letters: return "textformat.abc"
        case .numbers: return "textformat.123"
        case .navigation: return "arrow.up.arrow.down.arrow.left.arrow.right"
        case .system: return "gear"
        case .hardware: return "speaker.wave.2"
        case .media: return "play.circle"
        case .control: return "command"
        case .modifiers: return "option"
        case .others: return "ellipsis.circle"
        }
    }
}

// MARK: - ActionsView

struct ActionsView: View {
    @StateObject private var actionManager = ActionManager.shared
    @State private var showingNewAction = false
    @State private var editingAction: ScrcpyAction? = nil
    @State private var showingDeleteAlert = false
    @State private var actionToDelete: ScrcpyAction? = nil
    @State private var showingExecutionAlert = false
    @State private var actionToExecute: ScrcpyAction? = nil
    @State private var confirmationCallback: (() -> Void)? = nil
    
    var body: some View {
        Group {
            if actionManager.actions.isEmpty {
                VStack {
                    Image(systemName: "inset.filled.rectangle.and.cursorarrow")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.gray)
                    Text("No Scrcpy Actions")
                        .font(.title2)
                        .bold()
                        .padding(2)
                    Text("Start a new scrcpy action by tapping the + button.\nActions are used to start scrcpy sessions and execute custom actions automatically.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.init(top: 1, leading: 20, bottom: 1, trailing: 20))
                        .multilineTextAlignment(.center)
                }
            } else {
                List(actionManager.actions) { action in
                    ActionRowView(action: action, onExecute: { executeAction(action) })
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .contextMenu {
                            Button(action: {
                                executeAction(action)
                            }) {
                                Label("Execute Action", systemImage: "play")
                            }
                            Button(action: {
                                editingAction = action
                            }) {
                                Label("Edit Action", systemImage: "pencil")
                            }
                            Button(action: {
                                actionManager.duplicateAction(action)
                            }) {
                                Label("Duplicate Action", systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive, action: {
                                actionToDelete = action
                                showingDeleteAlert = true
                            }) {
                                Label("Delete Action", systemImage: "trash")
                            }
                        }
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("Scrcpy Actions")
        .sheet(isPresented: $showingNewAction) {
            NewActionView { action in
                actionManager.saveAction(action)
            }
        }
        .sheet(item: $editingAction) { action in
            EditActionView(action: action) { updatedAction in
                actionManager.saveAction(updatedAction)
            }
        }
        .alert("Delete Action", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let action = actionToDelete {
                    actionManager.deleteAction(id: action.id)
                }
                actionToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                actionToDelete = nil
            }
        } message: {
            if let action = actionToDelete {
                Text("Are you sure you want to delete '\(action.name)'?")
            }
        }
        .alert("Execute Action", isPresented: $showingExecutionAlert) {
            Button("Execute", role: .none) {
                if let callback = confirmationCallback {
                    callback()
                }
                actionToExecute = nil
                confirmationCallback = nil
            }
            Button("Cancel", role: .cancel) {
                actionToExecute = nil
                confirmationCallback = nil
            }
        } message: {
            if let action = actionToExecute {
                Text(getActionExecutionSummary(action))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowActionConfirmation"))) { notification in
            if let action = notification.object as? ScrcpyAction {
                print("📢 [ActionsView] Received action confirmation notification for: \(action.name)")
                // 使用全局Alert确保用户能看到
                WindowUtil.showGlobalActionConfirmation(action: action) {
                    SessionConnectionManager.shared.executeConfirmedAction()
                }
            }
        }
    }
    
    // MARK: - Action Execution Methods
    
    private func executeAction(_ action: ScrcpyAction) {
        guard let deviceId = action.deviceId else {
            print("❌ [ActionsView] Cannot execute action: no device ID")
            return
        }
        
        let sessions = SessionManager.shared.loadSessions()
        guard sessions.first(where: { $0.id == deviceId }) != nil else {
            print("❌ [ActionsView] Cannot execute action: device not found")
            return
        }
        
        // 对于所有类型的 action，都直接开始连接
        // confirmation 类型的确认会在连接成功后进行
        performActionExecution(action)
    }
    
    private func performActionExecution(_ action: ScrcpyAction) {
        guard let deviceId = action.deviceId else {
            print("❌ [ActionsView] Cannot execute action: no device ID")
            return
        }
        
        let sessions = SessionManager.shared.loadSessions()
        guard let session = sessions.first(where: { $0.id == deviceId }) else {
            print("❌ [ActionsView] Cannot execute action: device not found")
            return
        }
        
        print("🚀 [ActionsView] Executing action: \(action.name)")
        SessionConnectionManager.shared.connectToSessionWithAction(
            session,
            action: action,
            statusCallback: { status, message, isConnecting in
                // 这里可以添加执行状态的回调处理
                print("📊 [ActionsView] Action execution status: \(status.description)")
            },
            errorCallback: { title, message in
                print("❌ [ActionsView] Action execution error: \(title) - \(message)")
            },
            actionConfirmationCallback: { action, confirmCallback in
                // 在连接成功后弹出确认弹窗
                DispatchQueue.main.async {
                    // 保存确认回调到 SessionConnectionManager，通过通知触发 UI
                    SessionConnectionManager.shared.setConfirmationAction(action, callback: confirmCallback)
                    NotificationCenter.default.post(
                        name: Notification.Name("ShowActionConfirmation"),
                        object: action
                    )
                }
            }
        )
    }
    
    private func getActionExecutionSummary(_ action: ScrcpyAction) -> String {
        var summary = "About to execute '\(action.name)'\n\n"
        
        if action.deviceType == .vnc {
            if !action.vncQuickActions.isEmpty {
                summary += "VNC Actions:\n"
                for vncAction in action.vncQuickActions {
                    summary += "• \(vncAction.rawValue)\n"
                }
            }
        } else {
            // ADB Action details based on type
            switch action.adbActionType {
            case .homeKey:
                summary += "ADB Action: Home Key\n"
                summary += "• Execute 'adb shell input keyevent 3' (KEYCODE_HOME)"
                
            case .switchKey:
                summary += "ADB Action: Switch Key\n"
                summary += "• Execute 'adb shell input keyevent 187' (KEYCODE_APP_SWITCH)"
                
            case .inputKeys:
                summary += "ADB Action: Input Keys\n"
                if !action.adbInputKeysConfig.keys.isEmpty {
                    summary += "Key sequence (\(action.adbInputKeysConfig.intervalMs)ms interval):\n"
                    
                    // Display 4 keys per line to save space
                    let keys = action.adbInputKeysConfig.keys
                    var currentLine = ""
                    
                    for (index, keyAction) in keys.enumerated() {
                        let keyDisplay = "\(keyAction.keyName)(\(keyAction.keyCode))"
                        
                        if index % 4 == 0 {
                            // Start a new line
                            if !currentLine.isEmpty {
                                summary += currentLine + "\n"
                            }
                            currentLine = "\(index + 1). \(keyDisplay)"
                        } else {
                            // Add to current line
                            currentLine += "  \(index + 1). \(keyDisplay)"
                        }
                    }
                    
                    // Add the last line
                    if !currentLine.isEmpty {
                        summary += currentLine + "\n"
                    }
                } else {
                    summary += "• No keys configured"
                }
                
            case .shellCommands:
                summary += "ADB Action: Shell Commands\n"
                if !action.adbShellConfig.commands.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let commandLines = action.adbShellConfig.commands.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    
                    summary += "Commands (\(action.adbShellConfig.intervalMs)ms interval):\n"
                    
                    // Show first 5 commands
                    let displayCount = min(commandLines.count, 5)
                    for i in 0..<displayCount {
                        summary += "\(i + 1). \(commandLines[i])\n"
                    }
                    
                    // Show "and X more..." if there are more than 5 commands
                    if commandLines.count > 5 {
                        summary += "... and \(commandLines.count - 5) more commands"
                    }
                } else {
                    summary += "• No commands configured"
                }
            }
            
            // Show legacy commands if present (for backward compatibility)
            if !action.adbCommands.isEmpty {
                summary += "\n\nLegacy ADB Commands:\n\(action.adbCommands)"
            }
        }
        
        return summary
    }
}

// MARK: - Action Row View

struct ActionRowView: View {
    let action: ScrcpyAction
    let onExecute: () -> Void
    
    @State private var deviceName: String = "Unknown Device"
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                // Action name
                Text(action.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // Device info
                HStack(spacing: 6) {
                    // Device type icon
                    Image(systemName: action.deviceType == .vnc ? "desktopcomputer" : "iphone")
                        .font(.caption)
                        .foregroundColor(action.deviceType == .vnc ? .blue : .green)
                    
                    // Device name
                    Text(deviceName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                // Execute button
                Button(action: onExecute) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                // Execution timing
                HStack(spacing: 4) {
                    Image(systemName: action.executionTiming.icon)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(executionTimingText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 9) // Increased from 4 to 14 (added 10px)
        .onAppear {
            loadDeviceName()
        }
    }
    
    private var executionTimingText: String {
        switch action.executionTiming {
        case .confirmation:
            return "Confirm"
        case .immediate:
            return "Immediate"
        case .delayed:
            return "\(action.delaySeconds)s"
        }
    }
    
    private func loadDeviceName() {
        guard let deviceId = action.deviceId else {
            deviceName = "No Device"
            return
        }
        
        let sessions = SessionManager.shared.loadSessions()
        if let session = sessions.first(where: { $0.id == deviceId }) {
            deviceName = session.sessionName.isEmpty ? "\(session.hostReal):\(session.port)" : session.sessionName
        } else {
            deviceName = "Device Not Found"
        }
    }
}

#Preview {
    ActionsView()
}

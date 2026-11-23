import Foundation

/// macOS virtual key codes (kVK_*), shortcut parsing and media keys.
enum Keys {
    static let returnKey = 36, tab = 48, space = 49, delete = 51, escape = 53, forwardDelete = 117
    static let left = 123, right = 124, down = 125, up = 126
    static let home = 115, end = 119, pageUp = 116, pageDown = 121
    static let fKeys = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]   // F1–F12

    private static let chars: [String: Int] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50, " ": 49,
    ]

    private static let names: [String: Int] = {
        var n: [String: Int] = [
            "space": 49, "tab": 48, "return": 36, "enter": 36, "esc": 53, "escape": 53,
            "delete": 51, "backspace": 51, "fwddelete": 117, "del": 117,
            "up": 126, "down": 125, "left": 123, "right": 124,
            "home": 115, "end": 119, "pgup": 116, "pageup": 116, "pgdn": 121, "pagedown": 121,
            "plus": 24, "minus": 27,
        ]
        for (i, code) in fKeys.enumerated() { n["f\(i + 1)"] = code }
        return n
    }()

    static func code(forCharacter ch: String) -> Int? { chars[ch.lowercased()] }

    static func code(forName name: String) -> Int? {
        let k = name.lowercased()
        if let c = names[k] { return c }
        return k.count == 1 ? chars[k] : nil
    }

    /// "cmd+shift+4", "ctrl+up", "f11" → (code, mods)
    static func parseShortcut(_ text: String) -> (code: Int, mods: Mods)? {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var mods: Mods = []
        var code: Int?
        for (i, p) in parts.enumerated() {
            guard !p.isEmpty else { return nil }
            switch p {
            case "cmd", "command", "⌘": mods.insert(.cmd)
            case "shift", "⇧": mods.insert(.shift)
            case "ctrl", "control", "⌃": mods.insert(.ctrl)
            case "opt", "option", "alt", "⌥": mods.insert(.opt)
            case "fn": mods.insert(.fn)
            default:
                guard i == parts.count - 1, code == nil, let c = Keys.code(forName: p) else { return nil }
                code = c
            }
        }
        guard let c = code else { return nil }
        return (c, mods)
    }

    /// "cmd+shift+4" → "⇧⌘4"
    static func prettyShortcut(_ text: String) -> String {
        guard let mods = parseShortcut(text)?.mods else { return text }
        var out = ""
        if mods.contains(.ctrl) { out += "⌃" }
        if mods.contains(.opt) { out += "⌥" }
        if mods.contains(.shift) { out += "⇧" }
        if mods.contains(.cmd) { out += "⌘" }
        if mods.contains(.fn) { out += "fn " }
        let key = text.split(separator: "+").last.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        let pretty: [String: String] = [
            "space": "Espaço", "tab": "⇥", "return": "↩", "enter": "↩", "esc": "esc", "escape": "esc",
            "delete": "⌫", "backspace": "⌫", "fwddelete": "⌦", "del": "⌦", "up": "↑", "down": "↓",
            "left": "←", "right": "→", "home": "↖", "end": "↘", "pgup": "⇞", "pageup": "⇞",
            "pgdn": "⇟", "pagedown": "⇟", "plus": "+", "minus": "-",
        ]
        return out + (pretty[key] ?? key.uppercased())
    }
}

/// NX media keys (protocol MEDIA payload).
enum MediaKey: String, CaseIterable, Identifiable, Codable {
    case play, prev, next, voldown, volup, mute, brightdown, brightup

    var id: String { rawValue }

    var code: UInt8 {
        switch self {
        case .volup: return 0
        case .voldown: return 1
        case .brightup: return 2
        case .brightdown: return 3
        case .mute: return 7
        case .play: return 16
        case .next: return 17
        case .prev: return 18
        }
    }

    var label: String {
        switch self {
        case .play: return "Play"
        case .prev: return "Anterior"
        case .next: return "Próxima"
        case .voldown: return "Vol −"
        case .volup: return "Vol +"
        case .mute: return "Mudo"
        case .brightdown: return "Brilho −"
        case .brightup: return "Brilho +"
        }
    }

    var symbol: String {
        switch self {
        case .play: return "playpause.fill"
        case .prev: return "backward.fill"
        case .next: return "forward.fill"
        case .voldown: return "speaker.wave.1.fill"
        case .volup: return "speaker.wave.3.fill"
        case .mute: return "speaker.slash.fill"
        case .brightdown: return "sun.min.fill"
        case .brightup: return "sun.max.fill"
        }
    }
}

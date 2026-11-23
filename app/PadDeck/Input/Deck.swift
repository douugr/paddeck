import Foundation

/// One shortcut button.
struct Slot: Codable, Equatable {
    enum Action: String, Codable, CaseIterable, Identifiable {
        case shortcut, text, open, media
        var id: String { rawValue }
        var label: String {
            switch self {
            case .shortcut: return String(localized: "Shortcut")
            case .text: return String(localized: "Text")
            case .open: return String(localized: "Open app")
            case .media: return String(localized: "Media")
            }
        }
    }

    var title: String
    var action: Action
    var value: String
    var color: Int

    var subtitle: String {
        switch action {
        case .shortcut: return Keys.prettyShortcut(value)
        case .text: return "“\(value)”"
        case .open: return value
        case .media: return MediaKey(rawValue: value)?.label ?? value
        }
    }

    var isValid: Bool {
        switch action {
        case .shortcut: return Keys.parseShortcut(value) != nil
        case .text, .open: return !value.isEmpty
        case .media: return MediaKey(rawValue: value) != nil
        }
    }

    func perform() {
        let c = Connection.shared
        switch action {
        case .shortcut:
            if let k = Keys.parseShortcut(value) { c.sendKey(k.code, mods: k.mods) }
        case .text: c.sendText(value)
        case .open: c.sendOpen(value)
        case .media: if let m = MediaKey(rawValue: value) { c.sendMedia(m) }
        }
    }
}

/// The shortcut deck: 3 pages × 15 buttons, saved as JSON in Documents.
final class Deck {
    static let shared = Deck()
    static let pages = 3
    static let perPage = 15
    static var count: Int { pages * perPage }

    private(set) var slots: [Slot?]

    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("deck.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Deck.url),
           let saved = try? JSONDecoder().decode([Slot?].self, from: data), saved.count == Deck.count {
            slots = saved
        } else {
            slots = Deck.defaults
        }
    }

    subscript(i: Int) -> Slot? {
        get { slots.indices.contains(i) ? slots[i] : nil }
        set {
            guard slots.indices.contains(i) else { return }
            slots[i] = newValue
            save()
        }
    }

    func resetToDefaults() {
        slots = Deck.defaults
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(slots) { try? data.write(to: Deck.url, options: .atomic) }
    }

    // colors: 0 gray, 1 blue, 2 purple, 3 green, 4 orange, 5 red
    private static var defaults: [Slot?] {
        func s(_ t: String, _ a: Slot.Action, _ v: String, _ c: Int) -> Slot? { Slot(title: t, action: a, value: v, color: c) }
        var all: [Slot?] = [
            s("Spotlight", .shortcut, "cmd+space", 1),
            s(String(localized: "Switch app"), .shortcut, "cmd+tab", 1),
            s("Mission Control", .shortcut, "ctrl+up", 2),
            s(String(localized: "Desktop ←"), .shortcut, "ctrl+left", 2),
            s(String(localized: "Desktop →"), .shortcut, "ctrl+right", 2),
            s(String(localized: "Copy"), .shortcut, "cmd+c", 0),
            s(String(localized: "Paste"), .shortcut, "cmd+v", 0),
            s(String(localized: "Undo"), .shortcut, "cmd+z", 0),
            s(String(localized: "Screenshot"), .shortcut, "cmd+shift+4", 3),
            s(String(localized: "Close window"), .shortcut, "cmd+w", 5),
            s(String(localized: "Previous"), .media, "prev", 4),
            s(String(localized: "Play / Pause"), .media, "play", 4),
            s(String(localized: "Next"), .media, "next", 4),
            s(String(localized: "Vol −"), .media, "voldown", 4),
            s(String(localized: "Vol +"), .media, "volup", 4),

            s("Safari", .open, "Safari", 1),
            s("Finder", .open, "Finder", 1),
            s("Terminal", .open, "Terminal", 1),
            s(String(localized: "Music"), .open, "Music", 1),
            s(String(localized: "Settings"), .open, "System Settings", 1),
            s(String(localized: "New tab"), .shortcut, "cmd+t", 0),
            s(String(localized: "Reload"), .shortcut, "cmd+r", 0),
            s(String(localized: "Find"), .shortcut, "cmd+f", 0),
            s(String(localized: "Save"), .shortcut, "cmd+s", 0),
            s(String(localized: "Full screen"), .shortcut, "ctrl+cmd+f", 2),
            s(String(localized: "Mute"), .media, "mute", 4),
            s(String(localized: "Show desktop"), .shortcut, "f11", 2),
            s(String(localized: "Hide app"), .shortcut, "cmd+h", 2),
            s(String(localized: "Quit app"), .shortcut, "cmd+q", 5),
            s(String(localized: "Lock screen"), .shortcut, "ctrl+cmd+q", 5),
        ]
        while all.count < count { all.append(nil) }
        return all
    }
}

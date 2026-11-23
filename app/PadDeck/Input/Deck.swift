import Foundation

/// One shortcut button.
struct Slot: Codable, Equatable {
    enum Action: String, Codable, CaseIterable, Identifiable {
        case shortcut, text, open, media
        var id: String { rawValue }
        var label: String {
            switch self {
            case .shortcut: return "Atalho"
            case .text: return "Texto"
            case .open: return "Abrir app"
            case .media: return "Mídia"
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
            s("Trocar app", .shortcut, "cmd+tab", 1),
            s("Mission Control", .shortcut, "ctrl+up", 2),
            s("Mesa ←", .shortcut, "ctrl+left", 2),
            s("Mesa →", .shortcut, "ctrl+right", 2),
            s("Copiar", .shortcut, "cmd+c", 0),
            s("Colar", .shortcut, "cmd+v", 0),
            s("Desfazer", .shortcut, "cmd+z", 0),
            s("Captura", .shortcut, "cmd+shift+4", 3),
            s("Fechar janela", .shortcut, "cmd+w", 5),
            s("Anterior", .media, "prev", 4),
            s("Play / Pausa", .media, "play", 4),
            s("Próxima", .media, "next", 4),
            s("Vol −", .media, "voldown", 4),
            s("Vol +", .media, "volup", 4),

            s("Safari", .open, "Safari", 1),
            s("Finder", .open, "Finder", 1),
            s("Terminal", .open, "Terminal", 1),
            s("Música", .open, "Music", 1),
            s("Ajustes", .open, "System Settings", 1),
            s("Nova aba", .shortcut, "cmd+t", 0),
            s("Recarregar", .shortcut, "cmd+r", 0),
            s("Buscar", .shortcut, "cmd+f", 0),
            s("Salvar", .shortcut, "cmd+s", 0),
            s("Tela cheia", .shortcut, "ctrl+cmd+f", 2),
            s("Mudo", .media, "mute", 4),
            s("Mostrar mesa", .shortcut, "f11", 2),
            s("Esconder app", .shortcut, "cmd+h", 2),
            s("Sair do app", .shortcut, "cmd+q", 5),
            s("Bloquear tela", .shortcut, "ctrl+cmd+q", 5),
        ]
        while all.count < count { all.append(nil) }
        return all
    }
}

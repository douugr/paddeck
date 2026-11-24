import UIKit
import SwiftUI

/// A color profile. Most of them match a Mac finish, so the iPhone/iPad looks like part of it:
/// the trackpad takes the color of the Mac's trackpad, the keys match its keyboard.
struct Palette: Identifiable, Equatable {
    enum Line: String, CaseIterable {
        case paddeck = "PadDeck", neo = "MacBook Neo", air = "MacBook Air", pro = "MacBook Pro", imac = "iMac"
    }

    let id: String
    let name: String          // localization key (English)
    let line: Line
    let light: Bool           // light surfaces: dark text, light status bar and system UI
    let background: UIColor
    let bar: UIColor
    let surface: UIColor      // trackpad and click buttons
    let surfaceActive: UIColor
    let key: UIColor
    let keyDark: UIColor      // special keys and the scroll strip
    let keyActive: UIColor
    let keyText: UIColor
    let text: UIColor         // text on the bar and on the trackpad
    let accent: UIColor

    var localizedName: String { NSLocalizedString(name, comment: "Color profile") }

    static func == (a: Palette, b: Palette) -> Bool { a.id == b.id }
}

enum Theme {
    static func rgb(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    /// The profile in use. Read once and kept until `reload()`, so a change in Settings
    /// is applied as a whole when the screen is rebuilt.
    private(set) static var current = palette(id: Prefs.theme)

    /// Posted after `reload()` picks up a new profile.
    static let changed = Notification.Name("PadDeckThemeChanged")

    /// Rereads the setting; true when the profile changed.
    @discardableResult
    static func reload() -> Bool {
        let p = palette(id: Prefs.theme)
        guard p != current else { return false }
        current = p
        return true
    }

    static func palette(id: String) -> Palette { all.first { $0.id == id } ?? all[0] }

    static var isLight: Bool { current.light }
    static var background: UIColor { current.background }
    static var bar: UIColor { current.bar }
    static var surface: UIColor { current.surface }
    static var surfaceActive: UIColor { current.surfaceActive }
    static var key: UIColor { current.key }
    static var keyDark: UIColor { current.keyDark }
    static var keyActive: UIColor { current.keyActive }
    static var keyText: UIColor { current.keyText }
    static var accent: UIColor { current.accent }
    static func text(_ alpha: CGFloat = 1) -> UIColor { current.text.withAlphaComponent(alpha) }

    static let ok = rgb(0x30D158)
    static let warn = rgb(0xFF9F0A)
    static let off = rgb(0xFF453A)

    /// Deck button colors (dark enough for white text, on any profile).
    static let deckColors: [UIColor] = [rgb(0x4A4A50), rgb(0x1A6FD8), rgb(0x5E4BC4),
                                        rgb(0x2E8B45), rgb(0xD9730D), rgb(0xC9342B)]

    /// True on phones / narrow windows (Split View, Slide Over).
    static func isCompact(_ view: UIView) -> Bool {
        view.traitCollection.horizontalSizeClass == .compact || view.bounds.width < 600
    }

    // MARK: Profiles

    private static let black: UInt32 = 0x1C1C1E

    /// Dark finish: black keys, dark trackpad.
    private static func dark(_ id: String, _ name: String, _ line: Palette.Line,
                             bg: UInt32, bar: UInt32, surface: UInt32, active: UInt32,
                             key: UInt32, keyDark: UInt32, keyActive: UInt32, accent: UInt32) -> Palette {
        Palette(id: id, name: name, line: line, light: false,
                background: rgb(bg), bar: rgb(bar), surface: rgb(surface), surfaceActive: rgb(active),
                key: rgb(key), keyDark: rgb(keyDark), keyActive: rgb(keyActive),
                keyText: .white, text: .white, accent: rgb(accent))
    }

    /// Light aluminium with the black keyboard of the MacBook Air / Pro.
    private static func lightBlackKeys(_ id: String, _ name: String, _ line: Palette.Line,
                                       bg: UInt32, bar: UInt32, surface: UInt32, active: UInt32,
                                       text: UInt32, accent: UInt32) -> Palette {
        Palette(id: id, name: name, line: line, light: true,
                background: rgb(bg), bar: rgb(bar), surface: rgb(surface), surfaceActive: rgb(active),
                key: rgb(black), keyDark: rgb(0x2C2C2F), keyActive: rgb(0x55555A),
                keyText: .white, text: rgb(text), accent: rgb(accent))
    }

    /// Light finish with a keyboard in the same color family (MacBook Neo, iMac).
    private static func lightColorKeys(_ id: String, _ name: String, _ line: Palette.Line,
                                       bg: UInt32, bar: UInt32, surface: UInt32, active: UInt32,
                                       key: UInt32, keyDark: UInt32, keyActive: UInt32,
                                       keyText: UInt32, text: UInt32, accent: UInt32) -> Palette {
        Palette(id: id, name: name, line: line, light: true,
                background: rgb(bg), bar: rgb(bar), surface: rgb(surface), surfaceActive: rgb(active),
                key: rgb(key), keyDark: rgb(keyDark), keyActive: rgb(keyActive),
                keyText: rgb(keyText), text: rgb(text), accent: rgb(accent))
    }

    /// iMac: the trackpad takes the soft color of the front, the accent the bold color of the
    /// back; white Magic Keyboard keys.
    private static func imac(_ id: String, _ name: String, front: UInt32, back: UInt32,
                             bg: UInt32, bar: UInt32, active: UInt32, text: UInt32) -> Palette {
        lightColorKeys(id, name, .imac, bg: bg, bar: bar, surface: front, active: active,
                       key: 0xFFFFFF, keyDark: 0xEDEDF0, keyActive: active,
                       keyText: black, text: text, accent: back)
    }

    static let all: [Palette] = [
        dark("dark", "Dark", .paddeck, bg: 0x121214, bar: 0x1C1C1F, surface: 0x26262A, active: 0x2E2E33,
             key: 0x3A3A3F, keyDark: 0x2A2A2E, keyActive: 0x5A5A62, accent: 0x0A84FF),

        // MacBook Neo: colored aluminium and a lighter keyboard in the same color.
        lightColorKeys("neo-silver", "Silver", .neo, bg: 0xE4E5E8, bar: 0xD8D9DD, surface: 0xD0D1D5, active: 0xC3C4C9,
                       key: 0xF7F7F9, keyDark: 0xE6E7EA, keyActive: 0xC6C7CC, keyText: black, text: 0x2E2F33, accent: 0x0A6FE0),
        lightColorKeys("neo-blush", "Blush", .neo, bg: 0xF3E4E1, bar: 0xEBD8D4, surface: 0xE5CEC9, active: 0xD9BFB9,
                       key: 0xFBF1EF, keyDark: 0xF0E0DC, keyActive: 0xD8BBB4, keyText: 0x4A2E2A, text: 0x5A3A35, accent: 0xC25B73),
        lightColorKeys("neo-citrus", "Citrus", .neo, bg: 0xEEF0CB, bar: 0xE5E8B8, surface: 0xDDE1A8, active: 0xD1D696,
                       key: 0xF8F9E3, keyDark: 0xEDEFCD, keyActive: 0xD2D69C, keyText: 0x363A10, text: 0x42461A, accent: 0x6F7F0A),
        dark("neo-indigo", "Indigo", .neo, bg: 0x1D2140, bar: 0x252A4E, surface: 0x2F355E, active: 0x39406C,
             key: 0x434A80, keyDark: 0x363C6C, keyActive: 0x5C66A3, accent: 0x93A5FF),

        // MacBook Air: aluminium with a black keyboard.
        lightBlackKeys("air-skyblue", "Sky Blue", .air, bg: 0xDCE6EE, bar: 0xD0DCE6, surface: 0xC5D4E0, active: 0xB7C8D6,
                       text: 0x2B3945, accent: 0x2F7DC0),
        lightBlackKeys("air-silver", "Silver", .air, bg: 0xE3E4E7, bar: 0xD7D8DC, surface: 0xCFD0D4, active: 0xC2C3C8,
                       text: 0x2E2F33, accent: 0x0A6FE0),
        lightBlackKeys("air-starlight", "Starlight", .air, bg: 0xEFE9DF, bar: 0xE6DED1, surface: 0xDDD4C5, active: 0xD1C6B5,
                       text: 0x3D372E, accent: 0x9A733C),
        dark("air-midnight", "Midnight", .air, bg: 0x141822, bar: 0x1D2230, surface: 0x272D3C, active: 0x313849,
             key: 0x343B50, keyDark: 0x292F41, keyActive: 0x4E5770, accent: 0x5E9CFF),
        dark("air-spacegray", "Space Gray", .air, bg: 0x2E2F33, bar: 0x38393D, surface: 0x45464B, active: 0x4F5055,
             key: 0x18181A, keyDark: 0x222224, keyActive: 0x5A5B60, accent: 0x0A84FF),

        // MacBook Pro
        dark("pro-spaceblack", "Space Black", .pro, bg: 0x0A0A0B, bar: 0x141415, surface: 0x1E1F21, active: 0x27282B,
             key: 0x303134, keyDark: 0x242527, keyActive: 0x4B4C50, accent: 0x0A84FF),
        lightBlackKeys("pro-silver", "Silver", .pro, bg: 0xE3E4E7, bar: 0xD7D8DC, surface: 0xCFD0D4, active: 0xC2C3C8,
                       text: 0x2E2F33, accent: 0x0A6FE0),

        // iMac 24"
        imac("imac-blue", "Blue", front: 0xCADDEF, back: 0x2D6BB4, bg: 0xDCE8F4, bar: 0xD1E1F0, active: 0xB8CEE5, text: 0x1F3A5C),
        imac("imac-purple", "Purple", front: 0xDDD4EE, back: 0x7653B5, bg: 0xE9E3F5, bar: 0xE1D9F0, active: 0xCDC1E4, text: 0x3E2B60),
        imac("imac-pink", "Pink", front: 0xF2D5D8, back: 0xCF4A6B, bg: 0xF8E5E7, bar: 0xF4DCDF, active: 0xE7C2C7, text: 0x5E2232),
        imac("imac-orange", "Orange", front: 0xF6D7C2, back: 0xDC6427, bg: 0xFAE6D8, bar: 0xF7DECC, active: 0xEAC4AA, text: 0x5C2E12),
        imac("imac-yellow", "Yellow", front: 0xF4E6B6, back: 0xC9970E, bg: 0xF9F0D2, bar: 0xF6EAC2, active: 0xE7D59C, text: 0x4F3D06),
        imac("imac-green", "Green", front: 0xD0E7D0, back: 0x3A8A4B, bg: 0xE1F0E1, bar: 0xD8EBD8, active: 0xBCD9BD, text: 0x1F4A27),
        imac("imac-silver", "Silver", front: 0xE5E6E9, back: 0x6B6E75, bg: 0xEEEFF1, bar: 0xE7E8EB, active: 0xD0D1D6, text: 0x2E2F33),
    ]
}

// MARK: - SwiftUI screens (Settings, connect, shortcut editor)

extension View {
    /// Background, bars, text, tint and light/dark style of a List or Form in the given profile.
    func themedList(_ p: Palette = Theme.current) -> some View {
        self.scrollContentBackground(.hidden)
            .background(Color(p.background).ignoresSafeArea())
            .foregroundStyle(Color(p.text))
            .tint(Color(p.accent))
            .toolbarBackground(Color(p.bar), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .preferredColorScheme(p.light ? .light : .dark)
    }

    /// Row background for a Section, in the given profile.
    func themedRows(_ p: Palette = Theme.current) -> some View {
        listRowBackground(Color(p.surface))
    }
}

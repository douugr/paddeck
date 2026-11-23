import UIKit

enum Theme {
    static func rgb(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    static let background = rgb(0x121214)
    static let bar = rgb(0x1C1C1F)
    static let surface = rgb(0x26262A)
    static let surfaceActive = rgb(0x2E2E33)
    static let key = rgb(0x3A3A3F)
    static let keyDark = rgb(0x2A2A2E)
    static let keyActive = rgb(0x5A5A62)
    static let accent = rgb(0x0A84FF)
    static let ok = rgb(0x30D158)
    static let warn = rgb(0xFF9F0A)
    static let off = rgb(0xFF453A)

    /// Deck button colors (dark enough for white text).
    static let deckColors: [UIColor] = [rgb(0x4A4A50), rgb(0x1A6FD8), rgb(0x5E4BC4),
                                        rgb(0x2E8B45), rgb(0xD9730D), rgb(0xC9342B)]

    /// True on phones / narrow windows (Split View, Slide Over).
    static func isCompact(_ view: UIView) -> Bool {
        view.traitCollection.horizontalSizeClass == .compact || view.bounds.width < 600
    }
}

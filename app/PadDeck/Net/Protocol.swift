import Foundation

/// Wire protocol shared with the Mac agent (see docs/PROTOCOL.md).
enum Proto {
    static let tcpPort: UInt16 = 47816
    static let udpPort: UInt16 = 47817
    static let usbPort: UInt16 = 47818
    static let bonjourType = "_paddeck._tcp"
    static let version: UInt8 = 1

    enum Out: UInt8 {
        case hello = 0x01, ping = 0x02
        case button = 0x10, move = 0x11, scroll = 0x12
        case text = 0x20, key = 0x21, media = 0x22, open = 0x23
    }

    enum In: UInt8 {
        case welcome = 0x81, denied = 0x82, pong = 0x83
    }

    static func frame(_ type: Out, _ payload: Data = Data()) -> Data {
        let len = min(payload.count, 65535)
        var d = Data([type.rawValue, UInt8(len >> 8), UInt8(len & 0xff)])
        d.append(payload.prefix(len))
        return d
    }

    static func be16(_ v: Int) -> [UInt8] {
        let x = UInt16(bitPattern: Int16(clamping: v))
        return [UInt8(x >> 8), UInt8(x & 0xff)]
    }
}

/// Modifier bits (same values as the protocol).
struct Mods: OptionSet, Hashable {
    let rawValue: UInt8
    static let shift = Mods(rawValue: 1 << 0)
    static let ctrl = Mods(rawValue: 1 << 1)
    static let opt = Mods(rawValue: 1 << 2)
    static let cmd = Mods(rawValue: 1 << 3)
    static let fn = Mods(rawValue: 1 << 4)

    /// Modifiers that turn a letter into a shortcut instead of text.
    static let commandLike: Mods = [.ctrl, .opt, .cmd, .fn]
}

enum MouseButton: UInt8 { case left = 0, right = 1, middle = 2 }
enum PressAction: UInt8 { case down = 0, up = 1, press = 2 }

extension Data {
    func u8(_ i: Int) -> UInt8 { self[startIndex + i] }
}

import Foundation

/// User settings (UserDefaults). Keys match the iOS 8 app where it makes sense.
enum Prefs {
    private static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            "pointerSpeed": 1.6,
            "scrollSpeed": 1.5,
            "naturalScroll": true,
            "tapToClick": true,
            "tapToDrag": true,
            "keepAwake": true,
            "showKeyboard": true,
            "keyboardOnTop": false,
            "keyClick": true,
            "keyHaptics": true,
        ])
    }

    static var pointerSpeed: Double { get { d.double(forKey: "pointerSpeed") } set { d.set(newValue, forKey: "pointerSpeed") } }
    static var scrollSpeed: Double { get { d.double(forKey: "scrollSpeed") } set { d.set(newValue, forKey: "scrollSpeed") } }
    static var naturalScroll: Bool { get { d.bool(forKey: "naturalScroll") } set { d.set(newValue, forKey: "naturalScroll") } }
    static var tapToClick: Bool { get { d.bool(forKey: "tapToClick") } set { d.set(newValue, forKey: "tapToClick") } }
    static var tapToDrag: Bool { get { d.bool(forKey: "tapToDrag") } set { d.set(newValue, forKey: "tapToDrag") } }
    static var keepAwake: Bool { get { d.bool(forKey: "keepAwake") } set { d.set(newValue, forKey: "keepAwake") } }
    static var showKeyboard: Bool { get { d.bool(forKey: "showKeyboard") } set { d.set(newValue, forKey: "showKeyboard") } }
    static var keyboardOnTop: Bool { get { d.bool(forKey: "keyboardOnTop") } set { d.set(newValue, forKey: "keyboardOnTop") } }
    static var keyClick: Bool { get { d.bool(forKey: "keyClick") } set { d.set(newValue, forKey: "keyClick") } }
    static var keyHaptics: Bool { get { d.bool(forKey: "keyHaptics") } set { d.set(newValue, forKey: "keyHaptics") } }

    /// Last Mac connected to: Bonjour name and/or IP.
    static var lastMacName: String? { get { d.string(forKey: "lastName") } set { d.set(newValue, forKey: "lastName") } }
    static var lastMacHost: String? { get { d.string(forKey: "lastHost") } set { d.set(newValue, forKey: "lastHost") } }

    /// PINs by Mac name or host.
    static func pin(for key: String) -> String? {
        (d.dictionary(forKey: "pins") as? [String: String])?[key]
    }

    static func setPin(_ pin: String?, for keys: [String]) {
        var pins = (d.dictionary(forKey: "pins") as? [String: String]) ?? [:]
        for k in keys { pins[k] = pin }
        d.set(pins, forKey: "pins")
    }
}

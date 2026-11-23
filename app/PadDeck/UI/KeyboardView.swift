import UIKit
import AudioToolbox

/// One key of the layout.
struct KeySpec {
    enum Kind { case char, key, mod, sys, layer, media }

    var kind: Kind
    var label: String
    var shiftLabel: String? = nil
    var char: String = ""          // text sent
    var shiftChar: String = ""     // text sent with shift
    var code: Int = -1             // virtual key code
    var width: CGFloat = 1         // units (11 per row)
    var mod: Mods = []
    var target: String = ""        // layer name
    var media: MediaKey? = nil

    var isSpace: Bool { kind == .char && char == " " }
    var isLetter: Bool { kind == .char && char.uppercased() == shiftChar && char != shiftChar }

    static func ch(_ c: String, _ shifted: String? = nil) -> KeySpec {
        let s = shifted ?? c
        let letter = c.uppercased() == s
        return KeySpec(kind: .char, label: letter ? s : c, shiftLabel: letter ? nil : s,
                       char: c, shiftChar: s, code: Keys.code(forCharacter: c) ?? -1)
    }
    static func key(_ label: String, _ code: Int, _ w: CGFloat = 1) -> KeySpec {
        KeySpec(kind: .key, label: label, code: code, width: w)
    }
    static func mod(_ label: String, _ m: Mods, _ w: CGFloat = 1) -> KeySpec {
        KeySpec(kind: .mod, label: label, width: w, mod: m)
    }
    static func layer(_ label: String, _ target: String, _ w: CGFloat = 1) -> KeySpec {
        KeySpec(kind: .layer, label: label, width: w, target: target)
    }
    static func media(_ m: MediaKey, _ w: CGFloat = 1) -> KeySpec {
        KeySpec(kind: .media, label: "", width: w, media: m)
    }
    static func space(_ w: CGFloat) -> KeySpec {
        var s = ch(" ")
        s.label = ""
        s.width = w
        return s
    }
    func widened(_ w: CGFloat) -> KeySpec { var k = self; k.width = w; return k }
}

private enum Layout {
    static let unitsPerRow: CGFloat = 11

    static func row(_ chars: String, _ shifted: String? = nil) -> [KeySpec] {
        let a = Array(chars).map(String.init)
        let b = shifted.map { Array($0).map(String.init) }
        return a.enumerated().map { i, c in KeySpec.ch(c, b?[i]) }
    }

    static func symbols(_ s: [String]) -> [KeySpec] { s.map { KeySpec.ch($0) } }

    /// 123 ⌃ ⌥ | space | ⌘ fn áç  (3.25 + 4.5 + 3.25)
    static func bottom(_ switchLabel: String, _ to: String) -> [KeySpec] {
        [KeySpec.layer(switchLabel, to, 1.25), KeySpec.mod("⌃", .ctrl), KeySpec.mod("⌥", .opt), KeySpec.space(4.5),
         KeySpec.mod("⌘", .cmd, 1.25), KeySpec.layer("fn", "fn"), KeySpec(kind: .sys, label: "áç")]
    }

    static let layers: [String: [[KeySpec]]] = {
        let del = KeySpec.key("⌫", Keys.delete)
        let ret = KeySpec.key("return", Keys.returnKey, 2)
        let abc: [[KeySpec]] = [
            row("qwertyuiop", "QWERTYUIOP") + [del],
            row("asdfghjkl", "ASDFGHJKL") + [ret],
            [KeySpec.mod("⇧", .shift)] + row("zxcvbnm,.", "ZXCVBNM<>") + [KeySpec.mod("⇧", .shift)],
            bottom("123", "123"),
        ]
        let num: [[KeySpec]] = [
            symbols(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]) + [del],
            symbols(["-", "/", ":", ";", "(", ")", "$", "&", "@"]) + [ret],
            [KeySpec.layer("#+=", "sym", 1.5)] + symbols([".", ",", "?", "!", "'", "\"", "_", "="]) + [KeySpec.layer("#+=", "sym", 1.5)],
            bottom("ABC", "abc"),
        ]
        let sym: [[KeySpec]] = [
            symbols(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]) + [del],
            symbols(["_", "\\", "|", "~", "<", ">", "€", "£", "•"]) + [ret],
            [KeySpec.layer("123", "123", 1.5)] + symbols([".", ",", "?", "!", "'", "\"", "`", "°"]) + [KeySpec.layer("123", "123", 1.5)],
            bottom("ABC", "abc"),
        ]
        let f = Keys.fKeys
        var fn1: [KeySpec] = [KeySpec.key("esc", Keys.escape)]
        for i in 0..<6 { fn1.append(KeySpec.key("F\(i + 1)", f[i])) }
        fn1 += [KeySpec.key("PgUp", Keys.pageUp), KeySpec.key("Home", Keys.home), del.widened(2)]
        var fn2: [KeySpec] = [KeySpec.key("tab", Keys.tab)]
        for i in 6..<12 { fn2.append(KeySpec.key("F\(i + 1)", f[i])) }
        fn2 += [KeySpec.key("PgDn", Keys.pageDown), KeySpec.key("End", Keys.end), ret]
        let media: [MediaKey] = [.brightdown, .brightup, .prev, .play, .next, .mute, .voldown, .volup]
        let fn3: [KeySpec] = media.map { KeySpec.media($0, 1.25) } + [KeySpec.key("⌦", Keys.forwardDelete)]
        let fn4: [KeySpec] = [
            KeySpec.layer("ABC", "abc", 1.25), KeySpec.mod("⇧", .shift, 1.25), KeySpec.mod("⌃", .ctrl),
            KeySpec.mod("⌥", .opt), KeySpec.mod("⌘", .cmd, 1.5), KeySpec.key("←", Keys.left, 1.25),
            KeySpec.key("↑", Keys.up, 1.25), KeySpec.key("↓", Keys.down, 1.25), KeySpec.key("→", Keys.right, 1.25),
        ]
        let fn: [[KeySpec]] = [fn1, fn2, fn3, fn4]
        return ["abc": abc, "123": num, "sym": sym, "fn": fn]
    }()

    /// Characters offered when a key is held (most common in Portuguese first).
    static let variants: [String: [String]] = [
        "a": ["á", "ã", "â", "à", "ä", "å", "æ", "ª"],
        "e": ["é", "ê", "è", "ë", "€"],
        "i": ["í", "î", "ì", "ï"],
        "o": ["ó", "õ", "ô", "ò", "ö", "ø", "œ", "º"],
        "u": ["ú", "ü", "û", "ù"],
        "c": ["ç", "ć", "č"],
        "n": ["ñ", "ń"],
        "s": ["ß", "š", "§"],
        "y": ["ý", "ÿ"],
        "z": ["ž"],
        "-": ["–", "—", "•"],
        "'": ["‘", "’"],
        "\"": ["“", "”", "«", "»"],
        "$": ["€", "£", "¥", "¢"],
        "?": ["¿"],
        "!": ["¡"],
        ".": ["…"],
        "0": ["°"],
        "/": ["\\"],
    ]
}

// MARK: - Key view

final class KeyView: UIView {
    let spec: KeySpec
    let label = UILabel()
    private var shiftLabel: UILabel?
    private let icon = UIImageView()
    private let lockBar = UIView()

    var pressed = false { didSet { refresh() } }
    var modState = 0 { didSet { refresh() } }   // 0 off, 1 next key, 2 locked

    var onDown: ((KeyView) -> Void)?
    var onMove: ((KeyView, UITouch) -> Void)?
    var onUp: ((KeyView) -> Void)?

    init(_ spec: KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous

        label.textAlignment = .center
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.text = spec.label
        addSubview(label)

        if let s = spec.shiftLabel {
            let l = UILabel()
            l.text = s
            l.textColor = UIColor(white: 1, alpha: 0.45)
            addSubview(l)
            shiftLabel = l
        }
        if let m = spec.media {
            icon.image = UIImage(systemName: m.symbol)
            icon.tintColor = .white
            icon.contentMode = .scaleAspectFit
            addSubview(icon)
        }

        lockBar.backgroundColor = Theme.ok
        lockBar.layer.cornerRadius = 1.5
        lockBar.isHidden = true
        addSubview(lockBar)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let small = b.height < 50
        if let s = shiftLabel {
            s.font = .systemFont(ofSize: small ? 10 : 15)
            s.frame = CGRect(x: small ? 4 : 9, y: small ? 2 : 5, width: b.width - 8, height: small ? 12 : 18)
            label.frame = CGRect(x: 3, y: b.height * 0.28, width: b.width - 6, height: b.height * 0.62)
        } else {
            label.frame = b.insetBy(dx: 4, dy: 3)
        }
        let side = min(b.width, b.height) * 0.42
        icon.frame = CGRect(x: (b.width - side) / 2, y: (b.height - side) / 2, width: side, height: side)
        lockBar.frame = CGRect(x: b.width / 2 - 10, y: b.height - (small ? 5 : 9), width: 20, height: 3)
        refresh()
    }

    func refresh() {
        let special = spec.kind != .char || spec.isSpace
        var bg = special ? Theme.keyDark : Theme.key
        if modState > 0 { bg = Theme.accent }
        if pressed { bg = Theme.keyActive }
        backgroundColor = bg
        lockBar.isHidden = modState != 2
        let text = label.text ?? ""
        let base = min(bounds.height, bounds.width * 1.3)
        let size: CGFloat
        if !special && text.count <= 2 { size = base * 0.38 }
        else if text.count <= 2 { size = base * 0.32 }
        else { size = base * (text.count > 5 ? 0.2 : 0.24) }
        label.font = .systemFont(ofSize: max(11, min(size, 30)))
    }

    override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { pressed = true; onDown?(self) }
    override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) { if let x = t.first { onMove?(self, x) } }
    override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { pressed = false; onUp?(self) }
    override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { pressed = false; onUp?(self) }
}

// MARK: - Keyboard

/// Mac-style keyboard with ABC / 123 / #+= / fn layers. Text is sent as Unicode, so it
/// works with any Mac layout. Modifiers: tap once for the next key, twice to lock.
/// Letters are typed on release: hold for accents, slide to fix a wrong touch.
final class KeyboardView: UIView {
    var onSystemKeyboard: (() -> Void)?

    private var layers: [String: [[KeyView]]] = [:]
    private var current = "abc"
    private var onceMods: Mods = []
    private var lockedMods: Mods = []
    private var mods: Mods { onceMods.union(lockedMods) }

    private var repeatTimer: Timer?
    private weak var repeatKey: KeyView?

    private let preview = UILabel()
    private weak var previewKey: KeyView?

    private weak var charKey: KeyView?     // letter waiting for release
    private weak var charOwner: KeyView?   // key view owning that touch (differs after sliding)
    private var holdTimer: Timer?
    private var variantView: UIView?
    private var variantLabels: [UILabel] = []
    private var variants: [String] = []
    private var variantIndex = -1

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var gap: CGFloat { Theme.isCompact(self) ? 5 : 7 }

    private var conn: Connection { .shared }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        clipsToBounds = false
        for (name, rows) in Layout.layers {
            layers[name] = rows.map { specs in
                specs.map { spec in
                    let k = KeyView(spec)
                    k.onDown = { [weak self] in self?.keyDown($0) }
                    k.onMove = { [weak self] in self?.keyMoved($0, $1) }
                    k.onUp = { [weak self] in self?.keyUp($0) }
                    addSubview(k)
                    return k
                }
            }
        }
        preview.backgroundColor = Theme.keyActive
        preview.textColor = .white
        preview.textAlignment = .center
        preview.layer.cornerRadius = 12
        preview.layer.masksToBounds = true
        preview.isHidden = true
        preview.isUserInteractionEnabled = false
        addSubview(preview)
        show(layer: "abc")
    }

    required init?(coder: NSCoder) { fatalError() }

    private func show(layer name: String) {
        current = name
        for (n, rows) in layers { rows.joined().forEach { $0.isHidden = n != name } }
        refreshKeys()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let g = gap
        for rows in layers.values {
            let rowH = (bounds.height - g * CGFloat(rows.count - 1)) / CGFloat(rows.count)
            var y: CGFloat = 0
            for row in rows {
                let unit = (bounds.width - g * CGFloat(row.count - 1)) / Layout.unitsPerRow
                var x: CGFloat = 0
                for k in row {
                    let w = unit * k.spec.width
                    k.frame = CGRect(x: x, y: y, width: w, height: rowH)
                    x += w + g
                }
                y += rowH + g
            }
        }
    }

    /// Touches in the gaps go to the nearest key, so no tap is lost.
    override func hitTest(_ p: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, bounds.contains(p) else { return nil }
        var best: KeyView?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for k in (layers[current] ?? []).joined() {
            let f = k.frame
            if f.contains(p) { return k }
            let dx = max(0, f.minX - p.x, p.x - f.maxX), dy = max(0, f.minY - p.y, p.y - f.maxY)
            let d = dx * dx + dy * dy
            if d < bestDist { bestDist = d; best = k }
        }
        return best
    }

    private func key(at p: CGPoint) -> KeyView? {
        (layers[current] ?? []).joined().first { $0.frame.insetBy(dx: -gap / 2, dy: -gap / 2).contains(p) }
    }

    private func refreshKeys() {
        let m = mods
        for k in (layers[current] ?? []).joined() {
            switch k.spec.kind {
            case .mod:
                k.modState = lockedMods.isSuperset(of: k.spec.mod) ? 2 : onceMods.isSuperset(of: k.spec.mod) ? 1 : 0
            case .char:
                k.label.text = k.spec.isLetter ? (m.contains(.shift) ? k.spec.shiftChar : k.spec.char) : k.spec.label
                k.refresh()
            default:
                break
            }
        }
    }

    private func consumeOnceMods() {
        guard !onceMods.isEmpty else { return }
        onceMods = []
        refreshKeys()
    }

    // MARK: Feedback

    private func feedback() {
        if Prefs.keyClick { AudioServicesPlaySystemSound(1104) }
        if Prefs.keyHaptics { haptic.impactOccurred() }   // iPhone only: iPads have no Taptic Engine
    }

    /// Above the key, or below it when there's no room (keyboard at the top).
    private func popupY(for f: CGRect, height h: CGFloat) -> CGFloat {
        let above = f.minY - h - 6
        let top = convert(CGPoint(x: 0, y: above), to: nil).y
        let safeTop = window?.safeAreaInsets.top ?? 0
        return top >= safeTop ? above : f.maxY + 6
    }

    private func showPreview(_ k: KeyView) {
        guard k.spec.kind == .char, !k.spec.isSpace, let text = k.label.text, !text.isEmpty else { return }
        let f = k.frame
        let w = f.width * 1.15, h = f.height * 0.95
        preview.text = text
        preview.font = .systemFont(ofSize: min(40, h * 0.5))
        preview.frame = CGRect(x: f.midX - w / 2, y: popupY(for: f, height: h), width: w, height: h)
        preview.isHidden = false
        bringSubviewToFront(preview)
        previewKey = k
    }

    private func hidePreview(_ k: KeyView?) {
        guard let k = k, k === previewKey else { return }
        preview.isHidden = true
        previewKey = nil
    }

    // MARK: Key events

    private func keyDown(_ k: KeyView) {
        feedback()
        showPreview(k)
        let s = k.spec

        if s.kind == .mod {
            if lockedMods.isSuperset(of: s.mod) { lockedMods.subtract(s.mod) }
            else if onceMods.isSuperset(of: s.mod) { onceMods.subtract(s.mod); lockedMods.formUnion(s.mod) }
            else { onceMods.formUnion(s.mod) }
            refreshKeys()
            return
        }

        commitPending()   // a letter still under another finger is typed first
        let m = mods

        switch s.kind {
        case .layer:
            stopRepeat()
            show(layer: s.target)
        case .sys:
            onSystemKeyboard?()
        case .media:
            if let media = s.media { conn.sendMedia(media) }
        case .char:
            if !m.isDisjoint(with: Mods.commandLike), s.code >= 0 {
                conn.sendKey(s.code, mods: m)          // shortcuts fire right away
                consumeOnceMods()
            } else if s.isSpace {
                conn.sendText(" ")
                consumeOnceMods()
                startRepeat(k)
            } else {
                charKey = k
                charOwner = k
                armHoldTimer()
            }
        case .key:
            conn.sendKey(s.code, mods: m)
            consumeOnceMods()
            if [Keys.delete, Keys.forwardDelete, Keys.left, Keys.right, Keys.up, Keys.down].contains(s.code) {
                startRepeat(k)
            }
        case .mod:
            break
        }
    }

    private func keyMoved(_ k: KeyView, _ touch: UITouch) {
        guard k === charOwner, let current = charKey else { return }
        if let box = variantView {
            let p = touch.location(in: box)
            let cell = box.bounds.width / CGFloat(variants.count)
            var i = Int(floor(p.x / cell))
            i = max(-1, min(variants.count - 1, i))
            if p.x < -cell * 0.5 || abs(p.y - box.bounds.midY) > box.bounds.height * 2 { i = -1 }
            highlightVariant(i)
            return
        }
        // Slide to the neighbouring letter before releasing.
        if let other = key(at: touch.location(in: self)), other !== current,
           other.spec.kind == .char, !other.spec.isSpace {
            hidePreview(current)
            current.pressed = false
            charKey = other
            other.pressed = true
            showPreview(other)
            armHoldTimer()
        }
    }

    private func keyUp(_ k: KeyView) {
        hidePreview(k)
        if k === repeatKey { stopRepeat() }
        guard k === charOwner, let target = charKey else { return }
        hidePreview(target)
        let shift = mods.contains(.shift)
        var text: String?
        if variantView != nil {
            text = variantIndex >= 0 ? variants[variantIndex] : nil
            if shift { text = text?.uppercased() }
        } else {
            text = shift ? target.spec.shiftChar : target.spec.char
        }
        if let t = text {
            conn.sendText(t)
            consumeOnceMods()
        }
        cancelHold()
    }

    /// Types the pending letter now (another key was pressed before it was released).
    private func commitPending() {
        guard let k = charKey else { return }
        if variantView == nil {
            conn.sendText(mods.contains(.shift) ? k.spec.shiftChar : k.spec.char)
            consumeOnceMods()
        }
        cancelHold()
    }

    private func armHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
        guard let k = charKey, Layout.variants[k.spec.char] != nil else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self] _ in self?.showVariants() }
    }

    private func showVariants() {
        holdTimer = nil
        guard let k = charKey, let list = Layout.variants[k.spec.char], !list.isEmpty else { return }
        hidePreview(k)
        let shift = mods.contains(.shift)
        let f = k.frame
        let cellW = max(Theme.isCompact(self) ? 36 : 64, f.width * 0.9), h = f.height
        let w = cellW * CGFloat(list.count)
        let x = min(max(0, f.minX), bounds.width - w)
        let box = UIView(frame: CGRect(x: x, y: popupY(for: f, height: h), width: w, height: h))
        box.backgroundColor = Theme.keyDark
        box.layer.cornerRadius = 12
        box.layer.borderWidth = 1
        box.layer.borderColor = UIColor(white: 1, alpha: 0.15).cgColor
        box.isUserInteractionEnabled = false
        variantLabels = list.enumerated().map { i, v in
            let l = UILabel(frame: CGRect(x: CGFloat(i) * cellW + 3, y: 3, width: cellW - 6, height: h - 6))
            l.text = shift ? v.uppercased() : v
            l.textColor = .white
            l.font = .systemFont(ofSize: min(32, h * 0.45))
            l.textAlignment = .center
            l.layer.cornerRadius = 9
            l.layer.masksToBounds = true
            box.addSubview(l)
            return l
        }
        addSubview(box)
        variantView = box
        variants = list
        highlightVariant(0)
        feedback()
    }

    private func highlightVariant(_ i: Int) {
        variantIndex = i
        for (j, l) in variantLabels.enumerated() { l.backgroundColor = j == i ? Theme.accent : .clear }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        if let k = charKey, k !== charOwner {   // slid onto it: clear its highlight
            k.pressed = false
            hidePreview(k)
        }
        variantView?.removeFromSuperview()
        variantView = nil
        variantLabels = []
        variants = []
        variantIndex = -1
        charKey = nil
        charOwner = nil
    }

    // MARK: Repeat (delete, arrows, space)

    private func startRepeat(_ k: KeyView) {
        stopRepeat()
        repeatKey = k
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                self?.repeatTick()
            }
        }
    }

    private func repeatTick() {
        guard let k = repeatKey, k.pressed else { stopRepeat(); return }
        if k.spec.kind == .char { conn.sendText(k.spec.char) }
        else { conn.sendKey(k.spec.code, mods: mods) }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatKey = nil
    }
}

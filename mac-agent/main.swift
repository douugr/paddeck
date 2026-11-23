// PadDeck Agent — receives input from the PadDeck iPad app and turns it into
// real mouse/keyboard events on this Mac. Menu bar only (LSUIElement).
// Build with ./build.sh (swiftc, no Xcode project needed). macOS 12+.

import Cocoa
import Network
import ServiceManagement

// MARK: - Constants

enum Proto {
    static let tcpPort: UInt16 = 47816
    static let udpPort: UInt16 = 47817
    static let usbPort: UInt16 = 47818   // the iPad app listens here; reached through usbmuxd
    static let bonjourType = "_paddeck._tcp"
    static let version: UInt8 = 1

    // client -> agent
    static let hello: UInt8 = 0x01
    static let ping: UInt8 = 0x02
    static let button: UInt8 = 0x10
    static let move: UInt8 = 0x11
    static let scroll: UInt8 = 0x12
    static let text: UInt8 = 0x20
    static let key: UInt8 = 0x21
    static let media: UInt8 = 0x22
    static let open: UInt8 = 0x23

    // agent -> client
    static let welcome: UInt8 = 0x81
    static let denied: UInt8 = 0x82
    static let pong: UInt8 = 0x83
}

// MARK: - Byte helpers

extension Data {
    func u8(_ i: Int) -> UInt8 { self[self.startIndex + i] }
    func u16(_ i: Int) -> UInt16 { UInt16(u8(i)) << 8 | UInt16(u8(i + 1)) }
    func i16(_ i: Int) -> Int16 { Int16(bitPattern: u16(i)) }
    func u32(_ i: Int) -> UInt32 {
        UInt32(u8(i)) << 24 | UInt32(u8(i + 1)) << 16 | UInt32(u8(i + 2)) << 8 | UInt32(u8(i + 3))
    }
    func sub(_ from: Int, _ count: Int? = nil) -> Data {
        let s = self.startIndex + from
        let e = count.map { s + $0 } ?? self.endIndex
        return self.subdata(in: s..<e)
    }
}

func frame(_ type: UInt8, _ payload: Data = Data()) -> Data {
    var d = Data([type, UInt8(payload.count >> 8 & 0xff), UInt8(payload.count & 0xff)])
    d.append(payload)
    return d
}

/// Normalises an endpoint host so the TCP and UDP views of the same iPad compare equal.
func hostKey(_ endpoint: NWEndpoint) -> String {
    guard case let .hostPort(host, _) = endpoint else { return "\(endpoint)" }
    var s = "\(host)"
    if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) }
    if s.hasPrefix("::ffff:") { s = String(s.dropFirst(7)) }
    return s
}

// MARK: - Input injection

final class Injector {
    private let src = CGEventSource(stateID: .hidSystemState)
    private var leftDown = false
    private var rightDown = false
    private var middleDown = false

    // double/triple click tracking
    private var lastClickTime: TimeInterval = 0
    private var lastClickPos = CGPoint.zero
    private var lastClickButton = -1
    private var clickState: Int64 = 1

    private var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    // MARK: pointer

    func move(dx: Double, dy: Double) {
        let from = location
        let to = clamp(CGPoint(x: from.x + dx, y: from.y + dy), near: from)
        let type: CGEventType
        let btn: CGMouseButton
        if leftDown { type = .leftMouseDragged; btn = .left }
        else if rightDown { type = .rightMouseDragged; btn = .right }
        else if middleDown { type = .otherMouseDragged; btn = .center }
        else { type = .mouseMoved; btn = .left }
        guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: to, mouseButton: btn) else { return }
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        e.post(tap: .cghidEventTap)
    }

    func scroll(dy: Int32, dx: Int32) {
        guard let e = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2,
                              wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        e.post(tap: .cghidEventTap)
    }

    /// action: 0 down, 1 up, 2 click
    func button(_ b: Int, action: Int) {
        switch action {
        case 0: buttonEvent(b, down: true)
        case 1: buttonEvent(b, down: false)
        default:
            buttonEvent(b, down: true)
            buttonEvent(b, down: false)
        }
    }

    private func buttonEvent(_ b: Int, down: Bool) {
        let p = location
        let type: CGEventType
        let btn: CGMouseButton
        switch b {
        case 1: type = down ? .rightMouseDown : .rightMouseUp; btn = .right; rightDown = down
        case 2: type = down ? .otherMouseDown : .otherMouseUp; btn = .center; middleDown = down
        default: type = down ? .leftMouseDown : .leftMouseUp; btn = .left; leftDown = down
        }
        if down {
            let now = ProcessInfo.processInfo.systemUptime
            let near = abs(p.x - lastClickPos.x) < 6 && abs(p.y - lastClickPos.y) < 6
            if b == lastClickButton && near && now - lastClickTime < NSEvent.doubleClickInterval {
                clickState = min(clickState + 1, 3)
            } else {
                clickState = 1
            }
            lastClickTime = now
            lastClickPos = p
            lastClickButton = b
        }
        guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: btn) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: clickState)
        if b == 2 { e.setIntegerValueField(.mouseEventButtonNumber, value: 2) }
        e.post(tap: .cghidEventTap)
    }

    /// Releases anything a disconnected client left pressed.
    func releaseAll() {
        if leftDown { buttonEvent(0, down: false) }
        if rightDown { buttonEvent(1, down: false) }
        if middleDown { buttonEvent(2, down: false) }
    }

    private func clamp(_ p: CGPoint, near from: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(max(count, 1)))
        CGGetActiveDisplayList(count, &ids, &count)
        let rects = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
        if rects.contains(where: { $0.contains(p) }) { return p }
        // outside every screen: keep it inside the screen it came from
        let r = rects.first(where: { $0.contains(from) }) ?? rects.first ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
    }

    // MARK: keyboard

    private static let modKeys: [(bit: UInt8, code: CGKeyCode, flag: CGEventFlags)] = [
        (0x08, 55, .maskCommand),      // command
        (0x02, 59, .maskControl),      // control
        (0x04, 58, .maskAlternate),    // option
        (0x01, 56, .maskShift),        // shift
        (0x10, 63, .maskSecondaryFn),  // fn
    ]

    /// Keys that real Apple keyboards send with the fn / keypad flags set.
    private static func extraFlags(for code: CGKeyCode) -> CGEventFlags {
        switch code {
        case 123, 124, 125, 126: return [.maskSecondaryFn, .maskNumericPad]   // arrows
        case 115, 116, 117, 119, 121: return [.maskSecondaryFn]               // home, pgup, fwd-del, end, pgdn
        case 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111: return [.maskSecondaryFn] // F1–F12
        default: return []
        }
    }

    /// action: 0 down, 1 up, 2 press (down+up with the modifiers wrapped around it)
    func key(_ code: CGKeyCode, mods: UInt8, action: Int) {
        let active = Injector.modKeys.filter { mods & $0.bit != 0 }
        var flags: CGEventFlags = []
        if action == 0 || action == 2 {
            for m in active {
                flags.insert(m.flag)
                post(m.code, down: true, flags: flags)
            }
        } else {
            for m in active { flags.insert(m.flag) }
        }
        let keyFlags = flags.union(Injector.extraFlags(for: code))
        if action == 0 || action == 2 { post(code, down: true, flags: keyFlags) }
        if action == 1 || action == 2 {
            post(code, down: false, flags: keyFlags)
            for m in active.reversed() {
                flags.remove(m.flag)
                post(m.code, down: false, flags: flags)
            }
        }
    }

    private func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    /// Types text independently of the Mac's keyboard layout (accents, ç, emoji…).
    func type(_ text: String) {
        for ch in text {
            switch ch {
            case "\n", "\r", "\r\n": key(36, mods: 0, action: 2)   // return
            case "\t": key(48, mods: 0, action: 2)                 // tab
            case "\u{8}": key(51, mods: 0, action: 2)              // backspace
            default:
                var units = Array(String(ch).utf16)
                for down in [true, false] {
                    guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
                    e.flags = []
                    e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                    e.post(tap: .cghidEventTap)
                }
            }
        }
    }

    // MARK: media keys

    func media(_ nxKey: Int) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (nxKey << 16) | ((down ? 0xa : 0xb) << 8)
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: open

    func open(_ target: String) {
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        DispatchQueue.main.async {
            let ws = NSWorkspace.shared
            if t.contains("://"), let url = URL(string: t) {
                ws.open(url)
            } else if t.hasPrefix("/") || t.hasPrefix("~") {
                ws.open(URL(fileURLWithPath: (t as NSString).expandingTildeInPath))
            } else if !t.contains(" "), t.split(separator: ".").count >= 3,
                      let url = ws.urlForApplication(withBundleIdentifier: t) {
                ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            } else {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-a", t]
                try? p.run()
            }
        }
    }
}

// MARK: - Smoothing

/// Wi-Fi delivers pointer packets in bursts (power saving, retries): applied as they come,
/// the cursor stops and jumps. This replays them at a steady 120 Hz, spreading each burst
/// over a few frames (~10–15 ms of delay). Clicks flush whatever is pending first.
final class Smoother {
    private let injector: Injector
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var mx = 0.0, my = 0.0   // pending pointer movement
    private var sx = 0.0, sy = 0.0   // pending scroll
    private var idleTicks = 0

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "smooth") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "smooth") }
    }

    init(injector: Injector, queue: DispatchQueue) {
        self.injector = injector
        self.queue = queue
    }

    func move(dx: Double, dy: Double) {
        mx += dx
        my += dy
        start()
    }

    func scroll(dy: Double, dx: Double) {
        sy += dy
        sx += dx
        start()
    }

    /// Applies everything pending right now (before a click, so it lands in the right place).
    func flush() {
        if mx != 0 || my != 0 { injector.move(dx: mx, dy: my) }
        let ty = sy.rounded(), tx = sx.rounded()
        if ty != 0 || tx != 0 { injector.scroll(dy: Int32(ty), dx: Int32(tx)) }
        mx = 0; my = 0; sx = 0; sy = 0
    }

    private func start() {
        idleTicks = 0
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: .nanoseconds(8_333_333), leeway: .microseconds(500))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        // Each frame moves half of what's pending: a steady stream passes straight through,
        // a burst is spread over the next few frames.
        let share = 0.5
        let ox = abs(mx) < 1.5 ? mx : mx * share
        let oy = abs(my) < 1.5 ? my : my * share
        if ox != 0 || oy != 0 {
            injector.move(dx: ox, dy: oy)
            mx -= ox
            my -= oy
        }
        let ty = (abs(sy) < 2 ? sy : sy * share).rounded()
        let tx = (abs(sx) < 2 ? sx : sx * share).rounded()
        if ty != 0 || tx != 0 {
            injector.scroll(dy: Int32(ty), dx: Int32(tx))
            sy -= ty
            sx -= tx
        }
        if mx == 0 && my == 0 && abs(sx) < 0.5 && abs(sy) < 0.5 {
            sx = 0; sy = 0
            idleTicks += 1
            if idleTicks > 120 {   // 1 s without input: stop the timer
                timer?.cancel()
                timer = nil
                idleTicks = 0
            }
        } else {
            idleTicks = 0
        }
    }
}

// MARK: - Sessions

final class Session {
    let conn: NWConnection
    let host: String
    var token: UInt32 = 0
    var name = "iPad"
    var authed = false
    var buffer = Data()
    var lastSeen = Date()
    var usb = false                  // came through the cable: no PIN needed
    var onClose: (() -> Void)?

    init(conn: NWConnection) {
        self.conn = conn
        self.host = hostKey(conn.endpoint)
    }

    func send(_ data: Data) {
        conn.send(content: data, completion: .contentProcessed { _ in })
    }
}

protocol ServerDelegate: AnyObject {
    func serverChanged()
}

final class Server {
    let queue = DispatchQueue(label: "paddeck.server")
    let injector = Injector()
    private lazy var smoother = Smoother(injector: injector, queue: queue)
    weak var delegate: ServerDelegate?

    private var tcp: NWListener?
    private var udp: NWListener?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private var failures: [String: (count: Int, until: Date)] = [:]
    private var reaper: DispatchSourceTimer?
    private var usbmux: USBMux?

    private(set) var listening = false
    private(set) var lastError: String?

    var pin: String {
        get {
            if let p = UserDefaults.standard.string(forKey: "pin"), p.count == 4 { return p }
            let p = Server.randomPIN()
            UserDefaults.standard.set(p, forKey: "pin")
            return p
        }
        set { UserDefaults.standard.set(newValue, forKey: "pin") }
    }

    /// Names of the connected iPads (read on main thread through a snapshot).
    private(set) var connectedNames: [String] = []

    static func randomPIN() -> String { String(format: "%04d", Int.random(in: 0...9999)) }

    func start() {
        do {
            let tcpOpts = NWProtocolTCP.Options()
            tcpOpts.noDelay = true
            let tp = NWParameters(tls: nil, tcp: tcpOpts)
            tp.allowLocalEndpointReuse = true
            let t = try NWListener(using: tp, on: NWEndpoint.Port(rawValue: Proto.tcpPort)!)
            t.service = NWListener.Service(name: nil, type: Proto.bonjourType)
            t.newConnectionHandler = { [weak self] c in self?.accept(c) }
            t.stateUpdateHandler = { [weak self] st in self?.listenerState(st) }
            t.start(queue: queue)
            tcp = t

            let up = NWParameters.udp
            up.allowLocalEndpointReuse = true
            let u = try NWListener(using: up, on: NWEndpoint.Port(rawValue: Proto.udpPort)!)
            u.newConnectionHandler = { [weak self] c in self?.acceptUDP(c) }
            u.start(queue: queue)
            udp = u
        } catch {
            lastError = "\(error)"
            notify()
        }

        usbmux = USBMux(queue: queue) { [weak self] conn, done in self?.adoptUSB(conn, onClose: done) }
        usbmux?.start()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in self?.reap() }
        timer.resume()
        reaper = timer
    }

    private func listenerState(_ st: NWListener.State) {
        switch st {
        case .ready: listening = true; lastError = nil
        case .failed(let e): listening = false; lastError = "\(e)"
        case .cancelled: listening = false
        default: break
        }
        notify()
    }

    /// Drops every session (used when the PIN changes).
    func disconnectAll() {
        queue.async {
            for s in self.sessions.values { s.conn.cancel() }
        }
    }

    private func notify() {
        let names = sessions.values.filter { $0.authed }.map { $0.usb ? "\($0.name) (cabo)" : $0.name }
        DispatchQueue.main.async {
            self.connectedNames = names
            self.delegate?.serverChanged()
        }
    }

    // MARK: TCP

    private func accept(_ c: NWConnection) {
        let s = Session(conn: c)
        register(s)
        c.start(queue: queue)
        receive(s)
    }

    /// A stream to the iPad app opened through usbmuxd (already started).
    private func adoptUSB(_ c: NWConnection, onClose: @escaping () -> Void) {
        let s = Session(conn: c)
        s.usb = true
        s.onClose = onClose
        register(s)
        receive(s)
    }

    private func register(_ s: Session) {
        sessions[ObjectIdentifier(s)] = s
        s.conn.stateUpdateHandler = { [weak self, weak s] st in
            guard let self = self, let s = s else { return }
            switch st {
            case .failed, .cancelled: self.drop(s)
            default: break
            }
        }
    }

    private func receive(_ s: Session) {
        s.conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                s.buffer.append(data)
                s.lastSeen = Date()
                self.parse(s)
            }
            if done || err != nil {
                s.conn.cancel()
            } else {
                self.receive(s)
            }
        }
    }

    private func parse(_ s: Session) {
        while s.buffer.count >= 3 {
            let len = Int(s.buffer.u16(1))
            guard s.buffer.count >= 3 + len else { return }
            let type = s.buffer.u8(0)
            let payload = s.buffer.sub(3, len)
            s.buffer = s.buffer.sub(3 + len)
            handle(s, type: type, payload: payload)
        }
    }

    private func drop(_ s: Session) {
        guard sessions.removeValue(forKey: ObjectIdentifier(s)) != nil else { return }
        if s.authed { injector.releaseAll() }
        s.onClose?()
        s.onClose = nil
        notify()
    }

    private func reap() {
        let now = Date()
        for s in sessions.values where now.timeIntervalSince(s.lastSeen) > 10 {
            s.conn.cancel()
        }
    }

    private func handle(_ s: Session, type: UInt8, payload p: Data) {
        switch type {
        case Proto.hello: hello(s, p)
        case Proto.ping: s.send(frame(Proto.pong))
        default:
            guard s.authed else { return }
            command(type, p, smooth: !s.usb)
        }
    }

    private func hello(_ s: Session, _ p: Data) {
        if !s.usb, let f = failures[s.host], f.count >= 5, f.until > Date() {
            s.send(frame(Proto.denied, Data([2])))
            return
        }
        guard p.count >= 2, p.u8(0) == Proto.version else {
            s.send(frame(Proto.denied, Data([3])))
            return
        }
        let pinLen = Int(p.u8(1))
        guard p.count >= 2 + pinLen else { return }
        let given = String(data: p.sub(2, pinLen), encoding: .utf8) ?? ""
        guard s.usb || given == pin else {
            var f = failures[s.host] ?? (count: 0, until: Date())
            f.count += 1
            f.until = Date().addingTimeInterval(60)
            failures[s.host] = f
            s.send(frame(Proto.denied, Data([f.count >= 5 ? 2 : 1])))
            return
        }
        failures[s.host] = nil
        s.authed = true
        s.token = UInt32.random(in: 1...UInt32.max)
        if let n = String(data: p.sub(2 + pinLen), encoding: .utf8), !n.isEmpty { s.name = n }
        var w = Data()
        withUnsafeBytes(of: s.token.bigEndian) { w.append(contentsOf: $0) }
        w.append((Host.current().localizedName ?? "Mac").data(using: .utf8)!)
        s.send(frame(Proto.welcome, w))
        notify()
    }

    /// Everything after authentication; shared by TCP and UDP.
    private func command(_ type: UInt8, _ p: Data, smooth: Bool) {
        let smoothing = smooth && Smoother.enabled
        switch type {
        case Proto.button where p.count >= 2:
            smoother.flush()
            injector.button(Int(p.u8(0)), action: Int(p.u8(1)))
        case Proto.move where p.count >= 4:
            if smoothing { smoother.move(dx: Double(p.i16(0)), dy: Double(p.i16(2))) }
            else { injector.move(dx: Double(p.i16(0)), dy: Double(p.i16(2))) }
        case Proto.scroll where p.count >= 4:
            if smoothing { smoother.scroll(dy: Double(p.i16(0)), dx: Double(p.i16(2))) }
            else { injector.scroll(dy: Int32(p.i16(0)), dx: Int32(p.i16(2))) }
        case Proto.text:
            if let t = String(data: p, encoding: .utf8) { injector.type(t) }
        case Proto.key where p.count >= 4:
            injector.key(CGKeyCode(p.u16(0)), mods: p.u8(2), action: Int(p.u8(3)))
        case Proto.media where p.count >= 1:
            injector.media(Int(p.u8(0)))
        case Proto.open:
            if let t = String(data: p, encoding: .utf8) { injector.open(t) }
        default: break
        }
    }

    // MARK: UDP

    private func acceptUDP(_ c: NWConnection) {
        c.start(queue: queue)
        receiveUDP(c)
    }

    private func receiveUDP(_ c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, err in
            guard let self = self else { return }
            if let d = data, d.count >= 5 {
                let token = d.u32(0)
                let host = hostKey(c.endpoint)
                if let s = self.sessions.values.first(where: { $0.authed && $0.token == token && $0.host == host }) {
                    s.lastSeen = Date()
                    let type = d.u8(4)
                    if type == Proto.move || type == Proto.scroll {
                        self.command(type, d.sub(5), smooth: true)
                    }
                }
            }
            if err == nil { self.receiveUDP(c) } else { c.cancel() }
        }
    }
}

// MARK: - USB (usbmuxd)

/// Talks to macOS's usbmuxd (the service Finder uses to reach iOS devices) to open a TCP
/// stream to the iPad app's USB port whenever an iPad is plugged in and the app is open.
final class USBMux {
    private static let socketPath = "/var/run/usbmuxd"
    private let queue: DispatchQueue
    private let onStream: (NWConnection, @escaping () -> Void) -> Void
    private var listen: NWConnection?
    private var devices: [Int: String] = [:]   // DeviceID -> serial
    private var busy: Set<Int> = []            // connecting or connected
    private var tag: UInt32 = 1

    init(queue: DispatchQueue, onStream: @escaping (NWConnection, @escaping () -> Void) -> Void) {
        self.queue = queue
        self.onStream = onStream
    }

    func start() {
        let c = NWConnection(to: .unix(path: USBMux.socketPath), using: .tcp)
        listen = c
        c.stateUpdateHandler = { [weak self] st in
            guard let self = self else { return }
            switch st {
            case .ready:
                self.send(c, ["MessageType": "Listen"])
                self.readLoop(c)
            case .failed, .cancelled:
                // usbmuxd restarted or unavailable: try again later
                self.listen = nil
                self.devices.removeAll()
                self.queue.asyncAfter(deadline: .now() + 5) { if self.listen == nil { self.start() } }
            default: break
            }
        }
        c.start(queue: queue)
    }

    // MARK: messages (16-byte little-endian header + XML plist)

    private func send(_ c: NWConnection, _ body: [String: Any]) {
        var dict = body
        dict["ClientVersionString"] = "PadDeck"
        dict["ProgName"] = "PadDeck"
        guard let plist = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else { return }
        var d = Data()
        for v in [UInt32(16 + plist.count), 1, 8, tag] {   // length, version (plist), type (plist), tag
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
        tag &+= 1
        d.append(plist)
        c.send(content: d, completion: .contentProcessed { _ in })
    }

    private func readMessage(_ c: NWConnection, _ done: @escaping ([String: Any]?) -> Void) {
        c.receive(minimumIncompleteLength: 16, maximumLength: 16) { head, _, _, err in
            guard let head = head, head.count == 16, err == nil else { return done(nil) }
            let len = Int(UInt32(head.u8(0)) | UInt32(head.u8(1)) << 8 | UInt32(head.u8(2)) << 16 | UInt32(head.u8(3)) << 24)
            let bodyLen = len - 16
            guard bodyLen > 0, bodyLen < 1 << 20 else { return done(nil) }
            c.receive(minimumIncompleteLength: bodyLen, maximumLength: bodyLen) { body, _, _, err in
                guard let body = body, err == nil,
                      let obj = try? PropertyListSerialization.propertyList(from: body, options: [], format: nil),
                      let dict = obj as? [String: Any] else { return done(nil) }
                done(dict)
            }
        }
    }

    private func readLoop(_ c: NWConnection) {
        readMessage(c) { [weak self] msg in
            guard let self = self else { return }
            guard let msg = msg else { c.cancel(); return }
            self.handle(msg)
            self.readLoop(c)
        }
    }

    private func handle(_ msg: [String: Any]) {
        switch msg["MessageType"] as? String {
        case "Attached":
            guard let id = msg["DeviceID"] as? Int,
                  let props = msg["Properties"] as? [String: Any],
                  (props["ConnectionType"] as? String) == "USB" else { return }
            devices[id] = props["SerialNumber"] as? String ?? "\(id)"
            connect(id)
        case "Detached":
            if let id = msg["DeviceID"] as? Int { devices[id] = nil }
        default: break
        }
    }

    /// Opens a stream to the app on the device; retries while the device stays plugged in.
    private func connect(_ id: Int) {
        guard devices[id] != nil, !busy.contains(id) else { return }
        busy.insert(id)
        let c = NWConnection(to: .unix(path: USBMux.socketPath), using: .tcp)
        var handedOver = false
        let retry: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.busy.remove(id)
            self.queue.asyncAfter(deadline: .now() + 2) { self.connect(id) }
        }
        c.stateUpdateHandler = { st in
            switch st {
            case .ready:
                let port = Int(Proto.usbPort.byteSwapped)   // usbmuxd wants network byte order
                self.send(c, ["MessageType": "Connect", "DeviceID": id, "PortNumber": port])
                self.readMessage(c) { reply in
                    if let n = reply?["Number"] as? Int, n == 0 {
                        handedOver = true
                        self.onStream(c, retry)        // from now on it's a plain TCP stream
                    } else {
                        c.cancel()                     // app not open on the iPad (yet)
                    }
                }
            case .failed, .cancelled:
                if !handedOver { retry() }
            default: break
            }
        }
        c.start(queue: queue)
    }
}

// MARK: - Menu bar UI

final class AppDelegate: NSObject, NSApplicationDelegate, ServerDelegate, NSMenuDelegate {
    let server = Server()
    var item: NSStatusItem!
    let menu = NSMenu()

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "PadDeck") {
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "PD"
        }
        menu.delegate = self
        item.menu = menu

        server.delegate = self
        server.start()
        _ = server.pin

        // Ask once for Accessibility (needed to post events).
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        rebuild()
    }

    func serverChanged() { rebuild() }
    func menuWillOpen(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
        menu.removeAllItems()

        let names = server.connectedNames
        let status: String
        if let e = server.lastError { status = "Erro: \(e)" }
        else if !names.isEmpty { status = "Conectado: " + names.joined(separator: ", ") }
        else if server.listening { status = "Aguardando o iPad…" }
        else { status = "Iniciando…" }
        menu.addItem(disabled(status))
        item.button?.appearsDisabled = names.isEmpty

        let pinItem = disabled("PIN: \(server.pin)")
        pinItem.attributedTitle = NSAttributedString(
            string: "PIN: \(server.pin)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)])
        menu.addItem(pinItem)
        menu.addItem(action("Gerar novo PIN", #selector(newPIN)))
        let smooth = action("Suavizar movimento no Wi-Fi", #selector(toggleSmooth))
        smooth.state = Smoother.enabled ? .on : .off
        menu.addItem(smooth)
        menu.addItem(.separator())

        if AXIsProcessTrusted() {
            menu.addItem(disabled("Acessibilidade: permitida ✓"))
        } else {
            menu.addItem(action("Permitir Acessibilidade…", #selector(openAccessibility)))
        }

        if #available(macOS 13.0, *) {
            let login = action("Abrir ao iniciar sessão", #selector(toggleLogin))
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }
        menu.addItem(.separator())
        menu.addItem(action("Sair do PadDeck", #selector(quit)))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func action(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc func toggleSmooth() {
        Smoother.enabled.toggle()
        rebuild()
    }

    @objc func newPIN() {
        server.pin = Server.randomPIN()
        server.disconnectAll()
        rebuild()
    }

    @objc func openAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func toggleLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch {
                NSLog("PadDeck: login item: \(error)")
            }
            rebuild()
        }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

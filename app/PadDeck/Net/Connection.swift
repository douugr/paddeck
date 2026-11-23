import Foundation
import Network
import UIKit

/// Which Mac to talk to.
enum MacTarget: Equatable {
    case service(name: String)   // found with Bonjour
    case host(String)            // typed IP or hostname

    var endpoint: NWEndpoint {
        switch self {
        case .service(let name):
            return .service(name: name, type: Proto.bonjourType, domain: "local.", interface: nil)
        case .host(let h):
            return .hostPort(host: NWEndpoint.Host(h), port: NWEndpoint.Port(rawValue: Proto.tcpPort)!)
        }
    }

    var displayName: String {
        switch self {
        case .service(let name): return name
        case .host(let h): return h
        }
    }
}

/// Connection to the Mac agent: TCP for commands, UDP for pointer movement, and a USB
/// listener (127.0.0.1:47818) that the agent reaches through usbmuxd when the cable is plugged in.
/// Public API is main-thread; networking runs on a private queue.
final class Connection: ObservableObject {
    static let shared = Connection()

    enum State { case idle, connecting, connected }

    @Published private(set) var state: State = .idle
    @Published private(set) var macName: String?
    @Published private(set) var viaUSB = false
    @Published private(set) var lastError: String?
    /// 0 none, 1 wrong PIN, 2 too many attempts, 3 version mismatch.
    @Published private(set) var lastDenyReason = 0
    @Published private(set) var target: MacTarget?

    private let q = DispatchQueue(label: "paddeck.net")
    private let deviceName: String

    // Queue-owned state
    private var tcp: NWConnection?
    private var udp: NWConnection?
    private var buffer = Data()
    private var token: UInt32 = 0
    private var wanted = false
    private var generation = 0
    private var lastRx = Date()
    private var pingTimer: DispatchSourceTimer?
    private var qTarget: MacTarget?
    private var qPin = ""
    private var usb = false
    private var usbBlocked = false
    private var usbListener: NWListener?

    private init() {
        deviceName = UIDevice.current.name
        q.async { self.startUSBListener() }
    }

    // MARK: - Public

    func connect(to target: MacTarget, pin: String) {
        self.target = target
        macName = target.displayName
        lastDenyReason = 0
        lastError = nil
        q.async {
            self.qTarget = target
            self.qPin = pin
            self.wanted = true
            self.usbBlocked = false
            self.generation += 1
            self.open()
        }
    }

    /// User-initiated: stops reconnecting and ignores the cable until the app is reopened.
    func disconnect() {
        q.async {
            self.wanted = false
            self.usbBlocked = true
            self.generation += 1
            self.close()
            self.publish(.idle)
        }
    }

    /// App came back to the foreground.
    func resume() {
        q.async {
            self.usbBlocked = false
            if self.usbListener == nil { self.startUSBListener() }
            if self.wanted && self.tcp == nil {
                self.generation += 1
                self.open()
            } else if self.token != 0 {
                self.sendFrame(.ping)   // the socket may have died while suspended
            }
        }
    }

    func sendButton(_ b: MouseButton, _ a: PressAction) {
        command(.button, Data([b.rawValue, a.rawValue]))
    }

    func sendMove(dx: Int, dy: Int) {
        guard dx != 0 || dy != 0 else { return }
        fast(.move, Proto.be16(dx) + Proto.be16(dy))
    }

    func sendScroll(dy: Int, dx: Int) {
        guard dx != 0 || dy != 0 else { return }
        fast(.scroll, Proto.be16(dy) + Proto.be16(dx))
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        command(.text, Data(text.utf8))
    }

    func sendKey(_ code: Int, mods: Mods = [], action: PressAction = .press) {
        command(.key, Data([UInt8((code >> 8) & 0xff), UInt8(code & 0xff), mods.rawValue, action.rawValue]))
    }

    func sendMedia(_ key: MediaKey) {
        command(.media, Data([key.code]))
    }

    func sendOpen(_ target: String) {
        guard !target.isEmpty else { return }
        command(.open, Data(target.utf8))
    }

    // MARK: - Publishing

    private func publish(_ st: State, name: String? = nil, error: String? = nil) {
        let usbNow = usb && st != .idle
        DispatchQueue.main.async {
            self.state = st
            self.viaUSB = usbNow
            if let n = name { self.macName = n }
            if let e = error { self.lastError = e }
            if st == .connected { self.lastError = nil }
        }
    }

    // MARK: - Sockets (queue only)

    private static func tcpParams() -> NWParameters {
        let o = NWProtocolTCP.Options()
        o.noDelay = true
        o.connectionTimeout = 5
        let p = NWParameters(tls: nil, tcp: o)
        p.serviceClass = .responsiveData
        return p
    }

    private func open() {
        close()
        guard let t = qTarget else { return }
        publish(.connecting)
        attach(NWConnection(to: t.endpoint, using: Connection.tcpParams()), pin: qPin)
    }

    private func attach(_ c: NWConnection, pin: String) {
        tcp = c
        buffer.removeAll()
        token = 0
        lastRx = Date()
        let gen = generation
        c.stateUpdateHandler = { [weak self] st in
            guard let self = self, gen == self.generation, c === self.tcp else { return }
            switch st {
            case .ready:
                self.lastRx = Date()
                self.sendHello(pin)
                self.startPing()
                if !self.usb { self.openUDP(like: c) }
                self.receive(c)
            case .waiting(let e), .failed(let e):
                self.fail(Connection.describe(e))
            default:
                break
            }
        }
        c.start(queue: q)
    }

    private func openUDP(like c: NWConnection) {
        guard case let .hostPort(host, _)? = c.currentPath?.remoteEndpoint else { return }
        // Pointer packets go in the Wi-Fi voice queue (highest priority, least buffering).
        let params = NWParameters.udp
        params.serviceClass = .interactiveVoice
        let u = NWConnection(host: host, port: NWEndpoint.Port(rawValue: Proto.udpPort)!, using: params)
        u.start(queue: q)
        udp = u
    }

    private func close() {
        pingTimer?.cancel()
        pingTimer = nil
        tcp?.cancel()
        tcp = nil
        udp?.cancel()
        udp = nil
        token = 0
        usb = false
    }

    private func fail(_ reason: String) {
        let wasUSB = usb
        close()
        let message = wasUSB ? "Cabo desconectado" : reason
        if wanted, qTarget != nil {
            publish(.connecting, error: message)
            generation += 1
            let gen = generation
            q.asyncAfter(deadline: .now() + 2) {
                if self.wanted && self.generation == gen && self.tcp == nil { self.open() }
            }
        } else {
            publish(.idle, error: message)
        }
    }

    private func startPing() {
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            guard let self = self, self.tcp != nil else { return }
            if Date().timeIntervalSince(self.lastRx) > 6.5 {
                self.fail("Conexão perdida")
            } else {
                self.sendFrame(.ping)
            }
        }
        t.resume()
        pingTimer = t
    }

    private func sendHello(_ pin: String) {
        let pinBytes = Array(pin.utf8.prefix(255))
        var p = Data([Proto.version, UInt8(pinBytes.count)])
        p.append(contentsOf: pinBytes)
        p.append(contentsOf: Array(deviceName.utf8))
        sendFrame(.hello, p)
    }

    private func sendFrame(_ type: Proto.Out, _ payload: Data = Data()) {
        tcp?.send(content: Proto.frame(type, payload), completion: .contentProcessed { _ in })
    }

    private func command(_ type: Proto.Out, _ payload: Data) {
        q.async {
            guard self.token != 0 else { return }
            self.sendFrame(type, payload)
        }
    }

    /// Movement/scroll: UDP when available (lossy is fine), TCP otherwise.
    private func fast(_ type: Proto.Out, _ bytes: [UInt8]) {
        q.async {
            guard self.token != 0 else { return }
            if let u = self.udp, u.state == .ready {
                let t = self.token
                var d = Data([UInt8(t >> 24 & 0xff), UInt8(t >> 16 & 0xff), UInt8(t >> 8 & 0xff), UInt8(t & 0xff), type.rawValue])
                d.append(contentsOf: bytes)
                u.send(content: d, completion: .idempotent)
            } else {
                self.sendFrame(type, Data(bytes))
            }
        }
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self = self, c === self.tcp else { return }
            if let d = data, !d.isEmpty {
                self.lastRx = Date()
                self.buffer.append(d)
                self.parse()
            }
            guard c === self.tcp else { return }   // closed while parsing (DENIED)
            if done || err != nil {
                self.fail("O Mac encerrou a conexão")
            } else {
                self.receive(c)
            }
        }
    }

    private func parse() {
        while buffer.count >= 3 {
            let s = buffer.startIndex
            let len = Int(buffer[s + 1]) << 8 | Int(buffer[s + 2])
            guard buffer.count >= 3 + len else { return }
            let type = buffer[s]
            let payload = buffer.subdata(in: (s + 3)..<(s + 3 + len))
            buffer.removeSubrange(s..<(s + 3 + len))
            handle(type, payload)
            if tcp == nil { return }
        }
    }

    private func handle(_ type: UInt8, _ p: Data) {
        switch Proto.In(rawValue: type) {
        case .welcome?:
            guard p.count >= 4 else { return }
            token = UInt32(p.u8(0)) << 24 | UInt32(p.u8(1)) << 16 | UInt32(p.u8(2)) << 8 | UInt32(p.u8(3))
            let sent = String(data: p.subdata(in: (p.startIndex + 4)..<p.endIndex), encoding: .utf8) ?? ""
            let name = sent.isEmpty ? (qTarget?.displayName ?? "Mac") : sent
            if !usb, let t = qTarget {
                let pin = qPin
                DispatchQueue.main.async {
                    Prefs.setPin(pin, for: [t.displayName, name])
                    switch t {
                    case .service(let n): Prefs.lastMacName = n; Prefs.lastMacHost = nil
                    case .host(let h): Prefs.lastMacHost = h; Prefs.lastMacName = nil
                    }
                }
            }
            publish(.connected, name: name)

        case .denied?:
            let reason = p.isEmpty ? 1 : Int(p.u8(0))
            wanted = false
            generation += 1
            let t = qTarget
            close()
            DispatchQueue.main.async {
                self.lastDenyReason = reason
                if reason == 1, let t = t { Prefs.setPin(nil, for: [t.displayName]) }   // forget the wrong PIN
            }
            let message = reason == 2 ? "Muitas tentativas. Aguarde 1 minuto."
                        : reason == 3 ? "Versão do PadDeck no Mac incompatível."
                        : "PIN incorreto."
            publish(.idle, error: message)

        default:
            break   // PONG: lastRx already updated
        }
    }

    private static func describe(_ e: NWError) -> String {
        if case .dns(let code) = e, code == -65570 {   // kDNSServiceErr_PolicyDenied
            return "Permita a Rede Local em Ajustes › PadDeck"
        }
        if case .posix(let p) = e {
            switch p {
            case .ECONNREFUSED: return "O PadDeck não está aberto no Mac"
            case .ETIMEDOUT: return "O Mac não respondeu"
            case .ENETDOWN, .ENETUNREACH: return "Sem conexão com a rede"
            default: break
            }
        }
        return "Não foi possível conectar"
    }

    // MARK: - USB cable (usbmuxd)

    private func startUSBListener() {
        let params = Connection.tcpParams()
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: Proto.usbPort)!) else { return }
        l.newConnectionHandler = { [weak self] c in self?.acceptUSB(c) }
        l.stateUpdateHandler = { [weak self] st in
            if case .failed = st {
                self?.usbListener?.cancel()
                self?.usbListener = nil
            }
        }
        l.start(queue: q)
        usbListener = l
    }

    /// usbmuxd connects from the device's loopback; anything else is refused.
    private static func isLoopback(_ e: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = e else { return false }
        switch host {
        case .ipv4(let a): return a == .loopback
        case .ipv6(let a): return a == .loopback || a.debugDescription.hasSuffix("127.0.0.1")
        case .name(let n, _): return n == "localhost"
        @unknown default: return false
        }
    }

    private func acceptUSB(_ c: NWConnection) {
        guard Connection.isLoopback(c.endpoint), !usbBlocked, !(usb && tcp != nil) else {
            c.cancel()
            return
        }
        // The cable wins over Wi-Fi.
        generation += 1
        close()
        usb = true
        publish(.connecting)
        attach(c, pin: "")
    }
}

/// Finds Macs running the PadDeck agent on the local network.
final class MacBrowser: ObservableObject {
    @Published private(set) var macs: [String] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: Proto.bonjourType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { r -> String? in
                if case let .service(name, _, _, _) = r.endpoint { return name }
                return nil
            }
            self?.macs = Array(Set(names)).sorted()
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

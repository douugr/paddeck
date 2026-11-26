import Foundation

// Swift face of pdcrypto.c, shared by the Mac agent and the App Store app (keep identical:
// the App Store app has a copy in app/PadDeck/Crypto, the original is crypto/ in douugr/paddeck). See docs/PROTOCOL.md.

enum PDWire {
    static let version: UInt8 = 2
    /// Outer frame type of an encrypted record; the inner type is the first plaintext byte.
    static let sealed: UInt8 = 0xE0
    /// Largest inner record (type + payload) that fits in one frame.
    static let maxInner = 65535 - Int(PD_TAG_SIZE)
}

/// Keys and counters of one encrypted connection.
final class SecureChannel {
    fileprivate var s = pd_session()
    /// Identifies the session in UDP datagrams (sent by the Mac in WELCOME).
    var sessionID: UInt32 = 0

    fileprivate init() {}
    deinit { pd_session_wipe(&s) }

    /// Encrypts [type, payload] into a full TCP frame: 0xE0, u16 length, ciphertext || tag.
    func sealFrame(_ type: UInt8, _ payload: Data = Data()) -> Data {
        var inner = [type]
        inner.append(contentsOf: payload.prefix(PDWire.maxInner - 1))
        let total = inner.count + Int(PD_TAG_SIZE)
        let head: [UInt8] = [PDWire.sealed, UInt8(total >> 8), UInt8(total & 0xff)]
        var out = [UInt8](repeating: 0, count: total)
        pd_seal(&s, head, head.count, inner, inner.count, &out)
        return Data(head + out)
    }

    /// Decrypts the payload of a 0xE0 frame. nil means forged or out of order: close the connection.
    func openFrame(_ payload: Data) -> (type: UInt8, payload: Data)? {
        let n = payload.count
        guard n > Int(PD_TAG_SIZE), n <= 65535 else { return nil }
        let head: [UInt8] = [PDWire.sealed, UInt8(n >> 8), UInt8(n & 0xff)]
        let input = [UInt8](payload)
        var plain = [UInt8](repeating: 0, count: n - Int(PD_TAG_SIZE))
        guard pd_open(&s, head, head.count, input, n, &plain) == 0 else { return nil }
        return (plain[0], Data(plain[1...]))
    }

    /// Client: an encrypted UDP datagram for [type, payload].
    func sealDatagram(_ type: UInt8, _ payload: [UInt8]) -> Data {
        let inner = [type] + payload
        var out = [UInt8](repeating: 0, count: Int(PD_UDP_HEAD) + inner.count + Int(PD_TAG_SIZE))
        let n = pd_udp_seal(&s, sessionID, inner, inner.count, &out)
        return Data(out.prefix(n))
    }

    /// Mac: decrypts a datagram. nil if forged, too old or a replay.
    func openDatagram(_ d: Data) -> (type: UInt8, payload: Data)? {
        let input = [UInt8](d)
        guard input.count > Int(PD_UDP_HEAD) + Int(PD_TAG_SIZE) else { return nil }
        var plain = [UInt8](repeating: 0, count: input.count - Int(PD_UDP_HEAD) - Int(PD_TAG_SIZE))
        let n = pd_udp_open(&s, input, input.count, &plain)
        guard n > 0 else { return nil }
        return (plain[0], Data(plain[1..<Int(n)]))
    }

    /// The session id a datagram claims (0 if too short).
    static func datagramSessionID(_ d: Data) -> UInt32 {
        let input = [UInt8](d)
        return pd_udp_session_id(input, input.count)
    }
}

/// Long-term X25519 identity (secret key + public key, 32 bytes each).
struct PDIdentity {
    let secretKey: [UInt8]
    let publicKey: [UInt8]

    static func generate() -> PDIdentity {
        var sk = [UInt8](repeating: 0, count: 32), pk = [UInt8](repeating: 0, count: 32)
        pd_keypair(&sk, &pk)
        return PDIdentity(secretKey: sk, publicKey: pk)
    }

    init?(secretKey sk: [UInt8]) {
        guard sk.count == 32 else { return nil }
        var pk = [UInt8](repeating: 0, count: 32)
        pd_public_key(&pk, sk)
        self.init(secretKey: sk, publicKey: pk)
    }

    private init(secretKey: [UInt8], publicKey: [UInt8]) {
        self.secretKey = secretKey
        self.publicKey = publicKey
    }
}

/// Hex form of a public key (used as a dictionary key in the settings).
func pdHex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

func pdUnhex(_ s: String) -> [UInt8]? {
    guard s.count % 2 == 0 else { return nil }
    var out: [UInt8] = []
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
        out.append(b)
        i = j
    }
    return out
}

// MARK: - Client side (iPhone / iPad)

/// Pairing in progress: built from the Mac's identity and the PIN typed by the user.
final class PairingClient {
    private var st: pd_pair_state
    /// PAIR message: nonce[16] || Y[32].
    let message: [UInt8]

    init?(macKey: [UInt8], pin: String) {
        let len = pin.utf8.count
        guard macKey.count == 32, len > 0 else { return nil }
        var state = pd_pair_state()
        var msg = [UInt8](repeating: 0, count: Int(PD_PAIR_MSG))
        guard pd_pair_client_start(&state, macKey, pin, len, &msg) == 0 else { return nil }
        st = state
        message = msg
    }

    /// The Mac's PAIR_REPLY (32 bytes) -> keys. nil if invalid.
    func finish(_ reply: Data) -> SecureChannel? {
        guard reply.count == 32 else { return nil }
        let ch = SecureChannel()
        return pd_pair_client_finish(&ch.s, &st, [UInt8](reply)) == 0 ? ch : nil
    }

    deinit { withUnsafeMutableBytes(of: &st) { _ = $0.initializeMemory(as: UInt8.self, repeating: 0) } }
}

/// Reconnection of an already paired device.
final class ResumeClient {
    private var st: pd_resume_state
    /// Ephemeral public key for the RESUME message.
    let ephemeral: [UInt8]

    init() {
        var state = pd_resume_state()
        var e = [UInt8](repeating: 0, count: 32)
        pd_resume_client_start(&state, &e)
        st = state
        ephemeral = e
    }

    /// The Mac's RESUME_REPLY (32 bytes) -> keys. nil if invalid.
    func finish(_ reply: Data, me: PDIdentity, macKey: [UInt8]) -> SecureChannel? {
        guard reply.count == 32, macKey.count == 32 else { return nil }
        let ch = SecureChannel()
        let rc = pd_resume_client_finish(&ch.s, &st, me.secretKey, me.publicKey, macKey, [UInt8](reply))
        return rc == 0 ? ch : nil
    }

    deinit { withUnsafeMutableBytes(of: &st) { _ = $0.initializeMemory(as: UInt8.self, repeating: 0) } }
}

// MARK: - Mac side

enum PDServerHandshake {
    /// Answers PAIR (48 bytes) with the current PIN: (keys, PAIR_REPLY). A wrong PIN only shows
    /// when the client's first record fails to open.
    static func pair(_ msg: Data, me: PDIdentity, pin: String) -> (SecureChannel, Data)? {
        guard msg.count == Int(PD_PAIR_MSG) else { return nil }
        let len = pin.utf8.count
        guard len > 0 else { return nil }
        let ch = SecureChannel()
        var reply = [UInt8](repeating: 0, count: 32)
        let rc = pd_pair_server(&ch.s, me.publicKey, pin, len, [UInt8](msg), &reply)
        return rc == 0 ? (ch, Data(reply)) : nil
    }

    /// Answers RESUME from a paired device: (keys, RESUME_REPLY).
    static func resume(device: [UInt8], ephemeral: Data, me: PDIdentity) -> (SecureChannel, Data)? {
        guard device.count == 32, ephemeral.count == 32 else { return nil }
        let ch = SecureChannel()
        var reply = [UInt8](repeating: 0, count: 32)
        let rc = pd_resume_server(&ch.s, me.secretKey, me.publicKey, device, [UInt8](ephemeral), &reply)
        return rc == 0 ? (ch, Data(reply)) : nil
    }
}

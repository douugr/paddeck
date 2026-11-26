# PadDeck protocol (v2)

The iPhone/iPad app (client) talks to the Mac agent over the local network. Since v2
(Mac agent 1.3, App Store app 1.2, iOS 8 app 1.8) everything sent over Wi-Fi is encrypted
and authenticated; the PIN is only used once, to pair a device.

| Channel | Port  | Used for |
|---------|-------|----------|
| TCP     | 47816 | handshake, clicks, keys, text, media, open app, keep-alive |
| UDP     | 47817 | pointer movement and scrolling (lossy is fine, latency matters) |
| TCP     | 47818 | cable mode: the **app listens** on 127.0.0.1 and the agent connects through usbmuxd |

The agent advertises itself with Bonjour as `_paddeck._tcp` on the TCP port.
All integers are big-endian.

The cryptography lives in `crypto/` (C, on [Monocypher](https://monocypher.org) 4.0.3), shared
by the three apps: `pdcrypto.c` implements everything below, `PDSecure.swift` wraps it for
Swift, and `crypto/tests/run.sh` runs its tests.

## TCP frames

```
u8  type
u16 length      (payload length, 0..65535)
u8  payload[length]
```

After the handshake every frame is a **sealed** frame:

```
u8  0xE0
u16 length      (n + 16)
u8  ciphertext[n] || tag[16]      XChaCha20-Poly1305 of [u8 type, payload...]
```

The 3-byte header is the associated data. Each direction has its own key and counts its
records from 0; the 24-byte nonce is that counter (little-endian u64) followed by zeros. A record
that fails to open, arrives out of order or is replayed ends the connection.

### Commands (client → agent, sealed)

| Type | Name   | Payload |
|------|--------|---------|
| 0x02 | PING   | empty |
| 0x10 | BUTTON | `u8 button` (0 left, 1 right, 2 middle), `u8 action` (0 down, 1 up, 2 click) |
| 0x11 | MOVE   | `i16 dx`, `i16 dy` (fallback when UDP is unavailable) |
| 0x12 | SCROLL | `i16 dy`, `i16 dx` in pixels; positive dy scrolls content down (finger moving down, "natural") |
| 0x20 | TEXT   | UTF-8 text, typed layout-independently |
| 0x21 | KEY    | `u16 keycode` (macOS virtual key, kVK_*), `u8 mods`, `u8 action` (0 down, 1 up, 2 press) |
| 0x22 | MEDIA  | `u8 key` (NX_KEYTYPE_*: 0 vol+, 1 vol−, 2 bright+, 3 bright−, 7 mute, 16 play, 17 next, 18 previous) |
| 0x23 | OPEN   | UTF-8: an app name (`Safari`), a bundle id (`com.apple.Music`), a path or a URL (`https://…`) |

`mods` bits: 0 shift, 1 control, 2 option, 3 command, 4 fn.

The agent answers PING with a sealed PONG (0x83). It closes a session after 10 s without any
frame (the client pings every 2 s, in the clear until the handshake gives it keys). When a
session ends, any mouse button it left pressed is released.

## Handshake (Wi-Fi)

Each side has a long-term X25519 key: the Mac in `~/Library/Application Support/PadDeck/identity.key`,
the App Store app in the Keychain (this device only), the iOS 8 app in `Library/PadDeck/identity.key`.
The Mac keeps the public keys of the devices it paired with; each device keeps the public keys
of the Macs it paired with.

```
client                                   agent
HELLO        u8 version (=2)        →
                                    ←    SERVER_HELLO   u8 version, Mac key[32]

  first time with this Mac (PIN):
PAIR         nonce[16] || Y[32]     →
                                    ←    PAIR_REPLY     Y[32]

  already paired:
RESUME       device key[32] || E[32] →
                                    ←    RESUME_REPLY   E[32]

  both:
sealed READY device key[32] || name →
                                    ←    sealed WELCOME u32 session id, Mac name
```

| Type | Name         | Direction |
|------|--------------|-----------|
| 0x01 | HELLO        | client → agent |
| 0x03 | PAIR         | client → agent |
| 0x04 | RESUME       | client → agent |
| 0x05 | READY        | client → agent, sealed |
| 0x81 | WELCOME      | agent → client, sealed (in the clear on the cable) |
| 0x82 | DENIED       | agent → client, `u8 reason`: 1 wrong PIN, 2 too many attempts, 3 bad version, 4 not paired |
| 0x84 | SERVER_HELLO | agent → client |
| 0x85 | PAIR_REPLY   | agent → client |
| 0x86 | RESUME_REPLY | agent → client |

### Pairing: CPace with the PIN

1. The client picks a random `nonce` and derives a generator from the PIN:
   `G = Elligator2(BLAKE2b-256("PadDeck v2 CPace generator\0" || u8 len || PIN || nonce || Mac key))`.
2. Each side picks a random scalar `y` and sends `Y = X25519(y, G)`; both compute
   `K = X25519(y, Y_other)`.
3. `H = BLAKE2b-512("PadDeck v2 pair\0" || Mac key || nonce || Y_client || Y_mac || K)`.

With a wrong PIN the two generators differ, the keys differ and READY doesn't open: the agent
answers DENIED 1. Recording the exchange reveals nothing about the PIN; an active attacker gets
exactly one guess per attempt. After 5 wrong PINs a host is refused for 60 s, and after 10 wrong
PINs from any host the agent changes the PIN. Every successful pairing also changes it, so each
PIN pairs one device. The Mac key is part of `H`, so a key swapped in SERVER_HELLO breaks the
handshake instead of getting pinned.

### Reconnecting: three Diffie-Hellmans

The client sends its long-term key and a fresh ephemeral key `E_c`; the Mac answers with its own
ephemeral key `E_m` (DENIED 4 if the device isn't paired, and the client forgets that Mac):

```
dh1 = X25519(e_c, Mac key)      only the real Mac can compute it
dh2 = X25519(device key, e_m)   only the real device can compute it
dh3 = X25519(e_c, e_m)          forward secrecy
H   = BLAKE2b-512("PadDeck v2 resume\0" || Mac key || device key || E_c || E_m || dh1 || dh2 || dh3)
```

Any X25519 result of all zeros (a low-order point) aborts the handshake.

### Keys

```
TCP client → agent   BLAKE2b-256(key = H, "tcp client->mac")
TCP agent → client   BLAKE2b-256(key = H, "tcp mac->client")
UDP client → agent   BLAKE2b-256(key = H, "udp client->mac")
```

The agent marks the session as authenticated only after READY opens (and, when reconnecting, its
device key matches RESUME). The client trusts the Mac once WELCOME opens.

## UDP datagrams

```
u32 session id  (from WELCOME)
u64 counter     (1, 2, 3…)
ciphertext || tag   XChaCha20-Poly1305 of [u8 type (0x11 MOVE or 0x12 SCROLL), payload...]
```

The first 12 bytes are the associated data and the counter is the nonce. The agent accepts a
datagram only for a live session from the same host, if it opens, and if its counter wasn't seen
yet and is at most 64 behind the newest one.

## Cable mode (USB)

The agent keeps a `Listen` session open with macOS's usbmuxd (`/var/run/usbmuxd`). When an iOS
device is attached over USB it sends usbmuxd a `Connect` request for port 47818 on that device
(retrying every 2 s while the app is closed). Once usbmuxd answers `Result 0`, the socket is a
plain byte stream to the app. The cable is the proof of trust: no handshake and no encryption.
The app sends HELLO as `u8 version, u8 0, device name`, the agent answers with a plain WELCOME
(`u32` 0, Mac name), and then the commands above go as plain frames (MOVE/SCROLL included,
since there is no UDP). Version 1 apps still work over the cable.

## Version 1

v1 sent the PIN in HELLO in the clear and nothing was encrypted. The v2 agent answers a v1 HELLO
over Wi-Fi with DENIED 3, and v1 agents answer a v2 HELLO the same way, so each side can tell the
user to update the other.

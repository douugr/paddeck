# PadDeck protocol (v1)

The iPad app (client) talks to the Mac agent over the local network.

| Channel | Port  | Used for |
|---------|-------|----------|
| TCP     | 47816 | handshake, clicks, keys, text, media, open app, keep-alive |
| UDP     | 47817 | pointer movement and scrolling (lossy is fine, latency matters) |
| TCP     | 47818 | cable mode: the **iPad app listens** on 127.0.0.1 and the agent connects through usbmuxd |

The agent advertises itself with Bonjour as `_paddeck._tcp` on the TCP port.
All integers are big-endian.

## TCP frames

```
u8  type
u16 length      (payload length, 0..65535)
u8  payload[length]
```

### Client → agent

| Type | Name   | Payload |
|------|--------|---------|
| 0x01 | HELLO  | `u8 version (=1)`, `u8 pinLen`, `pin[pinLen]` (ASCII digits), rest = device name (UTF-8) |
| 0x02 | PING   | empty |
| 0x10 | BUTTON | `u8 button` (0 left, 1 right, 2 middle), `u8 action` (0 down, 1 up, 2 click) |
| 0x11 | MOVE   | `i16 dx`, `i16 dy` (fallback when UDP is unavailable) |
| 0x12 | SCROLL | `i16 dy`, `i16 dx` in pixels; positive dy scrolls content down (finger moving down, "natural") |
| 0x20 | TEXT   | UTF-8 text, typed layout-independently |
| 0x21 | KEY    | `u16 keycode` (macOS virtual key, kVK_*), `u8 mods`, `u8 action` (0 down, 1 up, 2 press) |
| 0x22 | MEDIA  | `u8 key` (NX_KEYTYPE_*: 0 vol+, 1 vol−, 2 bright+, 3 bright−, 7 mute, 16 play, 17 next, 18 previous) |
| 0x23 | OPEN   | UTF-8: an app name (`Safari`), a bundle id (`com.apple.Music`), a path or a URL (`https://…`) |

`mods` bits: 0 shift, 1 control, 2 option, 3 command, 4 fn.

Every type except HELLO and PING is ignored until the agent sends WELCOME.

### Agent → client

| Type | Name    | Payload |
|------|---------|---------|
| 0x81 | WELCOME | `u32 token`, rest = the Mac's name (UTF-8) |
| 0x82 | DENIED  | `u8 reason` (1 wrong PIN, 2 too many attempts, 3 bad version) |
| 0x83 | PONG    | empty |

The agent closes a session after 10 s without any frame (the client pings every 2 s).
When a session ends, any mouse button it left pressed is released.

## UDP datagrams

```
u32 token       (from WELCOME)
u8  type        (0x11 MOVE or 0x12 SCROLL)
payload         (same as the TCP frames)
```

Datagrams are accepted only when the token belongs to a live session and they come
from the same host as that session's TCP connection.

## Security

The PIN (4 digits, shown in the agent's menu) keeps other devices on the network from
taking control. After 5 wrong PINs a host is refused for 60 s. Traffic is not encrypted:
use it on a network you trust.

## Cable mode (USB)

The agent keeps a `Listen` session open with macOS's usbmuxd (`/var/run/usbmuxd`). When an iOS
device is attached over USB it sends usbmuxd a `Connect` request for port 47818 on that device
(retrying every 2 s while the app is closed). Once usbmuxd answers `Result 0`, the socket is a
plain byte stream to the app and the protocol above runs unchanged, with two differences: the
iPad still sends HELLO first but the PIN is not checked (the cable is the proof of trust), and
MOVE/SCROLL go over TCP since there is no UDP.

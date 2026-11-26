#import "PDConnection.h"
#import "PDSettings.h"
#import <UIKit/UIKit.h>
#include "pdcrypto.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

NSString *const PDConnectionChangedNotification = @"PDConnectionChanged";

static const uint16_t kTCPPort = 47816;
static const uint16_t kUDPPort = 47817;
static const uint16_t kUSBPort = 47818;   // the Mac agent reaches this through usbmuxd (cable)

// Protocol v2: over Wi-Fi everything is encrypted (see docs/PROTOCOL.md). The PIN pairs the iPad
// once; later connections use the keys exchanged then. The cable stays in the clear.
static const uint8_t kVersion = 2;

enum {
    kHello = 0x01, kPing = 0x02, kPair = 0x03, kResume = 0x04, kReady = 0x05,
    kButton = 0x10, kMove = 0x11, kScroll = 0x12,
    kText = 0x20, kKey = 0x21, kMedia = 0x22, kOpen = 0x23,
    kWelcome = 0x81, kDenied = 0x82, kPong = 0x83,
    kServerHello = 0x84, kPairReply = 0x85, kResumeReply = 0x86,
    kSealed = 0xE0,
};

enum { kDeniedPIN = 1, kDeniedLocked = 2, kDeniedVersion = 3, kDeniedNotPaired = 4 };

static NSString *Hex(const uint8_t *b, size_t n) {
    NSMutableString *s = [NSMutableString stringWithCapacity:n * 2];
    for (size_t i = 0; i < n; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}

#pragma mark - Identity

/// This iPad's long-term key: Library/PadDeck/identity.key (readable only by the app's user).
static uint8_t gSecretKey[32], gPublicKey[32];

static void LoadIdentity(void) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject
                     stringByAppendingPathComponent:@"PadDeck"];
    NSString *file = [dir stringByAppendingPathComponent:@"identity.key"];
    NSData *d = [NSData dataWithContentsOfFile:file];
    if (d.length == 32) {
        memcpy(gSecretKey, d.bytes, 32);
    } else {
        pd_keypair(gSecretKey, gPublicKey);
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                       attributes:@{NSFilePosixPermissions: @0700} error:NULL];
        [fm createFileAtPath:file contents:[NSData dataWithBytes:gSecretKey length:32]
                  attributes:@{NSFilePosixPermissions: @0600}];
    }
    pd_public_key(gPublicKey, gSecretKey);
}

@interface PDConnection ()
@property (nonatomic, readwrite) PDState state;
@property (nonatomic, readwrite, copy) NSString *host;
@property (nonatomic, readwrite, copy) NSString *macName;
@property (nonatomic, readwrite) int lastDenyReason;
@property (nonatomic, readwrite, copy) NSString *lastError;
@property (nonatomic, readwrite) BOOL viaUSB;
@end

@implementation PDConnection {
    dispatch_queue_t _q;
    int _tcp;
    int _udp;
    dispatch_source_t _readSource;
    dispatch_source_t _pingTimer;
    NSMutableData *_buffer;
    BOOL _authed;             // NO until WELCOME
    pd_session _session;      // keys, valid while _secure
    BOOL _secure;
    uint32_t _sessionID;      // from WELCOME, identifies our UDP datagrams
    pd_pair_state _pairState;
    BOOL _pairing;
    pd_resume_state _resumeState;
    BOOL _resuming;
    uint8_t _macKey[32];
    BOOL _haveMacKey;
    BOOL _wanted;             // user wants to be connected (drives auto-reconnect)
    NSUInteger _generation;   // invalidates retries scheduled for older attempts
    CFAbsoluteTime _lastRx;
    NSString *_qHost, *_qPin, *_qName;   // copies owned by the queue
    BOOL _usb;                // current connection came through the cable
    BOOL _usbBlocked;         // user tapped "Trocar Mac": ignore the cable until reopened
    int _usbListen;
    dispatch_source_t _usbSource;
}

+ (instancetype)shared {
    static PDConnection *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[PDConnection alloc] init]; });
    return c;
}

- (instancetype)init {
    if ((self = [super init])) {
        _q = dispatch_queue_create("paddeck.net", DISPATCH_QUEUE_SERIAL);
        _tcp = -1;
        _udp = -1;
        _buffer = [NSMutableData data];
        _usbListen = -1;
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:PDPrefPins];   // replaced by pairing
        dispatch_async(_q, ^{
            LoadIdentity();
            [self startUSBListener];
        });
    }
    return self;
}

#pragma mark - Public

+ (BOOL)isPairedTarget:(NSString *)nameOrHost {
    if (!nameOrHost.length) return NO;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *key = [d dictionaryForKey:PDPrefPairedTargets][nameOrHost];
    return key && [d dictionaryForKey:PDPrefPairedMacs][key] != nil;
}

- (void)connectToHost:(NSString *)host name:(NSString *)name pin:(NSString *)pin {
    self.host = host;
    self.macName = name.length ? name : host;
    self.lastDenyReason = 0;
    self.lastError = nil;
    NSString *h = [host copy], *p = [pin copy], *n = [name copy];
    dispatch_async(_q, ^{
        self->_qHost = h;
        self->_qPin = p;
        self->_qName = n;
        self->_wanted = YES;
        self->_usbBlocked = NO;
        self->_generation++;
        [self open];
    });
}

- (void)disconnect {
    dispatch_async(_q, ^{
        self->_wanted = NO;
        self->_usbBlocked = YES;
        self->_generation++;
        [self closeSockets];
        [self publishState:PDStateIdle macName:nil error:nil];
    });
}

- (void)resumeIfNeeded {
    dispatch_async(_q, ^{
        self->_usbBlocked = NO;
        if (self->_usbListen < 0) [self startUSBListener];
        if (self->_wanted && !self->_authed && self->_tcp < 0) {
            self->_generation++;
            [self open];
        } else if (self->_wanted && self->_authed) {
            // The socket may have died while suspended; a ping will tell.
            [self sendFrame:kPing payload:nil];
        }
    });
}

#pragma mark - State publishing

- (void)publishState:(PDState)st macName:(NSString *)name error:(NSString *)err {
    BOOL usb = _usb && st != PDStateIdle;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.state = st;
        self.viaUSB = usb;
        if (name) self.macName = name;
        if (err) self.lastError = err;
        if (st == PDStateConnected) self.lastError = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:PDConnectionChangedNotification object:self];
    });
}

#pragma mark - Sockets (queue only)

- (void)open {
    [self closeSockets];
    [self publishState:PDStateConnecting macName:nil error:nil];

    struct addrinfo hints;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *res = NULL;
    char port[8];
    snprintf(port, sizeof port, "%u", kTCPPort);
    if (getaddrinfo(_qHost.UTF8String, port, &hints, &res) != 0 || !res) {
        [self failed:@"Endereço inválido"];
        return;
    }
    struct sockaddr_in addr;
    memcpy(&addr, res->ai_addr, sizeof addr);
    freeaddrinfo(res);

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { [self failed:@"Erro de socket"]; return; }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);

    // Non-blocking connect with a timeout.
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    int r = connect(fd, (struct sockaddr *)&addr, sizeof addr);
    if (r < 0 && errno != EINPROGRESS) {
        close(fd);
        [self failed:@"Não foi possível conectar"];
        return;
    }
    if (r < 0) {
        fd_set wset;
        FD_ZERO(&wset);
        FD_SET(fd, &wset);
        struct timeval tv = { 4, 0 };
        int err = 0;
        socklen_t len = sizeof err;
        if (select(fd + 1, NULL, &wset, NULL, &tv) <= 0 ||
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) < 0 || err != 0) {
            close(fd);
            [self failed:@"O Mac não respondeu"];
            return;
        }
    }
    fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
    _tcp = fd;

    // UDP for pointer movement.
    int u = socket(AF_INET, SOCK_DGRAM, 0);
    if (u >= 0) {
        struct sockaddr_in ua = addr;
        ua.sin_port = htons(kUDPPort);
        fcntl(u, F_SETFL, fcntl(u, F_GETFL, 0) | O_NONBLOCK);
        setsockopt(u, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        int tos = 0xB8;   // DSCP EF: Wi-Fi voice queue (highest priority, least buffering)
        setsockopt(u, IPPROTO_IP, IP_TOS, &tos, sizeof tos);
        if (connect(u, (struct sockaddr *)&ua, sizeof ua) == 0) _udp = u;
        else close(u);
    }
    [self attach:fd pin:_qPin];
}

/// Starts the protocol on a connected socket (Wi-Fi or cable): read source, HELLO, pings.
- (void)attach:(int)fd pin:(NSString *)pinText {
    _tcp = fd;
    struct timeval stv = { 2, 0 };
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &stv, sizeof stv);
    [_buffer setLength:0];
    [self resetSession];
    _lastRx = CFAbsoluteTimeGetCurrent();

    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, _q);
    __weak PDConnection *weakSelf = self;
    dispatch_source_set_event_handler(src, ^{ [weakSelf readAvailable:fd]; });
    dispatch_source_set_cancel_handler(src, ^{ close(fd); });
    dispatch_resume(src);
    _readSource = src;

    // HELLO. Cable: version, empty PIN, device name (the Mac trusts the cable).
    // Wi-Fi: just the version; the name only travels encrypted, in READY.
    NSMutableData *hello = [NSMutableData dataWithBytes:&kVersion length:1];
    if (_usb) {
        uint8_t noPin = 0;
        [hello appendBytes:&noPin length:1];
        [hello appendData:[[[UIDevice currentDevice] name] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]];
    }
    [self sendFrame:kHello payload:hello];

    _pingTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _q);
    dispatch_source_set_timer(_pingTimer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(_pingTimer, ^{ [weakSelf pingTick]; });
    dispatch_resume(_pingTimer);
}

- (void)closeSockets {
    if (_pingTimer) { dispatch_source_cancel(_pingTimer); _pingTimer = nil; }
    if (_readSource) { dispatch_source_cancel(_readSource); _readSource = nil; }  // closes _tcp
    _tcp = -1;
    if (_udp >= 0) { close(_udp); _udp = -1; }
    [self resetSession];
    _usb = NO;
}

- (void)resetSession {
    _authed = NO;
    _secure = NO;
    _pairing = NO;
    _resuming = NO;
    _haveMacKey = NO;
    _sessionID = 0;
    pd_session_wipe(&_session);
    memset(&_pairState, 0, sizeof _pairState);
    memset(&_resumeState, 0, sizeof _resumeState);
}

#pragma mark - Cable (usbmuxd)

- (void)startUSBListener {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_len = sizeof a;
    a.sin_family = AF_INET;
    a.sin_port = htons(kUSBPort);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);   // usbmuxd connects locally on the device
    if (bind(fd, (struct sockaddr *)&a, sizeof a) < 0 || listen(fd, 2) < 0) {
        close(fd);
        return;
    }
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
    _usbListen = fd;
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, _q);
    __weak PDConnection *weakSelf = self;
    dispatch_source_set_event_handler(src, ^{ [weakSelf acceptUSB:fd]; });
    dispatch_source_set_cancel_handler(src, ^{ close(fd); });
    dispatch_resume(src);
    _usbSource = src;
}

- (void)acceptUSB:(int)lfd {
    for (;;) {
        int fd = accept(lfd, NULL, NULL);
        if (fd < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return;
            // listener broke (e.g. while suspended): rebuild it
            dispatch_source_cancel(_usbSource);
            _usbSource = nil;
            _usbListen = -1;
            [self startUSBListener];
            return;
        }
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) & ~O_NONBLOCK);
        if (_usbBlocked || (_usb && _tcp >= 0)) {   // ignored, or already on the cable
            close(fd);
            continue;
        }
        // The cable wins over Wi-Fi.
        _generation++;
        [self closeSockets];
        _usb = YES;
        [self publishState:PDStateConnecting macName:nil error:nil];
        [self attach:fd pin:@""];
    }
}

- (void)pingTick {
    if (_tcp < 0) return;
    if (CFAbsoluteTimeGetCurrent() - _lastRx > 6.5) {
        [self failed:@"Conexão perdida"];
        return;
    }
    [self sendFrame:kPing payload:nil];
}

- (void)failed:(NSString *)reason {
    BOOL wasUSB = _usb;
    [self closeSockets];
    if (wasUSB) reason = @"Cabo desconectado";
    if (_wanted && _qHost.length) {
        [self publishState:PDStateConnecting macName:nil error:reason];
        NSUInteger gen = ++_generation;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), _q, ^{
            if (self->_wanted && self->_generation == gen && self->_tcp < 0) [self open];
        });
    } else {
        [self publishState:PDStateIdle macName:nil error:reason];
    }
}

- (void)readAvailable:(int)fd {
    if (fd != _tcp) return;
    uint8_t tmp[4096];
    ssize_t n = recv(fd, tmp, sizeof tmp, 0);
    if (n <= 0) {
        if (n < 0 && (errno == EAGAIN || errno == EINTR)) return;
        [self failed:@"O Mac encerrou a conexão"];
        return;
    }
    _lastRx = CFAbsoluteTimeGetCurrent();
    [_buffer appendBytes:tmp length:(NSUInteger)n];
    [self parse];
}

- (void)parse {
    while (_buffer.length >= 3) {
        const uint8_t *b = _buffer.bytes;
        NSUInteger len = ((NSUInteger)b[1] << 8) | b[2];
        if (_buffer.length < 3 + len) return;
        uint8_t type = b[0];
        NSData *payload = [_buffer subdataWithRange:NSMakeRange(3, len)];
        [_buffer replaceBytesInRange:NSMakeRange(0, 3 + len) withBytes:NULL length:0];
        if (type == kSealed) {
            NSMutableData *plain = [NSMutableData dataWithLength:len > PD_TAG_SIZE ? len - PD_TAG_SIZE : 0];
            uint8_t head[3] = { kSealed, (uint8_t)(len >> 8), (uint8_t)(len & 0xff) };
            if (!_secure || len <= PD_TAG_SIZE ||
                pd_open(&_session, head, 3, payload.bytes, len, plain.mutableBytes) != 0) {
                [self failed:@"Não foi possível verificar o Mac"];
                return;
            }
            const uint8_t *pb = plain.bytes;
            [self handleSealed:pb[0] payload:[plain subdataWithRange:NSMakeRange(1, plain.length - 1)]];
        } else {
            [self handle:type payload:payload];
        }
        if (_tcp < 0) return;
    }
}

/// Frames in the clear: the handshake, DENIED, and everything on the cable.
- (void)handle:(uint8_t)type payload:(NSData *)p {
    const uint8_t *b = p.bytes;
    switch (type) {
        case kWelcome:
            if (!_usb || p.length < 4) return;
            [self welcome:[p subdataWithRange:NSMakeRange(4, p.length - 4)]];
            break;
        case kServerHello: {
            if (_usb || _haveMacKey) return;
            if (p.length != 33 || b[0] != kVersion) { [self deny:kDeniedVersion]; return; }
            memcpy(_macKey, b + 1, 32);
            _haveMacKey = YES;
            NSString *hex = Hex(_macKey, 32);
            if ([[NSUserDefaults standardUserDefaults] dictionaryForKey:PDPrefPairedMacs][hex]) {
                uint8_t msg[64];
                memcpy(msg, gPublicKey, 32);
                pd_resume_client_start(&_resumeState, msg + 32);
                _resuming = YES;
                [self sendFrame:kResume payload:[NSData dataWithBytes:msg length:64]];
            } else {
                const char *pin = _qPin.UTF8String ?: "";
                uint8_t msg[PD_PAIR_MSG];
                if (pd_pair_client_start(&_pairState, _macKey, pin, strlen(pin), msg) != 0) {
                    [self deny:kDeniedNotPaired];   // not paired yet: ask for the PIN
                    return;
                }
                _pairing = YES;
                [self sendFrame:kPair payload:[NSData dataWithBytes:msg length:sizeof msg]];
            }
            break;
        }
        case kPairReply:
            if (!_pairing) return;
            _pairing = NO;
            if (p.length != 32 || pd_pair_client_finish(&_session, &_pairState, b) != 0) {
                [self failed:@"Não foi possível verificar o Mac"];
                return;
            }
            [self startEncryption];
            break;
        case kResumeReply:
            if (!_resuming) return;
            _resuming = NO;
            if (p.length != 32 ||
                pd_resume_client_finish(&_session, &_resumeState, gSecretKey, gPublicKey, _macKey, b) != 0) {
                [self failed:@"Não foi possível verificar o Mac"];
                return;
            }
            [self startEncryption];
            break;
        case kDenied:
            [self deny:p.length ? b[0] : kDeniedPIN];
            break;
        default: break;  // PONG: _lastRx already updated
    }
}

/// Keys agreed: READY proves who we are (and, when pairing, that the PIN was right).
- (void)startEncryption {
    _secure = YES;
    NSMutableData *p = [NSMutableData dataWithBytes:gPublicKey length:32];
    [p appendData:[[[UIDevice currentDevice] name] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]];
    [self sendFrame:kReady payload:p];
}

/// Encrypted records from the Mac.
- (void)handleSealed:(uint8_t)type payload:(NSData *)p {
    if (type == kWelcome && !_authed && p.length >= 4) {
        const uint8_t *b = p.bytes;
        _sessionID = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3];
        [self welcome:[p subdataWithRange:NSMakeRange(4, p.length - 4)]];
    }
    // PONG: nothing to do
}

- (void)welcome:(NSData *)nameData {
    _authed = YES;
    NSString *name = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
    if (!name.length) name = _qName.length ? _qName : _qHost;
    if (!_usb && _haveMacKey) {
        NSString *host = _qHost, *bonjour = _qName, *key = Hex(_macKey, 32);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            [d setObject:host forKey:PDPrefLastHost];
            [d setObject:name forKey:PDPrefLastName];
            NSMutableDictionary *macs = [[d dictionaryForKey:PDPrefPairedMacs] mutableCopy] ?: [NSMutableDictionary dictionary];
            macs[key] = name;
            [d setObject:macs forKey:PDPrefPairedMacs];
            NSMutableDictionary *targets = [[d dictionaryForKey:PDPrefPairedTargets] mutableCopy] ?: [NSMutableDictionary dictionary];
            if (host.length) targets[host] = key;
            if (bonjour.length) targets[bonjour] = key;
            targets[name] = key;
            [d setObject:targets forKey:PDPrefPairedTargets];
        });
    }
    _qPin = @"";   // paired now (or on the cable): the PIN isn't needed again
    [self publishState:PDStateConnected macName:name error:nil];
}

- (void)deny:(int)reason {
    _wanted = NO;
    _generation++;
    NSString *forget = (reason == kDeniedNotPaired && _haveMacKey) ? Hex(_macKey, 32) : nil;
    [self closeSockets];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.lastDenyReason = reason;
        if (forget) {   // the Mac forgot this iPad
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            NSMutableDictionary *macs = [[d dictionaryForKey:PDPrefPairedMacs] mutableCopy];
            [macs removeObjectForKey:forget];
            if (macs) [d setObject:macs forKey:PDPrefPairedMacs];
            NSMutableDictionary *targets = [[d dictionaryForKey:PDPrefPairedTargets] mutableCopy];
            [targets removeObjectsForKeys:[targets allKeysForObject:forget]];
            if (targets) [d setObject:targets forKey:PDPrefPairedTargets];
        }
    });
    NSString *msg = reason == kDeniedLocked ? @"Muitas tentativas. Aguarde 1 minuto."
                  : reason == kDeniedVersion ? @"Atualize o PadDeck no Mac para a versão 1.3 ou mais recente."
                  : reason == kDeniedNotPaired ? nil   // the connect screen asks for the PIN
                  : @"PIN incorreto.";
    [self publishState:PDStateIdle macName:nil error:msg];
}

/// Sends a frame, encrypted once the session has keys.
- (void)sendFrame:(uint8_t)type payload:(NSData *)payload {
    if (_tcp < 0) return;
    NSMutableData *f;
    if (_secure) {
        NSUInteger len = MIN(payload.length, 65535 - PD_TAG_SIZE - 1);   // inner: type + payload
        NSMutableData *inner = [NSMutableData dataWithBytes:&type length:1];
        if (len) [inner appendBytes:payload.bytes length:len];
        NSUInteger total = inner.length + PD_TAG_SIZE;
        uint8_t head[3] = { kSealed, (uint8_t)(total >> 8), (uint8_t)(total & 0xff) };
        f = [NSMutableData dataWithLength:3 + total];
        memcpy(f.mutableBytes, head, 3);
        pd_seal(&_session, head, 3, inner.bytes, inner.length, (uint8_t *)f.mutableBytes + 3);
    } else {
        NSUInteger len = MIN(payload.length, 65535);
        f = [NSMutableData dataWithCapacity:3 + len];
        uint8_t head[3] = { type, (uint8_t)(len >> 8), (uint8_t)(len & 0xff) };
        [f appendBytes:head length:3];
        if (len) [f appendBytes:payload.bytes length:len];
    }
    const uint8_t *p = f.bytes;
    size_t left = f.length;
    while (left > 0) {
        ssize_t n = send(_tcp, p, left, 0);
        if (n <= 0) {
            if (n < 0 && errno == EINTR) continue;
            [self failed:@"Conexão perdida"];
            return;
        }
        p += n;
        left -= (size_t)n;
    }
}

/// Sends a command only when authenticated.
- (void)command:(uint8_t)type payload:(NSData *)payload {
    dispatch_async(_q, ^{
        if (!self->_authed) return;
        [self sendFrame:type payload:payload];
    });
}

/// Movement/scroll: UDP when available, TCP otherwise.
- (void)fast:(uint8_t)type a:(int)a b:(int)b {
    uint16_t x = (uint16_t)(int16_t)MAX(-32768, MIN(32767, a));
    uint16_t y = (uint16_t)(int16_t)MAX(-32768, MIN(32767, b));
    dispatch_async(_q, ^{
        if (!self->_authed) return;
        uint8_t pl[4] = { (uint8_t)(x >> 8), (uint8_t)(x & 0xff), (uint8_t)(y >> 8), (uint8_t)(y & 0xff) };
        if (self->_udp >= 0 && self->_secure) {
            uint8_t inner[5] = { type, pl[0], pl[1], pl[2], pl[3] };
            uint8_t dg[PD_UDP_HEAD + sizeof inner + PD_TAG_SIZE];
            size_t n = pd_udp_seal(&self->_session, self->_sessionID, inner, sizeof inner, dg);
            if (send(self->_udp, dg, n, 0) == (ssize_t)n) return;
        }
        [self sendFrame:type payload:[NSData dataWithBytes:pl length:4]];
    });
}

#pragma mark - Input API

- (void)sendButton:(int)button action:(int)action {
    uint8_t p[2] = { (uint8_t)button, (uint8_t)action };
    [self command:kButton payload:[NSData dataWithBytes:p length:2]];
}

- (void)sendMoveDX:(int)dx dy:(int)dy {
    if (dx == 0 && dy == 0) return;
    [self fast:kMove a:dx b:dy];
}

- (void)sendScrollDY:(int)dy dx:(int)dx {
    if (dx == 0 && dy == 0) return;
    [self fast:kScroll a:dy b:dx];
}

- (void)sendText:(NSString *)text {
    if (!text.length) return;
    [self command:kText payload:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)sendKey:(int)code mods:(uint8_t)mods action:(int)action {
    uint8_t p[4] = { (uint8_t)(code >> 8), (uint8_t)(code & 0xff), mods, (uint8_t)action };
    [self command:kKey payload:[NSData dataWithBytes:p length:4]];
}

- (void)sendMedia:(int)key {
    uint8_t p = (uint8_t)key;
    [self command:kMedia payload:[NSData dataWithBytes:&p length:1]];
}

- (void)sendOpen:(NSString *)target {
    if (!target.length) return;
    [self command:kOpen payload:[target dataUsingEncoding:NSUTF8StringEncoding]];
}

@end

// PadDeck transport security (protocol v2). See pdcrypto.h and docs/PROTOCOL.md.

#include "pdcrypto.h"
#include "monocypher.h"
#include <string.h>

#if defined(__APPLE__)
#include <stdlib.h>   // arc4random_buf: kernel CSPRNG on macOS and iOS (8+)
#elif defined(__linux__)
#include <sys/random.h>
#include <sys/types.h>
#endif

static const char LABEL_GEN[]    = "PadDeck v2 CPace generator";
static const char LABEL_PAIR[]   = "PadDeck v2 pair";
static const char LABEL_RESUME[] = "PadDeck v2 resume";

void pd_random(uint8_t *buf, size_t len) {
#if defined(__APPLE__)
    arc4random_buf(buf, len);
#elif defined(__linux__)
    while (len > 0) {
        ssize_t n = getrandom(buf, len, 0);
        if (n > 0) { buf += n; len -= (size_t)n; }
    }
#else
#error "pd_random: no CSPRNG for this platform"
#endif
}

void pd_public_key(uint8_t pk[32], const uint8_t sk[32]) {
    crypto_x25519_public_key(pk, sk);
}

void pd_keypair(uint8_t sk[32], uint8_t pk[32]) {
    pd_random(sk, 32);
    crypto_x25519_public_key(pk, sk);
}

/// Constant time: 1 if all 32 bytes are zero (X25519 result of a low-order point).
static int is_zero32(const uint8_t a[32]) {
    static const uint8_t zero[32] = {0};
    return crypto_verify32(a, zero) == 0;
}

static void update_str(crypto_blake2b_ctx *ctx, const char *s) {
    crypto_blake2b_update(ctx, (const uint8_t *)s, strlen(s) + 1);   // with the NUL as separator
}

/// Splits the handshake hash into the directional keys.
static void derive(pd_session *s, const uint8_t h[64], int is_mac) {
    uint8_t c2s[32], s2c[32];
    crypto_blake2b_keyed(c2s, 32, h, 64, (const uint8_t *)"tcp client->mac", 15);
    crypto_blake2b_keyed(s2c, 32, h, 64, (const uint8_t *)"tcp mac->client", 15);
    memset(s, 0, sizeof *s);
    memcpy(s->tx_key, is_mac ? s2c : c2s, 32);
    memcpy(s->rx_key, is_mac ? c2s : s2c, 32);
    crypto_blake2b_keyed(s->udp_key, 32, h, 64, (const uint8_t *)"udp client->mac", 15);
    crypto_wipe(c2s, 32);
    crypto_wipe(s2c, 32);
}

// MARK: - Pairing (CPace)

static int generator(uint8_t g[32], const char *pin, size_t pin_len,
                     const uint8_t nonce[16], const uint8_t mac_pk[32]) {
    if (pin_len == 0 || pin_len > PD_PIN_MAX) return -1;
    uint8_t h[32], len = (uint8_t)pin_len;
    crypto_blake2b_ctx ctx;
    crypto_blake2b_init(&ctx, 32);
    update_str(&ctx, LABEL_GEN);
    crypto_blake2b_update(&ctx, &len, 1);
    crypto_blake2b_update(&ctx, (const uint8_t *)pin, pin_len);
    crypto_blake2b_update(&ctx, nonce, 16);
    crypto_blake2b_update(&ctx, mac_pk, 32);
    crypto_blake2b_final(&ctx, h);
    crypto_elligator_map(g, h);
    crypto_wipe(h, 32);
    return 0;
}

static void pair_hash(uint8_t h[64], const uint8_t mac_pk[32], const uint8_t client_msg[PD_PAIR_MSG],
                      const uint8_t mac_y[32], const uint8_t k[32]) {
    crypto_blake2b_ctx ctx;
    crypto_blake2b_init(&ctx, 64);
    update_str(&ctx, LABEL_PAIR);
    crypto_blake2b_update(&ctx, mac_pk, 32);
    crypto_blake2b_update(&ctx, client_msg, PD_PAIR_MSG);
    crypto_blake2b_update(&ctx, mac_y, 32);
    crypto_blake2b_update(&ctx, k, 32);
    crypto_blake2b_final(&ctx, h);
}

int pd_pair_client_start(pd_pair_state *st, const uint8_t mac_pk[32],
                         const char *pin, size_t pin_len, uint8_t out[PD_PAIR_MSG]) {
    uint8_t g[32];
    memset(st, 0, sizeof *st);
    pd_random(st->msg, 16);
    if (generator(g, pin, pin_len, st->msg, mac_pk) != 0) return -1;
    pd_random(st->y, 32);
    crypto_x25519(st->msg + 16, st->y, g);
    crypto_wipe(g, 32);
    if (is_zero32(st->msg + 16)) return -1;
    memcpy(st->mac_pk, mac_pk, 32);
    memcpy(out, st->msg, PD_PAIR_MSG);
    return 0;
}

int pd_pair_server(pd_session *s, const uint8_t mac_pk[32], const char *pin, size_t pin_len,
                   const uint8_t in[PD_PAIR_MSG], uint8_t out[32]) {
    uint8_t g[32], y[32], k[32], h[64];
    int rc = -1;
    if (generator(g, pin, pin_len, in, mac_pk) != 0) return -1;
    pd_random(y, 32);
    crypto_x25519(out, y, g);
    crypto_x25519(k, y, in + 16);
    if (!is_zero32(out) && !is_zero32(k)) {
        pair_hash(h, mac_pk, in, out, k);
        derive(s, h, 1);
        rc = 0;
    }
    crypto_wipe(g, 32);
    crypto_wipe(y, 32);
    crypto_wipe(k, 32);
    crypto_wipe(h, 64);
    return rc;
}

int pd_pair_client_finish(pd_session *s, pd_pair_state *st, const uint8_t in[32]) {
    uint8_t k[32], h[64];
    int rc = -1;
    crypto_x25519(k, st->y, in);
    if (!is_zero32(k)) {
        pair_hash(h, st->mac_pk, st->msg, in, k);
        derive(s, h, 0);
        rc = 0;
    }
    crypto_wipe(k, 32);
    crypto_wipe(h, 64);
    crypto_wipe(st, sizeof *st);
    return rc;
}

// MARK: - Resume (paired devices)

static void resume_hash(uint8_t h[64], const uint8_t mac_pk[32], const uint8_t dev_pk[32],
                        const uint8_t dev_E[32], const uint8_t mac_E[32],
                        const uint8_t dh1[32], const uint8_t dh2[32], const uint8_t dh3[32]) {
    crypto_blake2b_ctx ctx;
    crypto_blake2b_init(&ctx, 64);
    update_str(&ctx, LABEL_RESUME);
    crypto_blake2b_update(&ctx, mac_pk, 32);
    crypto_blake2b_update(&ctx, dev_pk, 32);
    crypto_blake2b_update(&ctx, dev_E, 32);
    crypto_blake2b_update(&ctx, mac_E, 32);
    crypto_blake2b_update(&ctx, dh1, 32);
    crypto_blake2b_update(&ctx, dh2, 32);
    crypto_blake2b_update(&ctx, dh3, 32);
    crypto_blake2b_final(&ctx, h);
}

void pd_resume_client_start(pd_resume_state *st, uint8_t out_E[32]) {
    pd_keypair(st->e, st->E);
    memcpy(out_E, st->E, 32);
}

int pd_resume_server(pd_session *s, const uint8_t mac_sk[32], const uint8_t mac_pk[32],
                     const uint8_t dev_pk[32], const uint8_t in_E[32], uint8_t out_E[32]) {
    uint8_t e[32], dh1[32], dh2[32], dh3[32], h[64];
    int rc = -1;
    pd_keypair(e, out_E);
    crypto_x25519(dh1, mac_sk, in_E);   // client ephemeral x Mac identity
    crypto_x25519(dh2, e, dev_pk);      // client identity  x Mac ephemeral
    crypto_x25519(dh3, e, in_E);        // ephemeral x ephemeral (forward secrecy)
    if (!is_zero32(dh1) && !is_zero32(dh2) && !is_zero32(dh3)) {
        resume_hash(h, mac_pk, dev_pk, in_E, out_E, dh1, dh2, dh3);
        derive(s, h, 1);
        rc = 0;
    }
    crypto_wipe(e, 32);
    crypto_wipe(dh1, 32);
    crypto_wipe(dh2, 32);
    crypto_wipe(dh3, 32);
    crypto_wipe(h, 64);
    return rc;
}

int pd_resume_client_finish(pd_session *s, pd_resume_state *st,
                            const uint8_t dev_sk[32], const uint8_t dev_pk[32],
                            const uint8_t mac_pk[32], const uint8_t in_E[32]) {
    uint8_t dh1[32], dh2[32], dh3[32], h[64];
    int rc = -1;
    crypto_x25519(dh1, st->e, mac_pk);
    crypto_x25519(dh2, dev_sk, in_E);
    crypto_x25519(dh3, st->e, in_E);
    if (!is_zero32(dh1) && !is_zero32(dh2) && !is_zero32(dh3)) {
        resume_hash(h, mac_pk, dev_pk, st->E, in_E, dh1, dh2, dh3);
        derive(s, h, 0);
        rc = 0;
    }
    crypto_wipe(dh1, 32);
    crypto_wipe(dh2, 32);
    crypto_wipe(dh3, 32);
    crypto_wipe(h, 64);
    crypto_wipe(st, sizeof *st);
    return rc;
}

// MARK: - Records

static void nonce_for(uint8_t nonce[24], uint64_t n) {
    memset(nonce, 0, 24);
    for (int i = 0; i < 8; i++) nonce[i] = (uint8_t)(n >> (8 * i));
}

void pd_seal(pd_session *s, const uint8_t *ad, size_t ad_len,
             const uint8_t *in, size_t len, uint8_t *out) {
    uint8_t nonce[24];
    nonce_for(nonce, s->tx_n++);
    crypto_aead_lock(out, out + len, s->tx_key, nonce, ad, ad_len, in, len);
}

int pd_open(pd_session *s, const uint8_t *ad, size_t ad_len,
            const uint8_t *in, size_t len, uint8_t *out) {
    if (len < PD_TAG_SIZE) return -1;
    uint8_t nonce[24];
    size_t n = len - PD_TAG_SIZE;
    nonce_for(nonce, s->rx_n);
    if (crypto_aead_unlock(out, in + n, s->rx_key, nonce, ad, ad_len, in, n) != 0) return -1;
    s->rx_n++;
    return 0;
}

static void put_be32(uint8_t *p, uint32_t v) {
    for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (24 - 8 * i));
}

static void put_be64(uint8_t *p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (56 - 8 * i));
}

static uint64_t get_be64(const uint8_t *p) {
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v = v << 8 | p[i];
    return v;
}

size_t pd_udp_seal(pd_session *s, uint32_t session_id, const uint8_t *in, size_t len, uint8_t *out) {
    uint8_t nonce[24];
    uint64_t n = ++s->udp_tx;   // starts at 1: 0 is never valid
    put_be32(out, session_id);
    put_be64(out + 4, n);
    nonce_for(nonce, n);
    crypto_aead_lock(out + PD_UDP_HEAD, out + PD_UDP_HEAD + len, s->udp_key, nonce,
                     out, PD_UDP_HEAD, in, len);
    return PD_UDP_HEAD + len + PD_TAG_SIZE;
}

uint32_t pd_udp_session_id(const uint8_t *in, size_t len) {
    if (len < PD_UDP_HEAD + PD_TAG_SIZE) return 0;
    return (uint32_t)in[0] << 24 | (uint32_t)in[1] << 16 | (uint32_t)in[2] << 8 | in[3];
}

long pd_udp_open(pd_session *s, const uint8_t *in, size_t len, uint8_t *out) {
    if (len < PD_UDP_HEAD + PD_TAG_SIZE) return -1;
    uint64_t n = get_be64(in + 4);
    if (n == 0) return -1;
    // Replay window: reject anything already seen or more than 64 behind the newest.
    if (n <= s->udp_top) {
        uint64_t back = s->udp_top - n;   // 0 = the newest itself
        if (back == 0 || back > 64) return -1;
        if (s->udp_bits & ((uint64_t)1 << (back - 1))) return -1;
    }
    uint8_t nonce[24];
    size_t m = len - PD_UDP_HEAD - PD_TAG_SIZE;
    nonce_for(nonce, n);
    if (crypto_aead_unlock(out, in + PD_UDP_HEAD + m, s->udp_key, nonce,
                           in, PD_UDP_HEAD, in + PD_UDP_HEAD, m) != 0) return -1;
    // Only authentic datagrams move the window.
    if (n > s->udp_top) {
        uint64_t shift = n - s->udp_top;
        // the old newest becomes bit (shift - 1)
        s->udp_bits = shift >= 64 ? (shift == 64 ? (uint64_t)1 << 63 : 0)
                                  : (s->udp_bits << shift) | ((uint64_t)1 << (shift - 1));
        if (s->udp_top == 0) s->udp_bits = 0;   // nothing seen before the first one
        s->udp_top = n;
    } else {
        s->udp_bits |= (uint64_t)1 << (s->udp_top - n - 1);
    }
    return (long)m;
}

void pd_session_wipe(pd_session *s) {
    crypto_wipe(s, sizeof *s);
}

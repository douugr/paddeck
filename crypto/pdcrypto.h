// PadDeck transport security (protocol v2), shared by the Mac agent, the App Store app and
// the iOS 8 iPad app. Built on Monocypher (X25519, Elligator 2, BLAKE2b, XChaCha20-Poly1305).
// See docs/PROTOCOL.md for the wire format. Keep this file identical in every app.

#ifndef PDCRYPTO_H
#define PDCRYPTO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PD_KEY_SIZE   32
#define PD_TAG_SIZE   16
#define PD_PAIR_MSG   48   // client pairing message: nonce[16] || Y[32]
#define PD_UDP_HEAD   12   // u32 session id || u64 counter (big-endian)
#define PD_PIN_MAX    64

/// Keys and counters of one encrypted session (one per TCP connection).
typedef struct {
    uint8_t  tx_key[32];
    uint64_t tx_n;        // next TCP record number to send
    uint8_t  rx_key[32];
    uint64_t rx_n;        // next TCP record number expected
    uint8_t  udp_key[32]; // client -> Mac datagrams
    uint64_t udp_tx;      // client: last datagram counter sent
    uint64_t udp_top;     // Mac: highest datagram counter accepted
    uint64_t udp_bits;    // Mac: replay window below udp_top (bit i = udp_top - 1 - i seen)
} pd_session;

/// Fills buf with cryptographically secure random bytes.
void pd_random(uint8_t *buf, size_t len);

/// Long-term identity: random secret key and its X25519 public key.
void pd_keypair(uint8_t sk[32], uint8_t pk[32]);
void pd_public_key(uint8_t pk[32], const uint8_t sk[32]);

// MARK: Pairing (first connection, authenticated by the PIN)
//
// CPace over X25519: both sides derive a generator from the PIN, so a wrong PIN gives
// different keys and the first encrypted record fails to open. Someone who records the
// exchange learns nothing about the PIN; an active attacker gets one guess per attempt.

typedef struct {
    uint8_t y[32];
    uint8_t msg[PD_PAIR_MSG];
    uint8_t mac_pk[32];
} pd_pair_state;

/// Client: builds the PAIR message (out) for the Mac whose identity is mac_pk.
/// Returns 0, or -1 if the PIN is empty or too long.
int pd_pair_client_start(pd_pair_state *st, const uint8_t mac_pk[32],
                         const char *pin, size_t pin_len, uint8_t out[PD_PAIR_MSG]);

/// Mac: answers a PAIR message with its own share (out) and sets up the session.
/// Returns 0, or -1 if the message is invalid.
int pd_pair_server(pd_session *s, const uint8_t mac_pk[32], const char *pin, size_t pin_len,
                   const uint8_t in[PD_PAIR_MSG], uint8_t out[32]);

/// Client: finishes with the Mac's share. Returns 0, or -1 if it is invalid.
int pd_pair_client_finish(pd_session *s, pd_pair_state *st, const uint8_t in[32]);

// MARK: Resume (already paired devices, no PIN)
//
// Each side proves its long-term key with ephemeral X25519 (three Diffie-Hellman results,
// like Noise KK): only the real Mac can open the client's records and vice versa.

typedef struct {
    uint8_t e[32];
    uint8_t E[32];
} pd_resume_state;

/// Client: creates its ephemeral key; out_E goes in the RESUME message.
void pd_resume_client_start(pd_resume_state *st, uint8_t out_E[32]);

/// Mac: answers a RESUME from the paired device dev_pk. Returns 0, or -1 if invalid.
int pd_resume_server(pd_session *s, const uint8_t mac_sk[32], const uint8_t mac_pk[32],
                     const uint8_t dev_pk[32], const uint8_t in_E[32], uint8_t out_E[32]);

/// Client: finishes with the Mac's ephemeral key. Returns 0, or -1 if invalid.
int pd_resume_client_finish(pd_session *s, pd_resume_state *st,
                            const uint8_t dev_sk[32], const uint8_t dev_pk[32],
                            const uint8_t mac_pk[32], const uint8_t in_E[32]);

// MARK: Records

/// TCP: encrypts len bytes into out (len + 16 bytes: ciphertext || tag).
void pd_seal(pd_session *s, const uint8_t *ad, size_t ad_len,
             const uint8_t *in, size_t len, uint8_t *out);

/// TCP: decrypts len bytes (ciphertext || tag) into out (len - 16 bytes).
/// Returns 0, or -1 if the record is forged, reordered or truncated (close the connection).
int pd_open(pd_session *s, const uint8_t *ad, size_t ad_len,
            const uint8_t *in, size_t len, uint8_t *out);

/// UDP (client): builds a datagram in out (12 + len + 16 bytes) and returns its size.
size_t pd_udp_seal(pd_session *s, uint32_t session_id, const uint8_t *in, size_t len, uint8_t *out);

/// UDP: the session id of a datagram (to find its session), or 0 if it's too short.
uint32_t pd_udp_session_id(const uint8_t *in, size_t len);

/// UDP (Mac): decrypts a datagram into out (len - 28 bytes). Returns the plaintext size,
/// or -1 if it is forged, too old or a replay.
long pd_udp_open(pd_session *s, const uint8_t *in, size_t len, uint8_t *out);

/// Erases a session's keys.
void pd_session_wipe(pd_session *s);

#ifdef __cplusplus
}
#endif

#endif

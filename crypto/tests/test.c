// Tests for pdcrypto.c. Run: crypto/tests/run.sh
#include "pdcrypto.h"
#include "monocypher.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>

static int fails = 0;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); fails++; } } while (0)

static int roundtrip(pd_session *a, pd_session *b) {
    // a -> b and b -> a, three records each
    for (int i = 0; i < 3; i++) {
        uint8_t ad[3] = {0xE0, 0, 5}, msg[5] = {'h','e','l','l','o'}, ct[21], pt[5];
        pd_seal(a, ad, 3, msg, 5, ct);
        if (pd_open(b, ad, 3, ct, 21, pt) != 0 || memcmp(pt, msg, 5)) return -1;
        pd_seal(b, ad, 3, msg, 5, ct);
        if (pd_open(a, ad, 3, ct, 21, pt) != 0 || memcmp(pt, msg, 5)) return -1;
    }
    return 0;
}

static void test_pair(void) {
    uint8_t mac_sk[32], mac_pk[32];
    pd_keypair(mac_sk, mac_pk);
    // right PIN
    pd_pair_state st; pd_session c, m; uint8_t msg[48], ys[32];
    CHECK(pd_pair_client_start(&st, mac_pk, "4821", 4, msg) == 0);
    CHECK(pd_pair_server(&m, mac_pk, "4821", 4, msg, ys) == 0);
    CHECK(pd_pair_client_finish(&c, &st, ys) == 0);
    CHECK(roundtrip(&c, &m) == 0);
    // UDP
    uint8_t dg[64], out[64]; uint8_t mv[5] = {0x11, 0, 3, 0xff, 0xfe};
    size_t n = pd_udp_seal(&c, 0xA1B2C3D4, mv, 5, dg);
    CHECK(n == 12 + 5 + 16);
    CHECK(pd_udp_session_id(dg, n) == 0xA1B2C3D4);
    CHECK(pd_udp_open(&m, dg, n, out) == 5 && memcmp(out, mv, 5) == 0);
    CHECK(pd_udp_open(&m, dg, n, out) == -1);           // replay
    dg[20] ^= 1;
    CHECK(pd_udp_open(&m, dg, n, out) == -1);           // tamper

    // wrong PIN: keys differ, first record fails both ways
    CHECK(pd_pair_client_start(&st, mac_pk, "4822", 4, msg) == 0);
    CHECK(pd_pair_server(&m, mac_pk, "4821", 4, msg, ys) == 0);
    CHECK(pd_pair_client_finish(&c, &st, ys) == 0);
    CHECK(roundtrip(&c, &m) != 0);

    // different Mac identity in the transcript (MITM swapping the key in SERVER_HELLO)
    uint8_t other_sk[32], other_pk[32];
    pd_keypair(other_sk, other_pk);
    CHECK(pd_pair_client_start(&st, other_pk, "4821", 4, msg) == 0);
    CHECK(pd_pair_server(&m, mac_pk, "4821", 4, msg, ys) == 0);
    CHECK(pd_pair_client_finish(&c, &st, ys) == 0);
    CHECK(roundtrip(&c, &m) != 0);

    // empty / long PIN rejected
    CHECK(pd_pair_client_start(&st, mac_pk, "", 0, msg) == -1);
    char longpin[65]; memset(longpin, '1', 65);
    CHECK(pd_pair_client_start(&st, mac_pk, longpin, 65, msg) == -1);

    // low-order points rejected (all-zero shared secret)
    uint8_t zero[32] = {0}; uint8_t bad[48];
    CHECK(pd_pair_client_start(&st, mac_pk, "4821", 4, msg) == 0);
    CHECK(pd_pair_client_finish(&c, &st, zero) == -1);
    memcpy(bad, msg, 16); memset(bad + 16, 0, 32);
    CHECK(pd_pair_server(&m, mac_pk, "4821", 4, bad, ys) == -1);
    // u = 1 is also low order
    uint8_t one[32] = {1};
    memcpy(bad + 16, one, 32);
    CHECK(pd_pair_server(&m, mac_pk, "4821", 4, bad, ys) == -1);
}

static void test_resume(void) {
    uint8_t mac_sk[32], mac_pk[32], dev_sk[32], dev_pk[32], ev_sk[32], ev_pk[32];
    pd_keypair(mac_sk, mac_pk); pd_keypair(dev_sk, dev_pk); pd_keypair(ev_sk, ev_pk);
    pd_resume_state st; pd_session c, m; uint8_t ec[32], es[32];
    pd_resume_client_start(&st, ec);
    CHECK(pd_resume_server(&m, mac_sk, mac_pk, dev_pk, ec, es) == 0);
    CHECK(pd_resume_client_finish(&c, &st, dev_sk, dev_pk, mac_pk, es) == 0);
    CHECK(roundtrip(&c, &m) == 0);

    // impostor client (claims dev_pk without its secret)
    pd_resume_client_start(&st, ec);
    CHECK(pd_resume_server(&m, mac_sk, mac_pk, dev_pk, ec, es) == 0);
    CHECK(pd_resume_client_finish(&c, &st, ev_sk, dev_pk, mac_pk, es) == 0);
    CHECK(roundtrip(&c, &m) != 0);

    // impostor Mac (has the public key only)
    pd_resume_client_start(&st, ec);
    CHECK(pd_resume_server(&m, ev_sk, mac_pk, dev_pk, ec, es) == 0);
    CHECK(pd_resume_client_finish(&c, &st, dev_sk, dev_pk, mac_pk, es) == 0);
    CHECK(roundtrip(&c, &m) != 0);

    uint8_t zero[32] = {0};
    CHECK(pd_resume_server(&m, mac_sk, mac_pk, dev_pk, zero, es) == -1);
    pd_resume_client_start(&st, ec);
    CHECK(pd_resume_client_finish(&c, &st, dev_sk, dev_pk, mac_pk, zero) == -1);
}

static void test_records(void) {
    uint8_t mac_sk[32], mac_pk[32], dev_sk[32], dev_pk[32];
    pd_keypair(mac_sk, mac_pk); pd_keypair(dev_sk, dev_pk);
    pd_resume_state st; pd_session c, m; uint8_t ec[32], es[32];
    pd_resume_client_start(&st, ec);
    pd_resume_server(&m, mac_sk, mac_pk, dev_pk, ec, es);
    pd_resume_client_finish(&c, &st, dev_sk, dev_pk, mac_pk, es);

    uint8_t ad[3] = {0xE0, 0, 4}, a[4] = "abc", b[4] = "def", ca[20], cb[20], pt[4];
    pd_seal(&c, ad, 3, a, 4, ca);
    pd_seal(&c, ad, 3, b, 4, cb);
    CHECK(pd_open(&m, ad, 3, cb, 20, pt) == -1);          // out of order
    CHECK(pd_open(&m, ad, 3, ca, 20, pt) == 0);
    CHECK(pd_open(&m, ad, 3, ca, 20, pt) == -1);          // replay
    uint8_t ad2[3] = {0xE0, 0, 5};
    CHECK(pd_open(&m, ad2, 3, cb, 20, pt) == -1);         // header changed
    CHECK(pd_open(&m, ad, 3, cb, 15, pt) == -1);          // too short
    CHECK(pd_open(&m, ad, 3, cb, 20, pt) == 0);
    // reflected record (Mac's own key direction) must not open
    uint8_t cm[20];
    pd_seal(&m, ad, 3, a, 4, cm);
    pd_session m2 = m; m2.rx_n = m2.tx_n - 1;
    CHECK(pd_open(&m2, ad, 3, cm, 20, pt) == -1);

    // UDP window
    uint8_t dg[200][40]; size_t len[200]; uint8_t mv[4] = {1,2,3,4}, out[40];
    for (int i = 0; i < 200; i++) len[i] = pd_udp_seal(&c, 7, mv, 4, dg[i]);   // counters 1..200
    CHECK(pd_udp_open(&m, dg[9], len[9], out) == 4);      // 10
    CHECK(pd_udp_open(&m, dg[4], len[4], out) == 4);      // 5: late but in window
    CHECK(pd_udp_open(&m, dg[4], len[4], out) == -1);     // 5 again
    CHECK(pd_udp_open(&m, dg[9], len[9], out) == -1);     // 10 again
    CHECK(pd_udp_open(&m, dg[8], len[8], out) == 4);      // 9
    CHECK(pd_udp_open(&m, dg[99], len[99], out) == 4);    // 100
    CHECK(pd_udp_open(&m, dg[30], len[30], out) == -1);   // 31: 69 behind, too old
    CHECK(pd_udp_open(&m, dg[40], len[40], out) == 4);    // 41: 59 behind, ok
    CHECK(pd_udp_open(&m, dg[99], len[99], out) == -1);   // 100 again
    CHECK(pd_udp_open(&m, dg[35], len[35], out) == 4);    // 36: exactly 64 behind, ok
    CHECK(pd_udp_open(&m, dg[35], len[35], out) == -1);
    CHECK(pd_udp_open(&m, dg[163], len[163], out) == 4);  // 164: jump of 64
    CHECK(pd_udp_open(&m, dg[99], len[99], out) == -1);   // 100: 64 behind but seen
    CHECK(pd_udp_open(&m, dg[100], len[100], out) == 4);  // 101: 63 behind, unseen
    CHECK(pd_udp_open(&m, dg[199], len[199], out) == 4);
    // datagram from another session's key
    pd_session other = m; memset(other.udp_key, 9, 32);
    uint8_t x[40]; size_t xl = pd_udp_seal(&other, 7, mv, 4, x);
    pd_session m3 = m;
    CHECK(pd_udp_open(&m3, x, xl, out) == -1);
    // counter 0 and short packets
    uint8_t z[40] = {0}; CHECK(pd_udp_open(&m, z, 32, out) == -1);
    CHECK(pd_udp_open(&m, dg[0], 27, out) == -1);
    CHECK(pd_udp_session_id(dg[0], 27) == 0);
}

int main(void) {
    for (int i = 0; i < 50; i++) { test_pair(); test_resume(); test_records(); }
    printf(fails ? "%d FAILURES\n" : "all tests passed\n", fails);
    return fails != 0;
}

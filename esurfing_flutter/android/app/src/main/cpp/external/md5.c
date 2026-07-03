/**
 * md5.c — RFC 1321 MD5 implementation, standalone, no external deps.
 */
#include "md5.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct {
    uint32_t state[4];
    uint64_t count;
    unsigned char buffer[64];
} md5_ctx;

static const uint32_t INIT[4] = {
    0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476
};

#define LROT(x, n) (((x) << (n)) | ((x) >> (32 - (n))))
#define F(x, y, z) (((x) & (y)) | ((~x) & (z)))
#define G(x, y, z) (((x) & (z)) | ((y) & (~z)))
#define H(x, y, z) ((x) ^ (y) ^ (z))
#define I(x, y, z) ((y) ^ ((x) | (~z)))

#define FF(a, b, c, d, x, s, ac) do { \
    (a) += F((b), (c), (d)) + (x) + (uint32_t)(ac); \
    (a) = LROT((a), (s)); (a) += (b); } while (0)
#define GG(a, b, c, d, x, s, ac) do { \
    (a) += G((b), (c), (d)) + (x) + (uint32_t)(ac); \
    (a) = LROT((a), (s)); (a) += (b); } while (0)
#define HH(a, b, c, d, x, s, ac) do { \
    (a) += H((b), (c), (d)) + (x) + (uint32_t)(ac); \
    (a) = LROT((a), (s)); (a) += (b); } while (0)
#define II(a, b, c, d, x, s, ac) do { \
    (a) += I((b), (c), (d)) + (x) + (uint32_t)(ac); \
    (a) = LROT((a), (s)); (a) += (b); } while (0)

static uint32_t load32(const unsigned char* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static void store32(unsigned char* p, uint32_t v) {
    p[0] = (unsigned char)(v); p[1] = (unsigned char)(v >> 8);
    p[2] = (unsigned char)(v >> 16); p[3] = (unsigned char)(v >> 24);
}
static void store64(unsigned char* p, uint64_t v) {
    store32(p, (uint32_t)v); store32(p + 4, (uint32_t)(v >> 32));
}

static void md5_compress(md5_ctx* ctx, const unsigned char block[64]) {
    uint32_t a = ctx->state[0], b = ctx->state[1];
    uint32_t c = ctx->state[2], d = ctx->state[3], X[16];
    for (int i = 0; i < 16; i++) X[i] = load32(block + 4 * i);

    FF(a,b,c,d,X[ 0], 7,0xD76AA478); FF(d,a,b,c,X[ 1],12,0xE8C7B756);
    FF(c,d,a,b,X[ 2],17,0x242070DB); FF(b,c,d,a,X[ 3],22,0xC1BDCEEE);
    FF(a,b,c,d,X[ 4], 7,0xF57C0FAF); FF(d,a,b,c,X[ 5],12,0x4787C62A);
    FF(c,d,a,b,X[ 6],17,0xA8304613); FF(b,c,d,a,X[ 7],22,0xFD469501);
    FF(a,b,c,d,X[ 8], 7,0x698098D8); FF(d,a,b,c,X[ 9],12,0x8B44F7AF);
    FF(c,d,a,b,X[10],17,0xFFFF5BB1); FF(b,c,d,a,X[11],22,0x895CD7BE);
    FF(a,b,c,d,X[12], 7,0x6B901122); FF(d,a,b,c,X[13],12,0xFD987193);
    FF(c,d,a,b,X[14],17,0xA679438E); FF(b,c,d,a,X[15],22,0x49B40821);
    GG(a,b,c,d,X[ 1], 5,0xF61E2562); GG(d,a,b,c,X[ 6], 9,0xC040B340);
    GG(c,d,a,b,X[11],14,0x265E5A51); GG(b,c,d,a,X[ 0],20,0xE9B6C7AA);
    GG(a,b,c,d,X[ 5], 5,0xD62F105D); GG(d,a,b,c,X[10], 9,0x02441453);
    GG(c,d,a,b,X[15],14,0xD8A1E681); GG(b,c,d,a,X[ 4],20,0xE7D3FBC8);
    GG(a,b,c,d,X[ 9], 5,0x21E1CDE6); GG(d,a,b,c,X[14], 9,0xC33707D6);
    GG(c,d,a,b,X[ 3],14,0xF4D50D87); GG(b,c,d,a,X[ 8],20,0x455A14ED);
    GG(a,b,c,d,X[13], 5,0xA9E3E905); GG(d,a,b,c,X[ 2], 9,0xFCEFA3F8);
    GG(c,d,a,b,X[ 7],14,0x676F02D9); GG(b,c,d,a,X[12],20,0x8D2A4C8A);
    HH(a,b,c,d,X[ 5], 4,0xFFFA3942); HH(d,a,b,c,X[ 8],11,0x8771F681);
    HH(c,d,a,b,X[11],16,0x6D9D6122); HH(b,c,d,a,X[14],23,0xFDE5380C);
    HH(a,b,c,d,X[ 1], 4,0xA4BEEA44); HH(d,a,b,c,X[ 4],11,0x4BDECFA9);
    HH(c,d,a,b,X[ 7],16,0xF6BB4B60); HH(b,c,d,a,X[10],23,0xBEBFBC70);
    HH(a,b,c,d,X[13], 4,0x289B7EC6); HH(d,a,b,c,X[ 0],11,0xEAA127FA);
    HH(c,d,a,b,X[ 3],16,0xD4EF3085); HH(b,c,d,a,X[ 6],23,0x04881D05);
    HH(a,b,c,d,X[ 9], 4,0xD9D4D039); HH(d,a,b,c,X[12],11,0xE6DB99E5);
    HH(c,d,a,b,X[15],16,0x1FA27CF8); HH(b,c,d,a,X[ 2],23,0xC4AC5665);
    II(a,b,c,d,X[ 0], 6,0xF4292244); II(d,a,b,c,X[ 7],10,0x432AFF97);
    II(c,d,a,b,X[14],15,0xAB9423A7); II(b,c,d,a,X[ 5],21,0xFC93A039);
    II(a,b,c,d,X[12], 6,0x655B59C3); II(d,a,b,c,X[ 3],10,0x8F0CCC92);
    II(c,d,a,b,X[10],15,0xFFEFF47D); II(b,c,d,a,X[ 1],21,0x85845DD1);
    II(a,b,c,d,X[ 8], 6,0x6FA87E4F); II(d,a,b,c,X[15],10,0xFE2CE6E0);
    II(c,d,a,b,X[ 6],15,0xA3014314); II(b,c,d,a,X[13],21,0x4E0811A1);
    II(a,b,c,d,X[ 4], 6,0xF7537E82); II(d,a,b,c,X[11],10,0xBD3AF235);
    II(c,d,a,b,X[ 2],15,0x2AD7D2BB); II(b,c,d,a,X[ 9],21,0xEB86D391);

    ctx->state[0] += a; ctx->state[1] += b;
    ctx->state[2] += c; ctx->state[3] += d;
}

static void md5_init(md5_ctx* ctx) {
    memcpy(ctx->state, INIT, sizeof(INIT));
    ctx->count = 0; memset(ctx->buffer, 0, sizeof(ctx->buffer));
}

static void md5_update(md5_ctx* ctx, const unsigned char* data, size_t len) {
    size_t idx = (size_t)(ctx->count >> 3) & 0x3F;
    ctx->count += (uint64_t)len << 3;
    if (idx) {
        size_t fill = 64 - idx;
        if (len < fill) { memcpy(ctx->buffer + idx, data, len); return; }
        memcpy(ctx->buffer + idx, data, fill);
        md5_compress(ctx, ctx->buffer);
        data += fill; len -= fill;
    }
    while (len >= 64) { md5_compress(ctx, data); data += 64; len -= 64; }
    if (len) memcpy(ctx->buffer, data, len);
}

static void md5_final(md5_ctx* ctx, unsigned char digest[16]) {
    size_t idx = (size_t)(ctx->count >> 3) & 0x3F;
    ctx->buffer[idx++] = 0x80;
    if (idx > 56) { memset(ctx->buffer + idx, 0, 64 - idx);
        md5_compress(ctx, ctx->buffer); idx = 0; }
    memset(ctx->buffer + idx, 0, 56 - idx);
    store64(ctx->buffer + 56, ctx->count);
    md5_compress(ctx, ctx->buffer);
    for (int i = 0; i < 4; i++) store32(digest + 4 * i, ctx->state[i]);
}

char* md5_hex(const unsigned char* data, size_t len, char* out) {
    md5_ctx ctx; unsigned char dg[16];
    char* r = out ? out : (char*)malloc(33);
    if (!r) return NULL;
    md5_init(&ctx); md5_update(&ctx, data, len); md5_final(&ctx, dg);
    for (int i = 0; i < 16; i++) sprintf(r + i * 2, "%02x", (unsigned)dg[i]);
    r[32] = '\0'; return r;
}

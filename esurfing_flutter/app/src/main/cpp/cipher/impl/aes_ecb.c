#include "cipher/CipherInterface.h"
#include "cipher/CipherUtils.h"
#include "external/aes128_core.h"
#include <string.h>
typedef struct { uint8_t k1[16], k2[16]; } ctx_t;
static uint8_t* ee(const uint8_t* d, size_t n, const uint8_t* k, size_t* o) {
    size_t pl; uint8_t* p = pad_2_multiple(d, n, 16, &pl); if (!p) return NULL;
    uint8_t* r = s_malloc(pl); if (!r) { s_free(p); return NULL; }
    uint8_t rk[176]; aes128_key_expand(k, rk);
    for (size_t i = 0; i < pl; i += 16) aes128_enc_block(p + i, r + i, rk);
    s_free(p); *o = pl; return r;
}
static uint8_t* dd(const uint8_t* d, size_t n, const uint8_t* k, size_t* o) {
    if (n % 16) return NULL; uint8_t* r = s_malloc(n); if (!r) return NULL;
    uint8_t rk[176]; aes128_key_expand(k, rk);
    for (size_t i = 0; i < n; i += 16) aes128_dec_block(d + i, r + i, rk);
    *o = n; return r;
}
static char* enc(cipher_interface_t* s, const char* t) {
    if(!s||!t)return NULL; ctx_t*d=s->private_data; if(!d)return NULL;
    size_t l=strlen(t),l1; uint8_t*r1=ee((const uint8_t*)t,l,d->k1,&l1); if(!r1)return NULL;
    size_t l2; uint8_t*r2=ee(r1,l1,d->k2,&l2); s_free(r1); if(!r2)return NULL;
    char*h=bytes_2_hex(r2,l2); s_free(r2); return h;
}
static char* dec(cipher_interface_t* s, const char* h) {
    if(!s||!h)return NULL; ctx_t*d=s->private_data; if(!d)return NULL;
    size_t bl; uint8_t*b=hex_2_bytes(h,&bl); if(!b)return NULL;
    size_t l1; uint8_t*r1=dd(b,bl,d->k2,&l1); s_free(b); if(!r1)return NULL;
    size_t l2; uint8_t*r2=dd(r1,l1,d->k1,&l2); s_free(r1); if(!r2)return NULL;
    while(l2>0&&r2[l2-1]==0)l2--;char*x=s_malloc(l2+1);memcpy(x,r2,l2);x[l2]=0;s_free(r2);return x;
}
static void dtr(cipher_interface_t*s){if(s){s_free(s->private_data);s_free(s);}}
cipher_interface_t* create_aes_ecb_cipher(const uint8_t*k1,const uint8_t*k2){
    if(!k1||!k2)return NULL;cipher_interface_t*c=s_malloc(sizeof(*c));ctx_t*d=s_malloc(sizeof(*d));
    memcpy(d->k1,k1,16);memcpy(d->k2,k2,16);c->encrypt=enc;c->decrypt=dec;c->destroy=dtr;c->private_data=d;return c;
}

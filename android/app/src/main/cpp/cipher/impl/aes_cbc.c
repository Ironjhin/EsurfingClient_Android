#include "cipher/CipherInterface.h"
#include "cipher/CipherUtils.h"
#include "external/aes128_core.h"
#include <string.h>
typedef struct { uint8_t k1[16], k2[16], iv[16]; } ctx_t;
static uint8_t* ec(const uint8_t* d, size_t n, const uint8_t* k, const uint8_t* iv, size_t* o) {
    size_t pl; uint8_t* p = pad_2_multiple(d, n, 16, &pl); if (!p) return NULL;
    uint8_t* r = s_malloc(16 + pl); if (!r) { s_free(p); return NULL; }
    memcpy(r, iv, 16); aes128_cbc_enc(p, r + 16, pl, k, iv); s_free(p); *o = 16 + pl; return r;
}
static uint8_t* dc(const uint8_t* d, size_t n, const uint8_t* k, size_t* o) {
    if (n < 16) return NULL; size_t ct = n - 16; uint8_t* r = s_malloc(ct);
    if (!r) return NULL; aes128_cbc_dec(d + 16, r, ct, k, d); *o = ct; return r;
}
static char* enc(cipher_interface_t* s, const char* t) {
    if (!s||!t) return NULL; ctx_t* d = s->private_data; if (!d) return NULL;
    size_t l = strlen(t), l1; uint8_t* r1 = ec((const uint8_t*)t,l,d->k1,d->iv,&l1);
    if(!r1)return NULL; size_t l2; uint8_t* r2 = ec(r1+16,l1-16,d->k2,r1,&l2);
    s_free(r1); if(!r2)return NULL; char* h = bytes_2_hex(r2,l2); s_free(r2); return h;
}
static char* dec(cipher_interface_t* s, const char* h) {
    if(!s||!h)return NULL; ctx_t* d=s->private_data; if(!d)return NULL;
    size_t bl; uint8_t* b=hex_2_bytes(h,&bl); if(!b||bl<32){s_free(b);return NULL;}
    size_t l1; uint8_t* r1=dc(b,bl,d->k2,&l1); s_free(b);
    if(!r1||l1<16){s_free(r1);return NULL;} size_t l2; uint8_t* r2=dc(r1,l1,d->k1,&l2);
    s_free(r1); if(!r2)return NULL; while(l2>0&&r2[l2-1]==0)l2--;
    char* x=s_malloc(l2+1); memcpy(x,r2,l2); x[l2]=0; s_free(r2); return x;
}
static void dtr(cipher_interface_t* s){if(s){s_free(s->private_data);s_free(s);}}
cipher_interface_t* create_aes_cbc_cipher(const uint8_t*k1,const uint8_t*k2,const uint8_t*iv){
    if(!k1||!k2||!iv)return NULL; cipher_interface_t*c=s_malloc(sizeof(*c));ctx_t*d=s_malloc(sizeof(*d));
    memcpy(d->k1,k1,16);memcpy(d->k2,k2,16);memcpy(d->iv,iv,16);
    c->encrypt=enc;c->decrypt=dec;c->destroy=dtr;c->private_data=d;return c;
}

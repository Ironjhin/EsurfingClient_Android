#include "cipher/CipherInterface.h"
#include "cipher/CipherUtils.h"
#include "external/des_core.h"
#include <string.h>
typedef struct { uint8_t k1[24], k2[24], iv1[8], iv2[8]; } ctx_t;
static uint8_t* d3cbc(const uint8_t* d, size_t n, const uint8_t k[24], const uint8_t iv[8], size_t* o, int enc) {
    size_t pl; uint8_t* p = pad_2_multiple(d, n, 8, &pl); if (!p) return NULL;
    uint8_t* r = s_malloc(pl); if(!r){s_free(p);return NULL;}
    uint8_t pr[8]; memcpy(pr,iv,8);
    for(size_t i=0;i<pl;i+=8){
        if(enc){uint8_t b[8];for(int j=0;j<8;j++)b[j]=p[i+j]^pr[j];des3_ede_enc(b,r+i,k);memcpy(pr,r+i,8);}
        else{uint8_t b[8];des3_ede_dec(d+i,b,k);for(int j=0;j<8;j++)r[i+j]=b[j]^pr[j];memcpy(pr,d+i,8);}
    }
    s_free(p);*o=pl;return r;
}
static char* enc(cipher_interface_t*s,const char*t){
    if(!s||!t)return NULL;ctx_t*d=s->private_data;if(!d)return NULL;
    size_t l=strlen(t),l1;uint8_t*r1=d3cbc((const uint8_t*)t,l,d->k1,d->iv1,&l1,1);if(!r1)return NULL;
    size_t l2;uint8_t*r2=d3cbc(r1,l1,d->k2,d->iv2,&l2,1);s_free(r1);if(!r2)return NULL;
    char*h=bytes_2_hex(r2,l2);s_free(r2);return h;
}
static char* dec(cipher_interface_t*s,const char*h){
    if(!s||!h)return NULL;ctx_t*d=s->private_data;if(!d)return NULL;
    size_t bl;uint8_t*b=hex_2_bytes(h,&bl);if(!b)return NULL;
    size_t l1;uint8_t*r1=d3cbc(b,bl,d->k2,d->iv2,&l1,0);s_free(b);if(!r1)return NULL;
    size_t l2;uint8_t*r2=d3cbc(r1,l1,d->k1,d->iv1,&l2,0);s_free(r1);if(!r2)return NULL;
    while(l2>0&&r2[l2-1]==0)l2--;char*x=s_malloc(l2+1);memcpy(x,r2,l2);x[l2]=0;s_free(r2);return x;
}
static void dtr(cipher_interface_t*s){if(s){s_free(s->private_data);s_free(s);}}
cipher_interface_t* create_desede_cbc_cipher(const uint8_t*k1,const uint8_t*k2,const uint8_t*iv1,const uint8_t*iv2){
    if(!k1||!k2||!iv1||!iv2)return NULL;
    cipher_interface_t*c=s_malloc(sizeof(*c));ctx_t*d=s_malloc(sizeof(*d));
    memcpy(d->k1,k1,24);memcpy(d->k2,k2,24);memcpy(d->iv1,iv1,8);memcpy(d->iv2,iv2,8);
    c->encrypt=enc;c->decrypt=dec;c->destroy=dtr;c->private_data=d;return c;
}

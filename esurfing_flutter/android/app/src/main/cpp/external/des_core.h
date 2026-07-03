#ifndef ESURFING_DES_CORE_H
#define ESURFING_DES_CORE_H
#include <stdint.h>
#include <string.h>
static const int des_ip[64]={58,50,42,34,26,18,10,2,60,52,44,36,28,20,12,4,62,54,46,38,30,22,14,6,64,56,48,40,32,24,16,8,57,49,41,33,25,17,9,1,59,51,43,35,27,19,11,3,61,53,45,37,29,21,13,5,63,55,47,39,31,23,15,7};
static const int des_fp[64]={40,8,48,16,56,24,64,32,39,7,47,15,55,23,63,31,38,6,46,14,54,22,62,30,37,5,45,13,53,21,61,29,36,4,44,12,52,20,60,28,35,3,43,11,51,19,59,27,34,2,42,10,50,18,58,26,33,1,41,9,49,17,57,25};
static const int des_pc1[56]={57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,59,51,43,35,27,19,11,3,60,52,44,36,63,55,47,39,31,23,15,7,62,54,46,38,30,22,14,6,61,53,45,37,29,21,13,5,28,20,12,4};
static const int des_e[48]={32,1,2,3,4,5,4,5,6,7,8,9,8,9,10,11,12,13,12,13,14,15,16,17,16,17,18,19,20,21,20,21,22,23,24,25,24,25,26,27,28,29,28,29,30,31,32,1};
static const int des_pc2[48]={14,17,11,24,1,5,3,28,15,6,21,10,23,19,12,4,26,8,16,7,27,20,13,2,41,52,31,37,47,55,30,40,51,45,33,48,44,49,39,56,34,53,46,42,50,36,29,32};
static const int des_p[32]={16,7,20,21,29,12,28,17,1,15,23,26,5,18,31,10,2,8,24,14,32,27,3,9,19,13,30,6,22,11,4,25};
static const uint8_t des_sbox[8*64]={
14,4,13,1,2,15,11,8,3,10,6,12,5,9,0,7,0,15,7,4,14,2,13,1,10,6,12,11,9,5,3,8,4,1,14,8,13,6,2,11,15,12,9,7,3,10,5,0,15,12,8,2,4,9,1,7,5,11,3,14,10,0,6,13,
15,1,8,14,6,11,3,4,9,7,2,13,12,0,5,10,3,13,4,7,15,2,8,14,12,0,1,10,6,9,11,5,0,14,7,11,10,4,13,1,5,8,12,6,9,3,2,15,13,8,10,1,3,15,4,2,11,6,7,12,0,5,14,9,
10,0,9,14,6,3,15,5,1,13,12,7,11,4,2,8,13,7,0,9,3,4,6,10,2,8,5,14,12,11,15,1,13,6,4,9,8,15,3,0,11,1,2,12,5,10,14,7,1,10,13,0,6,9,8,7,4,15,14,3,11,5,2,12,
7,13,14,3,0,6,9,10,1,2,8,5,11,12,4,15,13,8,11,5,6,15,0,3,4,7,2,12,1,10,14,9,10,6,9,0,12,11,7,13,15,1,3,14,5,2,8,4,3,15,0,6,10,1,13,8,9,4,5,11,12,7,2,14,
2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9,14,11,2,12,4,7,13,1,5,0,15,10,3,9,8,6,4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14,11,8,12,7,1,14,2,13,6,15,0,9,10,4,5,3,
12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11,10,15,4,2,7,12,9,5,6,1,13,14,0,11,3,8,9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6,4,3,2,12,9,5,15,10,11,14,1,7,6,0,8,13,
4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1,13,0,11,7,4,9,1,10,14,3,5,12,2,15,8,6,1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2,6,11,13,8,1,4,10,7,9,5,0,15,14,2,3,12,
13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7,1,15,13,8,10,3,7,4,12,5,6,11,0,14,9,2,7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8,2,1,14,7,4,10,8,13,15,12,9,0,3,5,6,11
};
static const int des_sh[16]={1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1};
static void des_b2b(const uint8_t*in,uint8_t*b){for(int i=0;i<8;i++){uint8_t v=in[i];for(int j=7;j>=0;j--)*b++=(v>>j)&1;}}
static void des_b2B(const uint8_t*b,uint8_t*out){for(int i=0;i<8;i++){uint8_t v=0;for(int j=0;j<8;j++)v=(v<<1)|(b[i*8+j]&1);out[i]=v;}}
static void des_perm(uint8_t*d,const uint8_t*s,const int*t,int n){for(int i=0;i<n;i++)d[i]=s[t[i]-1]&1;}
static void des_ks(const uint8_t k[8],uint8_t sk[16][48]){uint8_t b[64],cd[56],tmp[48];des_b2b(k,b);des_perm(cd,b,des_pc1,56);for(int r=0;r<16;r++){uint8_t C[28],D[28];memcpy(C,cd,28);memcpy(D,cd+28,28);for(int i=0;i<28;i++)cd[i]=C[(i+des_sh[r])%28];for(int i=0;i<28;i++)cd[28+i]=D[(i+des_sh[r])%28];des_perm(tmp,cd,des_pc2,48);memcpy(sk[r],tmp,48);}}
static void des_f(const uint8_t R[32],const uint8_t sk[48],uint8_t o[32]){uint8_t e[48];des_perm(e,R,des_e,48);for(int i=0;i<48;i++)e[i]^=sk[i];uint8_t s[32];const uint8_t*p=e;for(int b=0;b<8;b++){int idx=(b<<6)+p[4]+2*(p[3]+2*(p[2]+2*(p[1]+2*(p[5]+2*p[0]))));uint8_t v=des_sbox[idx]&0x0F;s[b*4+0]=(v>>3)&1;s[b*4+1]=(v>>2)&1;s[b*4+2]=(v>>1)&1;s[b*4+3]=v&1;p+=6;}des_perm(o,s,des_p,32);}
static void des_proc(const uint8_t in[8],uint8_t out[8],const uint8_t sk[16][48],int enc){uint8_t b[64],ip[64];des_b2b(in,b);des_perm(ip,b,des_ip,64);uint8_t L[32],R[32];memcpy(L,ip,32);memcpy(R,ip+32,32);for(int r=0;r<16;r++){uint8_t f[32];const uint8_t*k=enc?sk[r]:sk[15-r];des_f(R,k,f);uint8_t nR[32];for(int i=0;i<32;i++)nR[i]=L[i]^f[i];memcpy(L,R,32);memcpy(R,nR,32);}uint8_t po[64],ob[64];memcpy(po,R,32);memcpy(po+32,L,32);des_perm(ob,po,des_fp,64);des_b2B(ob,out);}
static void des_enc(const uint8_t in[8],uint8_t out[8],const uint8_t key[8]){uint8_t sk[16][48];des_ks(key,sk);des_proc(in,out,sk,1);}
static void des_dec(const uint8_t in[8],uint8_t out[8],const uint8_t key[8]){uint8_t sk[16][48];des_ks(key,sk);des_proc(in,out,sk,0);}
static void des3_enc(const uint8_t in[8],uint8_t out[8],const uint8_t k1[8],const uint8_t k2[8],const uint8_t k3[8]){uint8_t t[8];des_enc(in,t,k1);des_dec(t,out,k2);des_enc(out,t,k3);memcpy(out,t,8);}
static void des3_dec(const uint8_t in[8],uint8_t out[8],const uint8_t k1[8],const uint8_t k2[8],const uint8_t k3[8]){uint8_t t[8];des_dec(in,t,k3);des_enc(t,out,k2);des_dec(out,t,k1);memcpy(out,t,8);}
static void des3_ede_enc(const uint8_t in[8],uint8_t out[8],const uint8_t k[24]){des3_enc(in,out,k,k+8,k+16);}
static void des3_ede_dec(const uint8_t in[8],uint8_t out[8],const uint8_t k[24]){des3_dec(in,out,k,k+8,k+16);}
#endif

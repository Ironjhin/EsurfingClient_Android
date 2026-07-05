#ifndef ESURFINGCLIENT_FFI_BRIDGE_H
#define ESURFINGCLIENT_FFI_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t esurfing_client_init(const char* data_dir, const char* config_json);
int32_t esurfing_client_start(int32_t thread_index);
void   esurfing_client_stop(void);
void   esurfing_client_force_auth_reset(void);
int32_t esurfing_client_is_stopped(void);
void   esurfing_client_destroy(void);

#ifdef __cplusplus
}
#endif

#endif

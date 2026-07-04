#ifndef ESURFINGCLIENT_FFI_BRIDGE_H
#define ESURFINGCLIENT_FFI_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t esurfing_client_init(const char* data_dir, const char* config_json);
int32_t esurfing_client_start(int32_t thread_index);
void   esurfing_client_stop(void);
int32_t esurfing_client_is_stopped(void);
void   esurfing_client_destroy(void);
void   esurfing_client_clear_log(void);

/**
 * @brief 初始化原生层环境（注入 Android 沙盒路径）
 *
 * 应在 esurfing_client_init() 之前调用。
 * 将 Android 私有数据目录路径注入 C 层日志系统，
 * 使日志写入 Android 应用内部存储而非 stdout 或硬编码路径。
 *
 * @param sandbox_path Android Context.filesDir.absolutePath
 */
void   init_native_env(const char* sandbox_path);

#ifdef __cplusplus
}
#endif

#endif

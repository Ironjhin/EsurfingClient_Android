#ifndef ESURFINGCLIENT_WINZSM_H
#define ESURFINGCLIENT_WINZSM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/**
 * Windows 通道 (UA: CCTP/WinSVR5/1068) 的 ZSM 解包.
 *
 * @param data ZSM 原始字节
 * @param length ZSM 长度
 * @param algo_id_out 可选, 写入头部 str2 的 Algo-ID (大写 UUID)
 * @return 是否成功
 */
bool init_win_cipher_from_zsm(const uint8_t* data, size_t length, char* algo_id_out);

#endif // ESURFINGCLIENT_WINZSM_H

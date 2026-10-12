#ifndef ESURFINGCLIENT_LOGOUTSTATE_H
#define ESURFINGCLIENT_LOGOUTSTATE_H

#include "States.h"

/**
 * @brief 把当前会话的现场存下来 (登录成功后调用)
 * @param status 该账号的状态
 * @return 是否写成功
 */
bool logout_state_save(const prog_status_t* status);

/**
 * @brief 读回存档并填进 status
 * @param status 输出 (按存档里的账号序号匹配)
 * @return 是否存在可用的存档
 */
bool logout_state_load(prog_status_t* status);

/**
 * @brief 删掉存档 (登出成功后, 或补登出尝试过之后调用)
 * @param idx 账号序号
 */
void logout_state_clear(uint8_t idx);

/**
 * @brief 补做当前线程账号上次没来得及做的登出
 */
void logout_previous_session(void);

#endif // ESURFINGCLIENT_LOGOUTSTATE_H

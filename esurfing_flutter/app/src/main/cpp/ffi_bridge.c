#include "ffi_bridge.h"
#include "inc/States.h"
#include "inc/DialerClient.h"
#include "inc/NetClient.h"
#include "utils/PlatformUtils.h"
#include "utils/TimeControl.h"
#include "utils/Logger.h"
#include "utils/SimThread.h"
#include "utils/cJSON.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

static char g_data_dir[512];
static int  g_thread_count = 0;
extern bool start_web_server(void);

typedef struct { int idx; sim_thread_t* t; } thread_wrap_t;
static thread_wrap_t* g_threads = NULL;
static int g_started = 0;
static bool g_time_control_started = false;

void init_native_env(const char* sandbox_path)
{
    if (sandbox_path)
    {
        strncpy(g_data_dir, sandbox_path, sizeof(g_data_dir) - 1);
        g_data_dir[sizeof(g_data_dir) - 1] = '\0';
        set_log_dir(g_data_dir);
    }
}

static int parse_json(const char* json) {
    cJSON* root = cJSON_Parse(json);
    if (!root) return -1;
    const cJSON* en = cJSON_GetObjectItem(root, "enabled");
    if (cJSON_IsBool(en)) g_prog_enabled = cJSON_IsTrue(en); else g_prog_enabled = 1;
    const cJSON* lv = cJSON_GetObjectItem(root, "log_lv");
    if (cJSON_IsNumber(lv)) set_logger_level((LogLevel)lv->valueint);
    const cJSON* acts = cJSON_GetObjectItem(root, "accounts");
    if (!acts || !cJSON_IsArray(acts) || cJSON_GetArraySize(acts) == 0) { cJSON_Delete(root); return -1; }
    int cnt = cJSON_GetArraySize(acts);
    g_prog_status = (prog_status_t*)calloc(cnt, sizeof(prog_status_t));
    if (!g_prog_status) { cJSON_Delete(root); return -1; }
    int vc = 0;
    for (int i = 0; i < cnt; i++) {
        const cJSON* a = cJSON_GetArrayItem(acts, i);
        if (!a) continue;
        const cJSON* u = cJSON_GetObjectItem(a, "username");
        const cJSON* p = cJSON_GetObjectItem(a, "password");
        const cJSON* c = cJSON_GetObjectItem(a, "channel");
        const cJSON* m = cJSON_GetObjectItem(a, "mark");
        const cJSON* tw = cJSON_GetObjectItem(a, "time_windows");
        if (!u || !u->valuestring || u->valuestring[0]==0) continue;
        if (!p || !p->valuestring || p->valuestring[0]==0) continue;
        snprintf(g_prog_status[vc].login_cfg.usr, USR_LEN, "%s", u->valuestring);
        snprintf(g_prog_status[vc].login_cfg.pwd, PWD_LEN, "%s", p->valuestring);
        g_prog_status[vc].login_cfg.chn = parse_channel_json(c, (uint8_t)(i + 1));
        apply_channel_ua(&g_prog_status[vc].login_cfg, (uint8_t)(i + 1));
        apply_time_windows(tw, &g_prog_status[vc].login_cfg);
        if (m && m->valuestring && m->valuestring[0]) {
            g_prog_status[vc].login_cfg.mark = (uint32_t)strtoul(m->valuestring, NULL, 16);
            g_prog_status[vc].login_cfg.use_cus_mark = 1;
        } else {
            g_prog_status[vc].login_cfg.mark = 0x100 + vc * 0x100;
        }
        g_prog_status[vc].login_cfg.idx = i + 1;
        vc++;
    }
    g_prog_cnt = vc;
    cJSON_Delete(root);
    return (vc > 0) ? 0 : -1;
}

int32_t esurfing_client_init(const char* data_dir, const char* config_json) {
    if (!data_dir || !config_json) return -1;
    strncpy(g_data_dir, data_dir, sizeof(g_data_dir) - 1);
    set_log_dir(g_data_dir);
    g_need_exit = false; g_thread_keep_alive = true; g_start_run_tm = get_cur_tm_ms(); tl_thread_idx = -1;
    init_logger();
    if (parse_json(config_json) != 0) return -1;
    for (int8_t i = 0; i < g_prog_cnt; i++) { tl_thread_idx = i; refresh_states(); }
    tl_thread_idx = -1;
    time_control_sync();
    return 0;
}

static bool _is_thread_alive(int idx)
{
    return g_threads && g_threads[idx].t && g_prog_status && g_prog_status[idx].runtime_status.is_running;
}

int32_t esurfing_client_start(int32_t idx) {
    if (!g_prog_status || idx < 0 || idx >= g_prog_cnt) return -1;
    if (!g_threads) {
        g_threads = (thread_wrap_t*)calloc(g_prog_cnt, sizeof(thread_wrap_t));
        if (!g_threads) return -1;
    }
    if (!g_time_control_started) {
        time_control_init();
        g_time_control_started = true;
    }
    if (g_prog_status[idx].runtime_status.is_time_disabled) {
        LOG_INFO("配置 %" PRIu8 " 当前不在允许时段，暂不启动认证线程", g_prog_status[idx].login_cfg.idx);
        return 0;
    }
    if (g_threads[idx].t) {
        if (_is_thread_alive(idx)) {
            LOG_VERBOSE("esurfing_client_start(%d): thread already running, skipping", idx);
            return 0;
        }
        LOG_WARN("esurfing_client_start(%d): stale thread handle detected, cleaning up", idx);
        int ret = 0;
        sim_thread_join(g_threads[idx].t, &ret);
        sim_thread_destroy(g_threads[idx].t);
        g_threads[idx].t = NULL;
        g_started--;
    }
    g_threads[idx].idx = idx;
    g_threads[idx].t = sim_thread_create(dialer_app, (void*)(intptr_t)(int8_t)idx);
    if (!g_threads[idx].t) {
        LOG_ERROR("==== [C LOG] sim_thread_create FAILED, errno: %d ====", errno);
        return -1;
    }
    g_started++;
    return 0;
}

void esurfing_client_stop(void) {
    LOG_DEBUG("esurfing_client_stop() called — setting is_need_reset for all threads");
    g_need_exit = true;
    g_thread_keep_alive = false;
    time_control_stop();
    g_time_control_started = false;
    for (int i = 0; i < g_prog_cnt; i++) {
        g_prog_status[i].runtime_status.is_need_reset = true;
        g_prog_status[i].runtime_status.is_running = false;
    }
}

void esurfing_client_clear_log(void) { clear_log_file(); }

int32_t esurfing_client_is_stopped(void) {
    for (int i = 0; i < g_prog_cnt; i++) {
        if (g_prog_status && g_prog_status[i].runtime_status.is_running) return 0;
    }
    return 1;
}

void esurfing_client_destroy(void) {
    esurfing_client_stop();
    if (g_threads) {
        for (int i = 0; i < g_prog_cnt; i++) {
            if (g_threads[i].t) {
                int ret = 0;
                sim_thread_join(g_threads[i].t, &ret);
                sim_thread_destroy(g_threads[i].t);
            }
        }
        free(g_threads);
        g_threads = NULL;
    }
    if (g_prog_status) {
        for (int i = 0; i < g_prog_cnt; i++) {
            if (g_prog_status[i].auth_cfg.cipher) destroy_cipher_factory();
        }
        free(g_prog_status);
        g_prog_status = NULL;
    }
    clean_logger();
    g_started = 0;
    g_prog_cnt = 0;
}

/* 强制重新认证: 设置 is_need_reset 标志, dialer_app 会在就地完成 reset 并重拨 */
void esurfing_client_force_auth_reset(void) {
    if (!g_prog_status) return;
    for (int i = 0; i < g_prog_cnt; i++) {
        g_prog_status[i].runtime_status.is_need_reset = true;
    }
}

int32_t esurfing_client_get_auth_state(int32_t idx) {
    if (!g_prog_status || idx < 0 || idx >= g_prog_cnt) return -1;
    int32_t state = 0;
    if (g_prog_status[idx].runtime_status.is_running)       state |= 0x01;
    if (g_prog_status[idx].runtime_status.is_authed)        state |= 0x02;
    if (g_prog_status[idx].runtime_status.is_connected)     state |= 0x04;
    if (g_prog_status[idx].runtime_status.is_time_disabled) state |= 0x08;
    if (g_prog_status[idx].runtime_status.is_initialized)   state |= 0x10;
    return state;
}


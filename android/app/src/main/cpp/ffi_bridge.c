#include "ffi_bridge.h"
#include "inc/States.h"
#include "inc/DialerClient.h"
#include "inc/NetClient.h"
#include "utils/PlatformUtils.h"
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
        if (!u || !u->valuestring || u->valuestring[0]==0) continue;
        if (!p || !p->valuestring || p->valuestring[0]==0) continue;
        snprintf(g_prog_status[vc].login_cfg.usr, USR_LEN, "%s", u->valuestring);
        snprintf(g_prog_status[vc].login_cfg.pwd, PWD_LEN, "%s", p->valuestring);
        const char* ch = (c&&c->valuestring)?c->valuestring:"phone";
        snprintf(g_prog_status[vc].login_cfg.chn, CHN_LEN, "%s", ch);
        if (strcmp(ch,"pc")==0) snprintf(g_prog_status[vc].login_cfg.user_agent, USER_AGENT_LEN, "CCTP/Linux64/1003");
        else snprintf(g_prog_status[vc].login_cfg.user_agent, USER_AGENT_LEN, "CCTP/android64_vpn/2093");
        if (m&&m->valuestring&&m->valuestring[0]) {
            g_prog_status[vc].login_cfg.mark = (uint32_t)strtoul(m->valuestring,NULL,16);
            g_prog_status[vc].login_cfg.use_cus_mark = 1;
        } else { g_prog_status[vc].login_cfg.mark = 0x100 + vc*0x100; }
        g_prog_status[vc].login_cfg.idx = i+1;
        vc++;
    }
    g_prog_cnt = vc;
    cJSON_Delete(root);
    return (vc>0)?0:-1;
}

int32_t esurfing_client_init(const char* data_dir, const char* config_json) {
    if (!data_dir||!config_json) return -1;
    strncpy(g_data_dir,data_dir,sizeof(g_data_dir)-1);
    set_log_dir(g_data_dir);
    g_need_exit=0; g_thread_keep_alive=1; g_start_run_tm=get_cur_tm_ms(); tl_thread_idx=-1;
    init_logger();
    if (parse_json(config_json)!=0) return -1;
    for (int8_t i=0;i<g_prog_cnt;i++){ tl_thread_idx=i; refresh_states(); }
    tl_thread_idx=-1;
    return 0;
}
int32_t esurfing_client_start(int32_t idx) {
    if (!g_prog_status||idx<0||idx>=g_prog_cnt) return -1;
    if (!g_threads){ g_threads=(thread_wrap_t*)calloc(g_prog_cnt,sizeof(thread_wrap_t)); if(!g_threads)return -1; }
    if (g_threads[idx].t) return 0;
    g_threads[idx].idx=idx;
    g_threads[idx].t=sim_thread_create(dialer_app,(void*)(intptr_t)(int8_t)idx);
    if(!g_threads[idx].t) {
        LOG_ERROR("==== [C LOG] sim_thread_create FAILED, errno: %d ====", errno);
        return -1;
    }
    g_started++; return 0;
}
void esurfing_client_stop(void){ g_need_exit=1; g_thread_keep_alive=0; for(int i=0;i<g_prog_cnt;i++){ g_prog_status[i].runtime_status.is_need_reset=1; g_prog_status[i].runtime_status.is_running=0; } }
int32_t esurfing_client_is_stopped(void){ int r=0; for(int i=0;i<g_prog_cnt;i++)if(g_threads&&g_threads[i].t&&g_prog_status&&g_prog_status[i].runtime_status.is_running)r++; return r==0?1:0; }
void esurfing_client_destroy(void){ esurfing_client_stop(); if(g_threads){ for(int i=0;i<g_prog_cnt;i++){ if(g_threads[i].t){ int ret=0; sim_thread_join(g_threads[i].t,&ret); sim_thread_destroy(g_threads[i].t); }} free(g_threads); g_threads=NULL; } if(g_prog_status){ for(int i=0;i<g_prog_cnt;i++)if(g_prog_status[i].auth_cfg.cipher)destroy_cipher_factory(); free(g_prog_status); g_prog_status=NULL; } clean_logger(); g_started=0; g_prog_cnt=0; }

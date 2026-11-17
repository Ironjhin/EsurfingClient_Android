#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#endif

#include "WebInternal.h"

#include "config/Config.h"
#include "control/Control.h"
#include "core/States.h"
#include "utils/log/Logger.h"
#include "utils/platform/PlatformUtils.h"
#include "utils/sim/SimThread.h"
#include "utils/time/TimeUtils.h"
#include "webserver/HotspotControl.h"

#include <cJSON/cJSON.h>
#include <mongoose/mongoose.h>

#ifndef _WIN32
#include <signal.h>
#include <unistd.h>
#endif

typedef enum
{
    LIFECYCLE_NONE = 0,
    LIFECYCLE_STOP = 1,
    LIFECYCLE_RESTART = 2
} lifecycle_action_t;

static volatile sig_atomic_t s_lifecycle_pending = 0;

/**
 * @brief 执行停止或重启生命周期动作
 *
 * 多进程安全规则:
 * 1. 仅当角色明确为 ROLE_WEB 且父进程 (监管者) 仍存活时才向 getppid() 发信号,
 *    严禁在 ROLE_STANDALONE 模式下向父 Shell 发送 SIGTERM/SIGUSR1。
 * 2. 在 ROLE_WEB 收到重启请求时, 绝不在 Web 子进程自身置 g_need_restart,
 *    统一由监管者收到 SIGUSR1 后有序停止子进程并 execv 重启, 避免双实例争抢 8888 端口。
 */
static void execute_lifecycle_action(const lifecycle_action_t action)
{
    if (action == LIFECYCLE_STOP)
    {
#ifndef _WIN32
        if (g_prog_role == ROLE_WEB && parent_process_alive())
        {
            const pid_t ppid = getppid();
            if (ppid > 1 && kill(ppid, SIGTERM) == 0)
            {
                return;
            }
        }
#endif
        g_stop_requested = 1;
        g_need_exit = true;
        g_thread_keep_alive = false;
    }
    else if (action == LIFECYCLE_RESTART)
    {
#ifndef _WIN32
        if (g_prog_role == ROLE_WEB)
        {
            if (parent_process_alive())
            {
                const pid_t ppid = getppid();
                if (ppid > 1 && kill(ppid, SIGUSR1) == 0)
                {
                    return;
                }
            }
            // 监管进程已不在或信号发送失败时, Web 子进程仅优雅退出, 绝不自行 execv
            g_stop_requested = 1;
            g_need_exit = true;
            return;
        }
#endif
        if (g_prog_role == ROLE_STANDALONE)
        {
            g_need_restart = 1;
            g_stop_requested = 1;
        }
    }
}

static int lifecycle_worker(void* arg)
{
    const lifecycle_action_t action = (lifecycle_action_t)(intptr_t)arg;
    // 微休眠 80ms, 让 Mongoose 事件循环先将 HTTP 200 JSON 完整刷出套接字再触发关停/重启
    sleep_ms(80, false);
    execute_lifecycle_action(action);
    s_lifecycle_pending = 0;
    return 0;
}

static void schedule_lifecycle_action(struct mg_connection* c, const lifecycle_action_t action)
{
    if (c != NULL)
    {
        c->is_draining = 1;
    }
    if (s_lifecycle_pending != 0)
    {
        return;
    }
    s_lifecycle_pending = (sig_atomic_t)action;

    sim_thread_t* worker = sim_thread_create(lifecycle_worker, (void*)(intptr_t)action);
    if (worker != NULL)
    {
        sim_thread_detach(worker);
        sim_thread_destroy(worker);
    }
    else
    {
        s_lifecycle_pending = 0;
        execute_lifecycle_action(action);
    }
}

/**
 * @brief 重新认证 (与"应用配置"一致: 都是重启)
 *
 * Web 进程不碰认证状态: 一律通过控制通道让认证进程退出, 再由监管者重新拉起。
 * 进程内热重载已经去掉, 重新认证不再走 is_need_reauth 那条老路。
 * @return 是否成功
 */
static bool request_restart_auth(void)
{
    return control_restart_auth();
}

/**
 * @brief 应用新配置
 *
 * 不再做进程内的热重载: 认证进程退出, 由监管者用新配置重新拉起它
 * (新配置在它启动时读取), Web 进程与网页不受影响。
 * @return 是否成功
 */
static bool request_apply_config(void)
{
    return control_apply_config();
}

/**
 * @brief 处理 POST API 请求
 * @return 是否已处理
 */
bool handle_api_post(struct mg_connection* c, struct mg_http_message* hm)
{
    // 从 Web 线程读取请求体
    char* data = NULL;
    if (hm->body.len > 0)
    {
        data = malloc(hm->body.len + 1);
        if (data == NULL)
        {
            mg_http_reply(c, 500, HEADER_CORS, "");
            return true;
        }
        memcpy(data, hm->body.buf, hm->body.len);
        data[hm->body.len] = '\0';
    }

    // 仅保存
    if (mg_match(hm->uri, mg_str("/api/saveConfigs"), NULL))
    {
        if (data == NULL)
        {
            mg_http_reply(c, 400, HEADER_CORS, "");
            return true;
        }
        if (save_cfg(data))
        {
            mg_http_reply(c, 204, HEADER_CORS, "");
        }
        else
        {
            mg_http_reply(c, 500, HEADER_CORS, "");
        }
        free(data);
        return true;
    }

    // 仅应用
    if (mg_match(hm->uri, mg_str("/api/applyConfigs"), NULL))
    {
        if (data == NULL)
        {
            mg_http_reply(c, 400, HEADER_CORS, "");
            return true;
        }

        cJSON* operation_json = cJSON_Parse(data);
        if (operation_json == NULL)
        {
            mg_http_reply(c, 500, HEADER_CORS, "");
            free(data);
            return true;
        }

        const cJSON* apply = cJSON_GetObjectItem(operation_json, "apply");
        if (apply != NULL && cJSON_IsBool(apply) && cJSON_IsTrue(apply))
        {
            /**
             * 配置不可用时程序正停在"等配置"的状态, 网页开着就是为了让用户
             * 把配置改回来 —— 这时"保存并应用"就是让主流程重新读一遍配置的
             * 开关: 没有认证线程可下发, 也不需要下发。
             *
             * 同时落下 .apply 标记: 监管者没有控制通道, 只能靠它知道该重读配置
             * (认证进程那边由监管者负责重启, 见 supervisor_sync_cfg)。
             */
            if (g_waiting_cfg)
            {
                g_need_reload = true;
                cfg_request_apply();
                LOG_INFO("收到 Web 应用配置文件请求, 主流程将重新加载配置文件");
                mg_http_reply(c, 204, HEADER_CORS, "");
            }
            else if (g_prog_status == NULL)
            {
                LOG_WARN("收到 Web 应用配置文件请求, 但程序尚未加载完成, 拒绝操作");
                mg_http_reply(c, 403, HEADER_CORS, "");
            }
            else
            {
                bool is_authed = false;
                const bool reachable = query_is_authed(&is_authed);

                if (reachable == false)
                {
                    /**
                     * 修复禁用配置后的永久死锁:
                     * 当用户此前将 enabled 设为 false 应用后 (或认证进程正处于退避未运行),
                     * 认证子进程已退出 (reachable == false), 此时必须照常置 g_need_reload 并调用
                     * cfg_request_apply() 落 .apply 标记通知监管者重新检查配置并拉起认证进程!
                     */
                    g_need_reload = true;
                    cfg_request_apply();
                    LOG_INFO("收到 Web 应用配置文件请求 (当前认证进程未运行), 已通知监管者与主流程重新加载配置");
                    mg_http_reply(c, 204, HEADER_CORS, "");
                }
                else if (request_apply_config() == false)
                {
                    LOG_WARN("收到 Web 应用配置文件请求, 但下发到认证进程失败");
                    mg_http_reply(c, 503, HEADER_CORS, "");
                }
                else
                {
                    // 认证进程整个重启 (退出后由监管者重新拉起);
                    // 监管者与 Web 进程自己走热重载, 不退出
                    g_need_reload = true;
                    cfg_request_apply();

                    LOG_INFO("收到 Web 应用配置文件请求 (当前%s), 认证进程将重启, 其余进程热重载配置",
                        is_authed ? "已认证" : "未认证");
                    mg_http_reply(c, 204, HEADER_CORS, "");
                }
            }
        }
        else
        {
            mg_http_reply(c, 500, HEADER_CORS, "");
        }

        free(data);
        cJSON_Delete(operation_json);
        return true;
    }

    // 重新认证 (Portal 使用 /api/restartAuth 期望 204/503)
    if (mg_match(hm->uri, mg_str("/api/restartAuth"), NULL))
    {
        if (g_prog_status == NULL || g_cfg_loaded == false)
        {
            LOG_WARN("收到 Web 重新认证请求, 但程序尚未加载配置, 拒绝操作");
            mg_http_reply(c, 503, HEADER_CORS, "");
        }
        else
        {
            bool is_authed = false;
            const bool reachable = query_is_authed(&is_authed);

            if (reachable == false)
            {
                LOG_WARN("收到 Web 重新认证请求, 但认证进程不可达");
                mg_http_reply(c, 503, HEADER_CORS, "");
            }
            else if (request_restart_auth() == false)
            {
                LOG_WARN("收到 Web 重新认证请求, 但下发到认证进程失败");
                mg_http_reply(c, 503, HEADER_CORS, "");
            }
            else
            {
                LOG_INFO("收到 Web 重新认证请求, 认证进程将重启");
                mg_http_reply(c, 204, HEADER_CORS, "");
            }
        }

        free(data);
        return true;
    }

    // 强制重新认证 (兼容 KernelSU WebUI /api/auth/reset, 返回 JSON {ok, reason})
    if (mg_match(hm->uri, mg_str("/api/auth/reset"), NULL))
    {
        if (g_prog_status == NULL || g_cfg_loaded == false)
        {
            LOG_WARN("收到 Web 重新认证请求, 但程序尚未加载配置, 拒绝操作");
            mg_http_reply(c, 503, HEADER_JSON, "{\"ok\":false,\"reason\":\"not ready\"}");
        }
        else
        {
            bool is_authed = false;
            const bool reachable = query_is_authed(&is_authed);

            if (reachable == false)
            {
                LOG_WARN("收到 Web 重新认证请求, 但认证进程不可达");
                mg_http_reply(c, 503, HEADER_JSON, "{\"ok\":false,\"reason\":\"no dialer\"}");
            }
            else if (request_restart_auth() == false)
            {
                LOG_WARN("收到 Web 重新认证请求, 但下发到认证进程失败");
                mg_http_reply(c, 503, HEADER_JSON, "{\"ok\":false,\"reason\":\"send failed\"}");
            }
            else
            {
                LOG_INFO("收到 Web 重新认证请求, 认证进程将重启");
                mg_http_reply(c, 200, HEADER_JSON, "{\"ok\":true}");
            }
        }

        free(data);
        return true;
    }

    // 停止服务 (兼容 KernelSU WebUI /api/stop 与 action.sh / uninstall.sh)
    if (mg_match(hm->uri, mg_str("/api/stop"), NULL))
    {
        LOG_INFO("收到 Web 停止服务请求");
        mg_http_reply(c, 200, HEADER_JSON, "{\"ok\":true}");
        free(data);
        schedule_lifecycle_action(c, LIFECYCLE_STOP);
        return true;
    }

    // 重启服务 (兼容 KernelSU WebUI /api/restart)
    if (mg_match(hm->uri, mg_str("/api/restart"), NULL))
    {
        LOG_INFO("收到 Web 重启服务请求");
        mg_http_reply(c, 200, HEADER_JSON, "{\"ok\":true,\"msg\":\"restarting\"}");
        free(data);
        schedule_lifecycle_action(c, LIFECYCLE_RESTART);
        return true;
    }

    // 手动清理日志 (POST /api/logs/clear, 支持 {"mode": "all" | "archived"}, 默认 "all")
    if (mg_match(hm->uri, mg_str("/api/logs/clear"), NULL))
    {
        bool clear_current = true;
        if (data != NULL)
        {
            cJSON* body = cJSON_Parse(data);
            if (body != NULL)
            {
                const cJSON* mode = cJSON_GetObjectItem(body, "mode");
                if (cJSON_IsString(mode) && mode->valuestring != NULL &&
                    strcmp(mode->valuestring, "archived") == 0)
                {
                    clear_current = false;
                }
                cJSON_Delete(body);
            }
        }
        free(data);

        uint32_t deleted_files = 0;
        uint64_t freed_bytes = 0;
        const bool ok = clear_logs(clear_current, &deleted_files, &freed_bytes);

        cJSON* resp = cJSON_CreateObject();
        if (resp == NULL)
        {
            mg_http_reply(c, 500, HEADER_CORS, "");
            return true;
        }
        cJSON_AddBoolToObject(resp, "ok", ok);
        cJSON_AddNumberToObject(resp, "deleted_files", (double)deleted_files);
        cJSON_AddNumberToObject(resp, "freed_bytes", (double)freed_bytes);
        char* resp_text = cJSON_PrintUnformatted(resp);
        if (resp_text != NULL)
        {
            mg_http_reply(c, ok ? 200 : 500, HEADER_JSON, "%s", resp_text);
            free(resp_text);
        }
        else
        {
            mg_http_reply(c, 500, HEADER_CORS, "");
        }
        cJSON_Delete(resp);
        return true;
    }

    free(data);

    /**
     * 热点开关: 立刻回"已受理", 真正的切换在后台线程里跑 (要起一次 PowerShell,
     * 快则一秒慢则十几秒, 不能占着 Web 线程); 页面随后轮询 /api/hotspot/status 看结果
     */
    if (mg_match(hm->uri, mg_str("/api/hotspot/start"), NULL) ||
        mg_match(hm->uri, mg_str("/api/hotspot/stop"), NULL))
    {
        const bool is_start = mg_match(hm->uri, mg_str("/api/hotspot/start"), NULL);
        char adapter[ADAPTER_ID_LEN] = {0};
        const int adapter_len = mg_http_get_var(&hm->query, "adapter", adapter, sizeof(adapter));
        if (adapter_len <= 0)
        {
            LOG_WARN("收到热点%s请求, 但没有指定网卡", is_start ? "开启" : "关闭");
            mg_http_reply(c, 400, HEADER_CORS, "");
            return true;
        }

        char* body = NULL;
        const int status = hotspot_request(is_start ? "start" : "stop", adapter, &body);
        if (body != NULL)
        {
            mg_http_reply(c, status, HEADER_JSON, "%s", body);
            free(body);
        }
        else
        {
            mg_http_reply(c, status, HEADER_CORS, "");
        }
        return true;
    }

    // 未知的 POST 路径
    mg_http_reply(c, 404, HEADER_TEXT, "Not found\n");
    return true;
}

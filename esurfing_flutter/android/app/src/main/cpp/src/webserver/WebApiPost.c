#include "WebInternal.h"

#include "config/Config.h"
#include "control/Control.h"
#include "core/States.h"
#include "utils/log/Logger.h"
#include "utils/platform/PlatformUtils.h"
#include "webserver/HotspotControl.h"

#include <cJSON/cJSON.h>
#include <mongoose/mongoose.h>

#ifndef _WIN32
#include <unistd.h>
#include <signal.h>
#endif

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
        if (apply)
        {
            if (cJSON_IsBool(apply))
            {
                if (g_waiting_cfg)
                {
                    g_need_reload = true;
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
                        LOG_WARN("收到 Web 应用配置文件请求, 但认证进程不可达");
                        mg_http_reply(c, 503, HEADER_CORS, "");
                    }
                    else if (request_apply_config() == false)
                    {
                        LOG_WARN("收到 Web 应用配置文件请求, 但下发到认证进程失败");
                        mg_http_reply(c, 503, HEADER_CORS, "");
                    }
                    else
                    {
                        LOG_INFO("收到 Web 应用配置文件请求 (当前%s), 程序将重新加载配置文件",
                            is_authed ? "已认证" : "未认证");
                        mg_http_reply(c, 204, HEADER_CORS, "");
                    }
                }
            }
            else
            {
                mg_http_reply(c, 500, HEADER_CORS, "");
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

    // 重新认证 (同时兼容 /api/restartAuth 与旧版/KernelSU WebUI 的 /api/auth/reset)
    if (mg_match(hm->uri, mg_str("/api/restartAuth"), NULL) ||
        mg_match(hm->uri, mg_str("/api/auth/reset"), NULL))
    {
        cJSON* resp = cJSON_CreateObject();
        if (g_prog_status == NULL || g_cfg_loaded == false)
        {
            LOG_WARN("收到 Web 重新认证请求, 但程序尚未加载配置, 拒绝操作");
            cJSON_AddBoolToObject(resp, "ok", false);
            cJSON_AddStringToObject(resp, "reason", "not ready");
            char* body = cJSON_Print(resp);
            mg_http_reply(c, 503, HEADER_JSON, "%s", body ? body : "{\"ok\":false}");
            if (body) free(body);
        }
        else
        {
            bool is_authed = false;
            const bool reachable = query_is_authed(&is_authed);

            if (reachable == false)
            {
                LOG_WARN("收到 Web 重新认证请求, 但认证进程不可达");
                cJSON_AddBoolToObject(resp, "ok", false);
                cJSON_AddStringToObject(resp, "reason", "no dialer");
                char* body = cJSON_Print(resp);
                mg_http_reply(c, 503, HEADER_JSON, "%s", body ? body : "{\"ok\":false}");
                if (body) free(body);
            }
            else if (request_restart_auth() == false)
            {
                LOG_WARN("收到 Web 重新认证请求, 但下发到认证进程失败");
                cJSON_AddBoolToObject(resp, "ok", false);
                cJSON_AddStringToObject(resp, "reason", "send failed");
                char* body = cJSON_Print(resp);
                mg_http_reply(c, 503, HEADER_JSON, "%s", body ? body : "{\"ok\":false}");
                if (body) free(body);
            }
            else
            {
                LOG_INFO("收到 Web 重新认证请求, 认证进程将重启");
                cJSON_AddBoolToObject(resp, "ok", true);
                char* body = cJSON_Print(resp);
                mg_http_reply(c, 200, HEADER_JSON, "%s", body ? body : "{\"ok\":true}");
                if (body) free(body);
            }
        }
        cJSON_Delete(resp);
        free(data);
        return true;
    }

    // 停止服务 (兼容 KernelSU WebUI /api/stop 与 action.sh)
    if (mg_match(hm->uri, mg_str("/api/stop"), NULL))
    {
        LOG_INFO("收到 Web 停止服务请求");
        cJSON* resp = cJSON_CreateObject();
        cJSON_AddBoolToObject(resp, "ok", true);
        char* body = cJSON_Print(resp);
        mg_http_reply(c, 200, HEADER_JSON, "%s", body ? body : "{\"ok\":true}");
        if (body) free(body);
        cJSON_Delete(resp);
        free(data);

#ifndef _WIN32
        // 在多进程模式下，向监管者 (父进程) 发送 SIGTERM
        pid_t ppid = getppid();
        if (ppid > 1)
        {
            kill(ppid, SIGTERM);
        }
#endif
        g_stop_requested = 1;
        g_need_exit = true;
        g_thread_keep_alive = false;
        return true;
    }

    // 重启服务 (兼容 KernelSU WebUI /api/restart)
    if (mg_match(hm->uri, mg_str("/api/restart"), NULL))
    {
        LOG_INFO("收到 Web 重启服务请求");
        cJSON* resp = cJSON_CreateObject();
        cJSON_AddBoolToObject(resp, "ok", true);
        cJSON_AddStringToObject(resp, "msg", "restarting");
        char* body = cJSON_Print(resp);
        mg_http_reply(c, 200, HEADER_JSON, "%s", body ? body : "{\"ok\":true}");
        if (body) free(body);
        cJSON_Delete(resp);
        free(data);

#ifndef _WIN32
        // 在多进程模式下，向监管者 (父进程) 发送 SIGUSR1
        pid_t ppid = getppid();
        if (ppid > 1)
        {
            kill(ppid, SIGUSR1);
        }
#endif
        g_need_restart = true;
        g_stop_requested = 1;
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

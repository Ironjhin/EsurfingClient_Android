#include "utils/PlatformUtils.h"
#include "utils/Logger.h"
#include "NetClient.h"
#include "States.h"
#include "external/md5.h"


#include <string.h>
#include <stdio.h>
#include <errno.h>

#ifdef __OPENWRT__
#ifndef SOL_SOCKET
    #define SOL_SOCKET 1
#endif

#ifndef SO_MARK
    #define SO_MARK 36
#endif
#endif

#define MAX_LEN 128

#define SCHOOL_ID_LENGTH 8
#define DOMAIN_LENGTH 16
#define AREA_LENGTH 8

static const char s_req_content_type[] = "Content-Type: application/x-www-form-urlencoded";
static const char s_req_accept[] = "Accept: text/html,text/xml,application/xhtml+xml,application/x-javascript,*/*";
static const char s_generate_url[] = "http://connect.rom.miui.com/generate_204";
static const char s_backup_generate_url[] = "http://192.0.2.1";

static char s_school_id[SCHOOL_ID_LENGTH];
static char s_domain[DOMAIN_LENGTH];
static char s_area[AREA_LENGTH];

/* 线程本地存储：允许调用方在 get() 前注入一个额外 HTTP 头（如 Host） */
static __thread char tls_extra_header[512] = {0};

void set_next_get_header(const char* header)
{
    if (header)
    {
        strncpy(tls_extra_header, header, sizeof(tls_extra_header) - 1);
        tls_extra_header[sizeof(tls_extra_header) - 1] = '\0';
    }
}

char* extract_url_param(const char* url, const char* search_str_start)
{
    if (url == NULL)
    {
        LOG_ERROR("URL 为空");
        return NULL;
    }
    const size_t len = strlen(search_str_start);
    char* search_pattern = malloc(len + 2);
    if (search_pattern == NULL)
    {
        LOG_ERROR("分配内存失败");
        return NULL;
    }
    snprintf(search_pattern, len + 2, "%s=", search_str_start);
    char* result = extract_between_tags(url, search_pattern, "&");
    free(search_pattern);
    return result;
}

static curl_socket_t open_socket_callback(void* client_p, curlsocktype purpose, struct curl_sockaddr* addr)
{
    (void)client_p;
    (void)purpose;
    curl_socket_t sock_fd = socket(addr->family, addr->socktype, addr->protocol);
    if (sock_fd == CURL_SOCKET_BAD)
    {
        LOG_ERROR("创建 socket 失败: %s", strerror(errno));
        return CURL_SOCKET_BAD;
    }

#ifndef __ANDROID__
    if (g_prog_status[tl_thread_idx].login_cfg.mark != 0)
    {
        if (setsockopt(sock_fd, SOL_SOCKET, SO_MARK,
                &g_prog_status[tl_thread_idx].login_cfg.mark,
                sizeof(g_prog_status[tl_thread_idx].login_cfg.mark)) == -1)
        {
            if (errno == EPERM || errno == EACCES)
            {
                LOG_WARN("setsockopt SO_MARK failed (EPERM), bypassing for Android compatibility...");
            }
            else
            {
                LOG_ERROR("设置 SO_MARK 失败 (mark = %" PRIu32 " (0x%x)): %s",
                    g_prog_status[tl_thread_idx].login_cfg.mark,
                    g_prog_status[tl_thread_idx].login_cfg.mark, strerror(errno));
            }
        }
        else
        {
            LOG_VERBOSE("设置 SO_MARK = %" PRIu32 " (0x%x)",
                g_prog_status[tl_thread_idx].login_cfg.mark,
                g_prog_status[tl_thread_idx].login_cfg.mark);
        }
    }
#endif

    return sock_fd;
}

static size_t header_cb(const void* contents, const size_t size, const size_t nmemb, void* userdata)
{
    const size_t real_size = size * nmemb;
    const char* header = contents;

    if (real_size >= 9 && strncmp(header, "schoolid:", 9) == 0 && !s_school_id[0])
    {
        if (s_school_id[0] == '\0')
        {
            LOG_VERBOSE("原始数据: %s", header);

            const char* value = header + 9;
            while (*value == ' ') value++;
            const size_t valid_len = strcspn(value, "\r\n");

            size_t copy_len = valid_len;
            if (copy_len >= SCHOOL_ID_LENGTH)
            {
                copy_len = SCHOOL_ID_LENGTH - 1;
                LOG_WARN("School Id 被截断, 原长度: %zu, 缓冲区大小: %d", valid_len, SCHOOL_ID_LENGTH);
            }

            memcpy(s_school_id, value, copy_len);
            s_school_id[copy_len] = '\0';

            LOG_INFO("School Id: %s", s_school_id);
        }
    }

    if (real_size >= 7 && strncmp(header, "domain:", 7) == 0 && !s_domain[0])
    {
        if (s_domain[0] == '\0')
        {
            LOG_VERBOSE("原始数据: %s", header);

            const char* value = header + 7;
            while (*value == ' ') value++;
            const size_t valid_len = strcspn(value, "\r\n");

            size_t copy_len = valid_len;
            if (copy_len >= DOMAIN_LENGTH)
            {
                copy_len = DOMAIN_LENGTH - 1;
                LOG_WARN("Domain 被截断, 原长度: %zu, 缓冲区大小: %d", valid_len, DOMAIN_LENGTH);
            }

            memcpy(s_domain, value, copy_len);
            s_domain[copy_len] = '\0';

            LOG_INFO("Domain: %s", s_domain);
        }
    }

    if (real_size >= 5 && strncmp(header, "area:", 5) == 0 && !s_area[0])
    {
        if (s_area[0] == '\0')
        {
            LOG_VERBOSE("原始数据: %s", header);

            const char* value = header + 5;
            while (*value == ' ') value++;
            const size_t valid_len = strcspn(value, "\r\n");

            size_t copy_len = valid_len;
            if (copy_len >= AREA_LENGTH)
            {
                copy_len = AREA_LENGTH - 1;
                LOG_WARN("Area 被截断, 原长度: %zu, 缓冲区大小: %d", valid_len, AREA_LENGTH);
            }

            memcpy(s_area, value, copy_len);
            s_area[copy_len] = '\0';

            LOG_INFO("Area: %s", s_area);
        }
    }

    if (real_size >= 9 && strncasecmp(header, "Location:", 9) == 0)
    {
        if (tl_thread_idx != -1)
        {
            if (!g_prog_status[tl_thread_idx].last_location_lock)
            {
                LOG_VERBOSE("原始数据: %s", header);

                const char* value = header + 9;
                while (*value == ' ') value++;
                const size_t valid_len = strcspn(value, "\r\n");

                size_t copy_len = valid_len;
                if (copy_len >= LAST_LOCATION_LEN)
                {
                    copy_len = LAST_LOCATION_LEN - 1;
                    LOG_WARN("Location 被截断, 原长度: %zu, 缓冲区大小: %d", valid_len, LAST_LOCATION_LEN);
                }

                memcpy(g_prog_status[tl_thread_idx].last_location, value, copy_len);
                g_prog_status[tl_thread_idx].last_location[copy_len] = '\0';

                LOG_VERBOSE("现在的 last_location: %s (长度: %zu)",
                            g_prog_status[tl_thread_idx].last_location, copy_len);
            }
        }
    }

    return real_size;
}

static size_t write_cb(const void* contents, const size_t size, const size_t nmemb, void* userdata)
{
    http_resp_t* resp = userdata;
    const size_t real_size = size * nmemb;
    char* ptr = realloc(resp->body_data, resp->body_size + real_size + 1);

    if (!ptr) return 0;

    resp->body_data = ptr;
    memcpy(&resp->body_data[resp->body_size], contents, real_size);
    resp->body_size += real_size;
    resp->body_data[resp->body_size] = 0;

    return real_size;
}

static char* calc_md5(const char* data)
{
    if (!data) return NULL;
    char* md5_str = (char*)malloc(33);
    if (!md5_str) { LOG_ERROR("malloc failed"); return NULL; }
    char* ret = md5_hex((const unsigned char*)data, strlen(data), md5_str);
    if (!ret) { free(md5_str); LOG_ERROR("md5 failed"); return NULL; }
    return md5_str;
}

static NetworkStatus curl_err_msg_out(const CURLcode curl_code)
{
    switch (curl_code)
    {
    case CURLE_COULDNT_RESOLVE_HOST:
        LOG_ERROR("curl 错误码: 6, 错误原因: DNS 解析错误");
        return REQUEST_ERROR;
    case CURLE_COULDNT_CONNECT:
        LOG_ERROR("curl 错误码: 7, 错误原因: 连接服务器失败");
        return REQUEST_ERROR;
    case CURLE_OPERATION_TIMEDOUT:
        LOG_ERROR("curl 错误码: 28, 错误原因: 操作超时");
        return REQUEST_WARN;
    case CURLE_HTTP_RETURNED_ERROR:
        LOG_ERROR("curl 错误码: 22, 错误原因: HTTP 状态码 ≥ 400");
        return REQUEST_ERROR;
    case CURLE_GOT_NOTHING:
        LOG_ERROR("curl 错误码: 52, 错误原因: 服务器返回空数据");
        return REQUEST_ERROR;
    case CURLE_URL_MALFORMAT:
        LOG_ERROR("curl 错误码: 3, 错误原因: URL 格式错误");
        return REQUEST_ERROR;
    case CURLE_WRITE_ERROR:
        LOG_ERROR("curl 错误码: 23, 错误原因: 写入数据失败");
        return REQUEST_ERROR;
    case CURLE_ABORTED_BY_CALLBACK:
        LOG_ERROR("curl 错误码: 42, 错误原因: 回调函数中止");
        return REQUEST_ERROR;
    default:
        LOG_ERROR("未知错误");
        return REQUEST_ERROR;
    }
}

http_resp_t post(const char* url, const char* data)
{
    LOG_VERBOSE("POST 地址: %s", url);
    LOG_VERBOSE("POST 数据: %s", data);

    http_resp_t resp = {0};

    char md5_hash_str[MAX_LEN] = {0};
    char ua[MAX_LEN] = {0};
    char c_id[MAX_LEN] = {0};
    char a_id[MAX_LEN] = {0};
    char cdc_sid[MAX_LEN] = {0};
    char cdc_d[MAX_LEN] = {0};
    char cdc_a[MAX_LEN] = {0};
    char* md5_hash = calc_md5(data);
    if (!md5_hash)
    {
        LOG_ERROR("计算 MD5 失败");
        resp.status = REQUEST_ERROR;
        return resp;
    }

    snprintf(md5_hash_str, MAX_LEN, "CDC-Checksum: %s", safe_str(md5_hash));
    free(md5_hash);
    snprintf(ua, MAX_LEN, "User-Agent: %s", safe_str(g_prog_status[tl_thread_idx].login_cfg.user_agent));
    snprintf(c_id, MAX_LEN, "Client-ID: %s", safe_str(g_prog_status[tl_thread_idx].auth_cfg.client_id));
    snprintf(a_id, MAX_LEN, "Algo-ID: %s", safe_str(g_prog_status[tl_thread_idx].auth_cfg.algo_id));
    snprintf(cdc_sid, MAX_LEN, "CDC-SchoolId: %s", safe_str(s_school_id));
    snprintf(cdc_d, MAX_LEN, "CDC-Domain: %s", safe_str(s_domain));
    snprintf(cdc_a, MAX_LEN, "CDC-Area: %s", safe_str(s_area));

    LOG_VERBOSE("POST 添加头 %s", md5_hash_str);
    LOG_VERBOSE("POST 添加头 %s", s_req_content_type);
    LOG_VERBOSE("POST 添加头 %s", ua);
    LOG_VERBOSE("POST 添加头 %s", s_req_accept);
    LOG_VERBOSE("POST 添加头 %s", c_id);
    LOG_VERBOSE("POST 添加头 %s", a_id);
    LOG_VERBOSE("POST 添加头 %s", cdc_sid);
    LOG_VERBOSE("POST 添加头 %s", cdc_d);
    LOG_VERBOSE("POST 添加头 %s", cdc_a);
    LOG_VERBOSE("下标: %" PRId8, tl_thread_idx);

    struct curl_slist* headers = NULL;

    headers = curl_slist_append(headers, md5_hash_str);
    headers = curl_slist_append(headers, s_req_content_type);
    headers = curl_slist_append(headers, ua);
    headers = curl_slist_append(headers, s_req_accept);
    headers = curl_slist_append(headers, c_id);
    headers = curl_slist_append(headers, a_id);
    headers = curl_slist_append(headers, cdc_sid);
    headers = curl_slist_append(headers, cdc_d);
    headers = curl_slist_append(headers, cdc_a);

    CURL* curl = curl_easy_init();
    if (curl == NULL)
    {
        LOG_ERROR("curl 初始化失败");
        resp.status = REQUEST_INIT_ERROR;
        curl_slist_free_all(headers);
        return resp;
    }
    LOG_VERBOSE("curl 初始化完成, curl: %p", curl);

    LOG_VERBOSE("设置 curl 选项");
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, data);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &resp);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 10L);
    curl_easy_setopt(curl, CURLOPT_OPENSOCKETFUNCTION, open_socket_callback);
    curl_easy_setopt(curl, CURLOPT_COOKIEFILE, "");

    LOG_VERBOSE("执行 CURL");
    const CURLcode curl_code = curl_easy_perform(curl);
    if (curl_code != CURLE_OK)
    {
        LOG_ERROR("POST curl 执行失败: curl_code=%d(%s)", curl_code, curl_easy_strerror(curl_code));
        curl_easy_cleanup(curl);
        curl_slist_free_all(headers);
        resp.status = curl_err_msg_out(curl_code);
        return resp;
    }

    LOG_VERBOSE("获取响应码");
    long resp_code;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &resp_code);

    curl_easy_cleanup(curl);
    curl_slist_free_all(headers);

    if (resp_code == 302)
    {
        LOG_DEBUG("重定向, 响应码: 302");
        if (tl_thread_idx != -1) LOG_VERBOSE("重定向至: %s", g_prog_status[tl_thread_idx].last_location);
        resp.status = REQUEST_REDIRECT;
        return resp;
    }
    if (resp_code == 200)
    {
        LOG_DEBUG("有响应体, 响应码: 200");
        resp.status = REQUEST_HAVE_RES;
        return resp;
    }
    if (resp_code == 204)
    {
        LOG_VERBOSE("无响应体, 响应码: 204");
        resp.status = REQUEST_SUCCESS;
        return resp;
    }

    LOG_ERROR("HTTP 响应错误, 响应码: %ld", resp_code);
    resp.status = REQUEST_ERROR;
    return resp;
}

http_resp_t get(const char* url)
{
    LOG_VERBOSE("GET 地址: %s", url);

    http_resp_t resp = {0};

    char c_id[MAX_LEN] = {0};

    struct curl_slist* headers = NULL;

    if (tl_thread_idx != -1)
    {
        snprintf(c_id, MAX_LEN, "Client-ID: %s", safe_str(g_prog_status[tl_thread_idx].auth_cfg.client_id));

        LOG_VERBOSE("GET 添加头 %s", s_req_accept);
        LOG_VERBOSE("GET 添加头 %s", c_id);
        LOG_VERBOSE("线程下标: %" PRId8, tl_thread_idx);

        headers = curl_slist_append(headers, s_req_accept);
        headers = curl_slist_append(headers, c_id);

        if (tls_extra_header[0])
        {
            LOG_VERBOSE("GET 添加额外头 %s", tls_extra_header);
            headers = curl_slist_append(headers, tls_extra_header);
            tls_extra_header[0] = '\0';
        }
    }

    CURL* curl = curl_easy_init();
    if (curl == NULL)
    {
        LOG_ERROR("curl 初始化失败");
        resp.status = REQUEST_INIT_ERROR;
        curl_slist_free_all(headers);
        return resp;
    }
    LOG_VERBOSE("curl 初始化完成, curl = %p", curl);

    LOG_VERBOSE("设置 curl 选项");
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 10L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 5L);
    if (tl_thread_idx != -1)
    {
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, header_cb);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &resp);
        curl_easy_setopt(curl, CURLOPT_OPENSOCKETFUNCTION, open_socket_callback);
        curl_easy_setopt(curl, CURLOPT_COOKIEFILE, "");
        curl_easy_setopt(curl, CURLOPT_USERAGENT, g_prog_status[tl_thread_idx].login_cfg.user_agent);
    }

    LOG_VERBOSE("执行 CURL");
    const CURLcode curl_code = curl_easy_perform(curl);

    // 即使 curl_easy_perform 失败（如 FOLLOWLOCATION 后目标 DNS 解析失败），
    // 也要检查是否发生过重定向（有重定向说明 captive portal 已拦截探测请求）
    long redirect_count = 0;
    curl_easy_getinfo(curl, CURLINFO_REDIRECT_COUNT, &redirect_count);

    if (curl_code != CURLE_OK)
    {
        if (redirect_count > 0)
        {
            LOG_DEBUG("自动跟随了 %ld 次重定向后出错 (%s)，判定为 captive portal 已拦截",
                      redirect_count, curl_easy_strerror(curl_code));
            if (tl_thread_idx != -1) LOG_VERBOSE("最后的 last_location: %s", g_prog_status[tl_thread_idx].last_location);
            if (resp.body_data) { free(resp.body_data); resp.body_data = NULL; }
            resp.status = REQUEST_REDIRECT;
            curl_easy_cleanup(curl);
            curl_slist_free_all(headers);
            return resp;
        }
        LOG_ERROR("curl 执行失败: curl_code=%d(%s)", curl_code, curl_easy_strerror(curl_code));
        curl_easy_cleanup(curl);
        curl_slist_free_all(headers);
        resp.status = curl_err_msg_out(curl_code);
        resp.curl_code = curl_code;
        return resp;
    }

    // libcurl 已自动跟随所有重定向
    if (redirect_count > 0)
    {
        LOG_DEBUG("自动跟随了 %ld 次重定向", redirect_count);
        if (tl_thread_idx != -1) LOG_VERBOSE("最终重定向至: %s", g_prog_status[tl_thread_idx].last_location);
        if (resp.body_data) { free(resp.body_data); resp.body_data = NULL; }
        resp.status = REQUEST_REDIRECT;
        curl_easy_cleanup(curl);
        curl_slist_free_all(headers);
        return resp;
    }

    LOG_VERBOSE("获取响应码");
    long resp_code;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &resp_code);

    curl_easy_cleanup(curl);
    curl_slist_free_all(headers);

    if (resp_code == 200)
    {
        LOG_DEBUG("有响应体, 响应码: 200");
        resp.status = REQUEST_HAVE_RES;
        return resp;
    }
    if (resp_code == 204)
    {
        LOG_VERBOSE("无响应体, 响应码: 204");
        resp.status = REQUEST_SUCCESS;
        return resp;
    }

    LOG_ERROR("HTTP 响应错误, 响应码: %ld", resp_code);
    resp.status = REQUEST_ERROR;
    return resp;
}

NetworkStatus check_network_status()
{
    http_resp_t resp = get(s_generate_url);
    if (resp.status != REQUEST_REDIRECT && resp.status != REQUEST_SUCCESS)
    {
        LOG_WARN("探测 URL 异常 (curl_code=%d, status=%d), 尝试备用超时方案", resp.curl_code, resp.status);
        resp = get(s_backup_generate_url);
        if (resp.status == REQUEST_WARN)
        {
            // 192.0.2.1 不可路由，有网时必然超时 → 视为已连接
            LOG_VERBOSE("备用 URL 超时 — 网络可达，判定为互联网已连接");
            resp.status = REQUEST_SUCCESS;
        }
        else
        {
            LOG_WARN("备用 URL 也失败 (status=%d)", resp.status);
        }
    }
    return resp.status;
}

static void get_school_ip_symbol()
{
    const char* school_ip = extract_url_param(g_prog_status[0].last_location, "wlanuserip");
    if (school_ip == NULL)
    {
        LOG_WARN("获取校园网标志失败: 无法从 last_location 中提取 wlanuserip");
        return;
    }
    const char* first_dot = strchr(school_ip, '.');
    if (first_dot == NULL)
    {
        LOG_WARN("获取校园网标志失败: IP 格式异常");
        return;
    }
    const char* second_dot = strchr(first_dot + 1, '.');
    if (second_dot == NULL)
    {
        LOG_WARN("获取校园网标志失败: IP 格式异常 (缺少第二个点)");
        return;
    }
    snprintf(g_school_network_symbol, SCHOOL_NETWORK_SYMBOL, "%s", safe_str(extract_between_tags(school_ip, "", second_dot)));
    LOG_INFO("获取到校园网标志: %s", g_school_network_symbol);
}

NetworkStatus get_last_location()
{
    http_resp_t resp = {0};

    uint8_t retry = 1;
    do
    {
        resp = get(s_generate_url); // 检测响应码
        if (resp.status != REQUEST_REDIRECT && resp.status != REQUEST_SUCCESS)
        {
            LOG_WARN("主探测 URL 异常 (curl_code=%d, status=%d), 尝试备用 URL", resp.curl_code, resp.status);
            resp = get(s_backup_generate_url);
            if (resp.status == REQUEST_WARN)
            {
                LOG_VERBOSE("备用 URL 超时 — 网络可达，视为已连接");
                resp.status = REQUEST_SUCCESS;
            }
        }
        switch (resp.status)
        {
        case REQUEST_REDIRECT:
            break;
        case REQUEST_SUCCESS:
            LOG_WARN("get_last_location: Captive portal not triggered. Status code: 204. Network might be already online or not intercepted by gateway.");
            retry = 1;
            LOG_INFO("已连接至互联网");
            sleep_ms(10000, true);
            break;
        default:
            if (resp.status == REQUEST_HAVE_RES)
            {
                LOG_WARN("get_last_location: Captive portal not triggered. Status code: 200. Network might be already online or not intercepted by gateway.");
            }
            if (retry > 5)
            {
                LOG_FATAL("get_last_location: 超过最多重试次数, curl_code=%d, status=%d", resp.curl_code, resp.status);
                return REQUEST_ERROR;
            }
            LOG_WARN("非重定向, curl_code=%d, 响应码: %d, 重试: 第 %" PRIu8 " 次, 最多 5 次", resp.curl_code, resp.status, retry);
            retry++;
            sleep_ms(1000, true);
            break;
        }
    } while (resp.status != REQUEST_REDIRECT);

    // rewrite known portal domains to IPs (internal DNS unreachable on unauthenticated devices)
    const char* portal_map[][2] = {{"enet.10000.gd.cn", "125.88.59.131"}, {NULL, NULL}};
    for (int pm = 0; portal_map[pm][0] != NULL; pm++)
    {
        char sf[128];
        const int sl = snprintf(sf, sizeof(sf), "://%s", portal_map[pm][0]);
        if (sl > 0 && (size_t)sl < sizeof(sf))
        {
            char* fp = strstr(g_prog_status[tl_thread_idx].last_location, sf);
            if (fp)
            {
                const size_t pl = (size_t)(fp - g_prog_status[tl_thread_idx].last_location);
                char nl[LAST_LOCATION_LEN];
                const int nn = snprintf(nl, sizeof(nl), "%.*s%s%s", (int)pl,
                    g_prog_status[tl_thread_idx].last_location,
                    portal_map[pm][1], fp + sl);
                if (nn > 0 && (size_t)nn < sizeof(nl))
                {
                    strncpy(g_prog_status[tl_thread_idx].last_location, nl, LAST_LOCATION_LEN - 1);
                    g_prog_status[tl_thread_idx].last_location[LAST_LOCATION_LEN - 1] = '\0';
                }
                LOG_VERBOSE("portal domain %s -> IP %s, fixed url: %s",
                    portal_map[pm][0], portal_map[pm][1], g_prog_status[tl_thread_idx].last_location);
                break;
            }
        }
    }

    g_prog_status[tl_thread_idx].last_location_lock = true;
    LOG_DEBUG("配置 %" PRIu8 " 获取认证配置 URL: %s", g_prog_status[tl_thread_idx].login_cfg.idx, g_prog_status[tl_thread_idx].last_location);

    get_school_ip_symbol(); // 获取校园网特征
    return REQUEST_REDIRECT;
}

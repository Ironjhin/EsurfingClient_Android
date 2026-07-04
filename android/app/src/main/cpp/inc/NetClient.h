#ifndef ESURFINGCLIENT_NETCLIENT_H
#define ESURFINGCLIENT_NETCLIENT_H

#include <curl/curl.h>

typedef enum {
    REQUEST_ERROR = 0,
    REQUEST_INIT_ERROR = 1,
    REQUEST_WARN = 2,
    REQUEST_HAVE_RES = 200,
    REQUEST_SUCCESS = 204,
    REQUEST_REDIRECT = 302
} NetworkStatus;

typedef struct {
    NetworkStatus status;
    CURLcode curl_code;
    char* body_data;
    size_t body_size;
} http_resp_t;

/**
 * @brief 截取 URL 中指定参数
 * @param url URL 地址
 * @param search_str_start 要查找的参数名
 * @return 查找到的参数
 */
char* extract_url_param(const char* url, const char* search_str_start);

/**
 * @brief 带默认头的 POST
 * @param url 地址
 * @param data 数据
 * @return 响应数据
 */
http_resp_t post(const char* url, const char* data);

/**
 * @brief 带默认头的 GET
 * @param url 地址
 * @return 响应数据
 *
 */
http_resp_t get(const char* url);

/**
 * @brief 检测网络状态
 * @return 网络状态
 */
NetworkStatus check_network_status();

/**
 * @brief 获取所有 ip 的 last_location
 * @return 网络状态
 */
NetworkStatus get_last_location();

/**
 * @brief 设置下一个 get() 请求的额外 HTTP 头（线程本地，一次有效）
 * @param header 完整的 HTTP 头字符串，例如 "Host: example.com:8080"
 */
void set_next_get_header(const char* header);

#endif //ESURFINGCLIENT_NETCLIENT_H

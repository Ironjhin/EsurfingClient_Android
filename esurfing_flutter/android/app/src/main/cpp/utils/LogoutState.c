#include "utils/LogoutState.h"
#include "utils/PlatformUtils.h"
#include "utils/Logger.h"
#include "utils/cJSON.h"
#include "cipher/CipherInterface.h"
#include "cipher/IosZsm.h"
#include "DialerClient.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool logout_state_path(char* out, const size_t len, const uint8_t idx)
{
    const char* cfg = get_config_path();
    if (cfg == NULL || cfg[0] == '\0') return false;

    const int n = snprintf(out, len, "%s.%" PRIu8 ".logout", cfg, idx);
    return n > 0 && (size_t)n < len;
}

static void zsm_blob_to_json(cJSON* root, const ios_zsm_blob_t* blob)
{
    if (root == NULL || blob == NULL) return;

    if (blob->key != NULL && blob->key_len > 0)
    {
        char* b64 = bytes2base64(blob->key, blob->key_len);
        if (b64 != NULL)
        {
            cJSON_AddStringToObject(root, "zsm_key", b64);
            free(b64);
        }
    }

    if (blob->iv != NULL && blob->iv_len > 0)
    {
        char* b64 = bytes2base64(blob->iv, blob->iv_len);
        if (b64 != NULL)
        {
            cJSON_AddStringToObject(root, "zsm_iv", b64);
            free(b64);
        }
    }
}

static bool zsm_blob_from_json(const cJSON* root, ios_zsm_blob_t* blob)
{
    if (root == NULL || blob == NULL) return false;

    const cJSON* key_node = cJSON_GetObjectItemCaseSensitive(root, "zsm_key");
    if (cJSON_IsString(key_node) && key_node->valuestring != NULL &&
        key_node->valuestring[0] != '\0')
    {
        size_t len = 0;
        uint8_t* buf = base642bytes(key_node->valuestring, &len);
        if (buf == NULL)
        {
            LOG_WARN("会话存档的 zsm_key Base64 解码失败");
            return false;
        }
        blob->key = buf;
        blob->key_len = len;
    }

    const cJSON* iv_node = cJSON_GetObjectItemCaseSensitive(root, "zsm_iv");
    if (cJSON_IsString(iv_node) && iv_node->valuestring != NULL &&
        iv_node->valuestring[0] != '\0')
    {
        size_t len = 0;
        uint8_t* buf = base642bytes(iv_node->valuestring, &len);
        if (buf == NULL)
        {
            LOG_WARN("会话存档的 zsm_iv Base64 解码失败");
            if (blob->key) { free(blob->key); blob->key = NULL; blob->key_len = 0; }
            return false;
        }
        blob->iv = buf;
        blob->iv_len = len;
    }

    return true;
}

bool logout_state_save(const prog_status_t* status)
{
    if (status == NULL) return false;

    char path[PATH_MAX + 32];
    if (logout_state_path(path, sizeof(path), status->login_cfg.idx) == false)
    {
        LOG_WARN("无法确定会话存档路径, 本次退出若被强杀将无法补登出");
        return false;
    }

    cJSON* root = cJSON_CreateObject();
    if (root == NULL) return false;

    cJSON_AddBoolToObject(root, "dynamic", status->auth_cfg.dynamic || status->login_cfg.chn == 4 || status->login_cfg.chn == 5);
    cJSON_AddNumberToObject(root, "account", status->login_cfg.idx);
    cJSON_AddStringToObject(root, "user_agent", safe_str(status->login_cfg.user_agent));
    cJSON_AddStringToObject(root, "term_url", safe_str(status->auth_cfg.term_url));
    cJSON_AddStringToObject(root, "algo_id", safe_str(status->auth_cfg.algo_id));
    cJSON_AddStringToObject(root, "client_id", safe_str(status->auth_cfg.client_id));
    cJSON_AddStringToObject(root, "host_name", safe_str(status->auth_cfg.host_name));
    cJSON_AddStringToObject(root, "client_ip", safe_str(status->auth_cfg.client_ip));
    cJSON_AddStringToObject(root, "mac_addr", safe_str(status->auth_cfg.mac_addr));
    cJSON_AddStringToObject(root, "ostag", safe_str(status->auth_cfg.ostag));
    cJSON_AddStringToObject(root, "ticket", safe_str(status->auth_cfg.ticket));
    cJSON_AddNumberToObject(root, "type", status->auth_cfg.type);

    zsm_blob_to_json(root, &status->auth_cfg.blob);

    char* text = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (text == NULL) return false;

    FILE* fp = fopen(path, "w");
    if (fp == NULL)
    {
        LOG_WARN("无法写入会话存档 %s, 本次退出若被强杀将无法补登出", path);
        free(text);
        return false;
    }

    const bool ok = fprintf(fp, "%s", text) > 0;
    fclose(fp);
    free(text);

    if (ok == false)
    {
        LOG_WARN("会话存档写入不完整: %s", path);
        return false;
    }

    LOG_DEBUG("会话现场已存档: %s (被强杀时下次启动会补登出)", path);
    return true;
}

static void read_str(const cJSON* root, const char* key, char* out, const size_t len)
{
    const cJSON* item = cJSON_GetObjectItem(root, key);
    if (item == NULL || cJSON_IsString(item) == false || item->valuestring == NULL) return;

    snprintf(out, len, "%s", item->valuestring);
}

bool logout_state_load(prog_status_t* status)
{
    if (status == NULL) return false;

    char path[PATH_MAX + 32];
    if (logout_state_path(path, sizeof(path), status->login_cfg.idx) == false)
    {
        return false;
    }

    FILE* fp = fopen(path, "r");
    if (fp == NULL)
    {
        return false;
    }

    char data[2048];
    const size_t got = fread(data, 1, sizeof(data) - 1, fp);
    fclose(fp);
    data[got] = '\0';

    cJSON* root = cJSON_Parse(data);
    if (root == NULL)
    {
        LOG_WARN("会话存档解析失败, 按没有存档处理: %s", path);
        return false;
    }

    const cJSON* account = cJSON_GetObjectItem(root, "account");
    if (account == NULL || cJSON_IsNumber(account) == false ||
        (uint8_t)account->valueint != status->login_cfg.idx)
    {
        LOG_WARN("会话存档的账号序号与本次不符, 忽略: %s", path);
        cJSON_Delete(root);
        return false;
    }

    read_str(root, "user_agent", status->login_cfg.user_agent, USER_AGENT_LEN);
    read_str(root, "term_url", status->auth_cfg.term_url, TERM_URL_LEN);
    read_str(root, "algo_id", status->auth_cfg.algo_id, ALGO_ID_LEN);
    read_str(root, "client_id", status->auth_cfg.client_id, CLIENT_ID_LEN);
    read_str(root, "host_name", status->auth_cfg.host_name, HOST_NAME_LEN);
    read_str(root, "client_ip", status->auth_cfg.client_ip, IP_LEN);
    read_str(root, "mac_addr", status->auth_cfg.mac_addr, MAC_ADDR_LEN);
    read_str(root, "ostag", status->auth_cfg.ostag, OSTAG_LEN);
    read_str(root, "ticket", status->auth_cfg.ticket, TICKET_LEN);

    const cJSON* dynamic = cJSON_GetObjectItem(root, "dynamic");
    if (dynamic != NULL && cJSON_IsBool(dynamic))
    {
        status->auth_cfg.dynamic = cJSON_IsTrue(dynamic);
    }

    const cJSON* type = cJSON_GetObjectItem(root, "type");
    if (type != NULL && cJSON_IsNumber(type))
    {
        status->auth_cfg.type = (int8_t)type->valueint;
    }

    if (zsm_blob_from_json(root, &status->auth_cfg.blob) == false)
    {
        LOG_WARN("会话存档的 ZSM key/iv 解码失败: %s", path);
        zsm_blob_free(&status->auth_cfg.blob);
        cJSON_Delete(root);
        return false;
    }

    cJSON_Delete(root);

    if (status->auth_cfg.term_url[0] == '\0' || status->auth_cfg.algo_id[0] == '\0')
    {
        LOG_WARN("会话存档缺少 term_url 或 algo_id, 无法补登出: %s", path);
        zsm_blob_free(&status->auth_cfg.blob);
        return false;
    }

    return true;
}

void logout_state_clear(const uint8_t idx)
{
    char path[PATH_MAX + 32];
    if (logout_state_path(path, sizeof(path), idx) == false) return;

    if (remove(path) == 0)
    {
        LOG_DEBUG("会话存档已清除: %s", path);
    }
}

#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#endif

#include "WebInternal.h"

#include <mongoose/mongoose.h>

#ifndef _WIN32
#include <dirent.h>
#endif

#include "utils/platform/PlatformUtils.h"
#include "utils/text/TextUtils.h"
#include "utils/log/Logger.h"

static const char log_current_name[] = "run.log";

static const char log_suffix[] = ".log";

static const char* week_day_to_str(const int day)
{
    static const char* names[] = {"sun", "mon", "tue", "wed", "thu", "fri", "sat"};
    if (day < 0 || day > 6) return "sun";
    return names[day];
}

void format_week_min(const uint16_t week_min, char* out)
{
    const uint16_t mod = week_min % WEEK_MINUTES;
    const int day = mod / 1440;
    const int hour = (mod % 1440) / 60;
    const int minute = mod % 60;
    snprintf(out, TIME_WINDOW_STR_LEN, "%s %02d:%02d", week_day_to_str(day), hour, minute);
}

/**
 * @brief 检查日志文件名是否安全 (禁止路径穿越)
 * @param name 文件名
 * @return 是否安全
 */
bool is_safe_log_name(const char* name)
{
    if (name == NULL) return false;
    const size_t len = strlen(name);
    if (len == 0 || len >= LOG_NAME_LEN) return false;
    if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) return false;
    for (size_t i = 0; i < len; i++)
    {
        const unsigned char c = (unsigned char)name[i];
        if (isalnum(c) == 0 && c != '.' && c != '_' && c != '-') return false;
    }
    return true;
}

/**
 * @brief 检查文件名是不是日志文件
 *
 * 必须再认一次后缀: 日志目录默认就是【程序所在目录】(配置里的 log_dir),
 * 那里还躺着程序本体 / 配置文件 / portal, 只判"名字安全"的话
 * 日志页会把这些都列成日志, 连明文账号密码所在的 ESurfingClient.json
 * 都能当成日志读出来
 * @param name 文件名
 * @return 是否是日志文件
 */
bool is_log_file_name(const char* name)
{
    if (is_safe_log_name(name) == false) return false;

    const size_t name_len = strlen(name);
    const size_t suffix_len = sizeof(log_suffix) - 1;
    if (name_len <= suffix_len) return false;

    return str_case_cmp(name + name_len - suffix_len, log_suffix) == 0;
}

/**
 * @brief 读取日志目录中的文件列表
 * @param out 输出数组
 * @param max 数组容量
 * @return 文件数量
 */
int list_log_files(log_file_entry_t* out, const int max)
{
    const char* dir = get_logger_dir();
    if (dir == NULL || dir[0] == '\0') return 0;

    int count = 0;

#ifdef _WIN32

    char pattern[PATH_MAX];
    const int pattern_len = snprintf(pattern, sizeof(pattern), "%s%c*", dir, SEP);
    if (pattern_len <= 0 || (size_t)pattern_len >= sizeof(pattern)) return 0;

    WIN32_FIND_DATAA find_data;
    HANDLE handle = FindFirstFileA(pattern, &find_data);
    if (handle == INVALID_HANDLE_VALUE) return 0;
    do
    {
        if ((find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) continue;
        if (count >= max) break;
        if (is_log_file_name(find_data.cFileName) == false) continue;

        snprintf(out[count].name, sizeof(out[count].name), "%s", find_data.cFileName);
        out[count].size = ((uint64_t)find_data.nFileSizeHigh << 32) | (uint64_t)find_data.nFileSizeLow;
        // FILETIME (100 纳秒, 1601 起) -> Unix 时间戳 (秒, 1970 起)
        const uint64_t file_time = ((uint64_t)find_data.ftLastWriteTime.dwHighDateTime << 32) |
            (uint64_t)find_data.ftLastWriteTime.dwLowDateTime;
        out[count].mtime = file_time / 10000000ULL - 11644473600ULL;
        out[count].current = strcmp(find_data.cFileName, log_current_name) == 0;

        char path[PATH_MAX];
        const int path_len = snprintf(path, sizeof(path), "%s%c%s", dir, SEP, find_data.cFileName);
        if (path_len > 0 && (size_t)path_len < sizeof(path))
        {
            win_stat_file(path, &out[count].size, &out[count].mtime);
        }
        count++;
    } while (FindNextFileA(handle, &find_data) != 0);
    FindClose(handle);

#else

    DIR* dir_handle = opendir(dir);
    if (dir_handle == NULL) return 0;

    char path[PATH_MAX];
    struct dirent* entry;
    while ((entry = readdir(dir_handle)) != NULL)
    {
        if (count >= max) break;
        if (is_log_file_name(entry->d_name) == false) continue;

        const int path_len = snprintf(path, sizeof(path), "%s%c%s", dir, SEP, entry->d_name);
        if (path_len <= 0 || (size_t)path_len >= sizeof(path)) continue;

        struct stat st;
        if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) continue;

        snprintf(out[count].name, sizeof(out[count].name), "%s", entry->d_name);
        out[count].size = (uint64_t)st.st_size;
        out[count].mtime = (uint64_t)st.st_mtime;
        out[count].current = strcmp(entry->d_name, log_current_name) == 0;
        count++;
    }
    closedir(dir_handle);

#endif

    return count;
}

/** @brief 排序: 当前日志在最前, 其余按修改时间倒序 */
int cmp_log_files(const void* a, const void* b)
{
    const log_file_entry_t* left = (const log_file_entry_t*)a;
    const log_file_entry_t* right = (const log_file_entry_t*)b;
    if (left->current != right->current) return left->current ? -1 : 1;
    if (left->mtime != right->mtime) return left->mtime > right->mtime ? -1 : 1;
    return -str_case_cmp(left->name, right->name);
}

/**
 * @brief 解析并输出单行 Mongoose 日志 (格式: "%-6llx %d %s:%d:%s ...")
 *
 * 使用栈缓冲与严格边界检查, 避免零碎 malloc 泄漏、空格对齐偏移误判与越界读取。
 */
static void flush_web_log_line(const char* line, const size_t len)
{
    if (len == 0) return;

    const char* end = line + len;
    const char* p = line;

    // 跳过时间戳字段及后续填充空格 (mg_log_prefix 使用 "%-6llx " 会有多个空格)
    while (p < end && *p != ' ') p++;
    while (p < end && *p == ' ') p++;

    // 等级字符 ('1'=ERROR, '2'=INFO, 其余=DEBUG/VERBOSE) 后紧跟单个空格
    if (p + 2 > end || p[1] != ' ')
    {
        LOG_DEBUG("未知的 Web 日志: %s", line);
        return;
    }

    const char level_ch = p[0];
    const char* file_start = p + 2;
    const char* file_end = memchr(file_start, ':', (size_t)(end - file_start));
    if (file_end == NULL || file_end == file_start)
    {
        LOG_DEBUG("未知的 Web 日志: %s", line);
        return;
    }

    const char* line_start = file_end + 1;
    if (line_start >= end)
    {
        LOG_DEBUG("未知的 Web 日志: %s", line);
        return;
    }

    const char* line_end = memchr(line_start, ':', (size_t)(end - line_start));
    if (line_end == NULL || line_end == line_start)
    {
        LOG_DEBUG("未知的 Web 日志: %s", line);
        return;
    }

    char file_buf[128];
    size_t file_len = (size_t)(file_end - file_start);
    if (file_len >= sizeof(file_buf)) file_len = sizeof(file_buf) - 1;
    memcpy(file_buf, file_start, file_len);
    file_buf[file_len] = '\0';

    char line_num_buf[24];
    size_t line_num_len = (size_t)(line_end - line_start);
    if (line_num_len >= sizeof(line_num_buf)) line_num_len = sizeof(line_num_buf) - 1;
    memcpy(line_num_buf, line_start, line_num_len);
    line_num_buf[line_num_len] = '\0';

    const uint32_t file_line = (uint32_t)str2uint64(line_num_buf);
    const char* msg = line_end + 1;

    switch (level_ch)
    {
    case '1':
        LOG_WEB_ERROR(file_buf, file_line, "%s", msg);
        break;
    case '2':
        LOG_WEB_INFO(file_buf, file_line, "%s", msg);
        break;
    default:
        LOG_WEB_TRACE(file_buf, file_line, "%s", msg);
        break;
    }
}

void logFn(const char ch, void* param)
{
    (void)param;
    static char buffer[512];
    static size_t pos = 0;

    if (ch == '\r')
    {
        return;
    }

    if (ch == '\n')
    {
        buffer[pos] = '\0';
        if (pos > 0)
        {
            flush_web_log_line(buffer, pos);
        }
        pos = 0;
        return;
    }

    // 单行超过缓冲长度时截断多余字符, 直到遇到 '\n' 再统一落盘并归零 pos
    if (pos < sizeof(buffer) - 1)
    {
        buffer[pos++] = ch;
    }
}

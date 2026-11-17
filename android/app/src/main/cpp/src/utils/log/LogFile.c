#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#endif

#include "LoggerInternal.h"

#include "core/States.h"
#include "utils/platform/PlatformUtils.h"
#include "utils/text/TextUtils.h"
#include "utils/time/TimeUtils.h"

#include <ctype.h>
#include <inttypes.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef _WIN32
#include <dirent.h>
#endif

static const char s_rotate_file_name[] = ".rotate.log";

#define LOG_ID_CHECK_LINES 32

static uint32_t s_rotate_seq = 0;

/**
 * @brief 获取路径当前的文件身份
 *
 * 设备号 + inode 唯一标识一个文件, 重命名之后路径会指向新的 inode,
 * 据此可以判断自己手上的句柄是否已经落在被轮转掉的旧文件上
 * @param path 文件路径
 * @param dev 设备号 (Windows 为卷序列号)
 * @param ino inode (Windows 为文件索引)
 * @return 是否获取成功
 */
static bool get_file_id(const char* path, uint64_t* dev, uint64_t* ino)
{
#ifdef _WIN32
    HANDLE handle = CreateFileA(path, GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (handle == INVALID_HANDLE_VALUE) return false;

    BY_HANDLE_FILE_INFORMATION info;
    const bool ok = GetFileInformationByHandle(handle, &info) != 0;
    CloseHandle(handle);
    if (ok == false) return false;

    *dev = (uint64_t)info.dwVolumeSerialNumber;
    *ino = ((uint64_t)info.nFileIndexHigh << 32) | (uint64_t)info.nFileIndexLow;
    return true;
#else
    struct stat st;
    if (stat(path, &st) != 0) return false;

    *dev = (uint64_t)st.st_dev;
    *ino = (uint64_t)st.st_ino;
    return true;
#endif
}

/**
 * @brief 以追加方式打开一个日志文件
 * @param path 文件路径
 * @return 文件句柄 (失败返回 NULL)
 */
static FILE* open_log_handle(const char* path)
{
    FILE* handle = fopen(path, "a");
    if (handle == NULL) return NULL;

#ifndef _WIN32
    /**
     * 设成 exec 时自动关闭:
     * 监管者 fork 出子进程时会继承这里的句柄, 而子进程自己还要再开一份,
     * 不关掉的话子进程会一直白占着一个 fd
     * (Windows 侧用 CreateProcess 且不继承句柄, 无需处理)
     */
    const int fd = fileno(handle);
    if (fd >= 0)
    {
        fcntl(fd, F_SETFD, FD_CLOEXEC);
    }
#endif

    return handle;
}

/**
 * @brief 打开日志文件并记录它的身份
 * @return 是否打开成功
 */
bool open_log_file(void)
{
    g_logger_cfg.file_handle = open_log_handle(g_logger_cfg.log_file);
    if (g_logger_cfg.file_handle == NULL) return false;

    g_logger_cfg.cur_lines = 0;
    g_logger_cfg.lines_since_check = 0;
    g_logger_cfg.file_dev = 0;
    g_logger_cfg.file_ino = 0;
    get_file_id(g_logger_cfg.log_file, &g_logger_cfg.file_dev, &g_logger_cfg.file_ino);
    return true;
}

/**
 * @brief 复检日志文件是否已被其它进程轮转
 *
 * 多个进程共用同一个 run.log, 任何一个进程都可能触发轮转,
 * 这里比对自身句柄与路径当前的 inode, 不一致就说明自己已经写到了旧文件上
 * @return 是否重新打开了日志文件
 */
static bool reopen_if_rotated(void)
{
    // 拿不到身份信息时无从比较, 退化为仅按自身行数计数
    if (!g_logger_cfg.file_handle || g_logger_cfg.file_ino == 0) return false;

    uint64_t dev = 0;
    uint64_t ino = 0;
    if (get_file_id(g_logger_cfg.log_file, &dev, &ino) == false) return false;
    if (dev == g_logger_cfg.file_dev && ino == g_logger_cfg.file_ino) return false;

    // 这里不能用 LOG_*, 会递归回到 log_out
    fprintf(stderr, "[INFO] 日志文件已被轮转, 重新打开: %s\n", g_logger_cfg.log_file);

    fclose(g_logger_cfg.file_handle);
    g_logger_cfg.file_handle = NULL;
    if (open_log_file() == false)
    {
        fprintf(stderr, "[ERROR] 轮转后无法重新打开日志文件 %s\n", g_logger_cfg.log_file);
        return false;
    }
    return true;
}

/**
 * @brief 日志轮转
 *
 * 轮转是"无主"的: 任何进程都可以发起, 并发安全由 rename 的原子性保证.
 * 同时发起时只有一个进程的 rename 会成功, 其余进程拿到失败,
 * 把失败直接当作"已被其它进程轮转"处理即可, 因此不需要锁或额外的协调
 */
void rotate(void)
{
    if (!g_logger_cfg.file_handle || strlen(g_logger_cfg.log_file) == 0) return;

    if (g_logger_cfg.cur_lines < g_logger_cfg.max_lines)
    {
        // 未到阈值, 只按固定间隔复检一次身份, 避免每写一行都 stat
        if (g_logger_cfg.lines_since_check < LOG_ID_CHECK_LINES) return;
        g_logger_cfg.lines_since_check = 0;
        reopen_if_rotated();
        return;
    }

    /**
     * 到阈值了, 必须先确认自己没有写在旧文件上:
     * 否则会把别的进程刚轮转出来的新 run.log 再轮转一次
     */
    if (reopen_if_rotated() || g_logger_cfg.file_handle == NULL) return;

    char cur_tm[32];
    get_fmt_time(cur_tm, FILE_FORMAT);
    char rotate_file_name[LOG_PATH_MAX];
#ifdef _WIN32
    const unsigned long proc_id = (unsigned long)GetCurrentProcessId();
#else
    const unsigned long proc_id = (unsigned long)getpid();
#endif
    /**
     * 文件名带上进程号与本进程的轮转序号:
     * 时间戳只有秒级精度, 多个进程可能在同一秒内各自轮转,
     * 只靠时间戳必然重名, 而 rename 会覆盖同名目标, 那样一次就会丢掉一整份日志
     */
    const uint16_t result = snprintf(rotate_file_name, sizeof(rotate_file_name), "%s%c%s-%lu-%" PRIu32 "%s",
        safe_str(g_logger_cfg.log_dir), SEP, safe_str(cur_tm), proc_id, s_rotate_seq, s_rotate_file_name);
    s_rotate_seq++;
    if (result >= (uint16_t)sizeof(rotate_file_name))
    {
        fprintf(stderr, "[ERROR] 轮转的文件名过长 (最大 %zu)\n", sizeof(rotate_file_name) - 1);
        g_logger_cfg.cur_lines = 0;
        return;
    }

    // Windows 无法重命名一个仍被自己打开的文件, 所以先关闭再改名
    fclose(g_logger_cfg.file_handle);
    g_logger_cfg.file_handle = NULL;

    /**
     * 关闭之后再确认一次: 关闭与重命名之间仍有窗口, 期间可能已被其它进程轮转.
     * 不确认的话会把别的进程刚建好的新 run.log 改名走 (rename 会覆盖同名目标)
     */
    uint64_t dev = 0;
    uint64_t ino = 0;
    if (get_file_id(g_logger_cfg.log_file, &dev, &ino) == false ||
        dev != g_logger_cfg.file_dev || ino != g_logger_cfg.file_ino)
    {
        if (open_log_file() == false)
        {
            fprintf(stderr, "[ERROR] 轮转后无法重新打开日志文件 %s\n", g_logger_cfg.log_file);
        }
        return;
    }

    const bool renamed = (rename(g_logger_cfg.log_file, rotate_file_name) == 0);
    if (!renamed)
    {
        // 多半是已被其它进程抢先轮转, 属于正常竞争
        fprintf(stderr, "[INFO] 日志轮转未生效 (可能已被其它进程轮转): %s\n", g_logger_cfg.log_file);
    }

    if (open_log_file() == false)
    {
        fprintf(stderr, "[ERROR] 轮转后无法重新打开日志文件 %s\n", g_logger_cfg.log_file);
    }

    if (renamed)
    {
        prune_old_logs();
    }
}

#define LOG_ARCHIVE_NAME_MAX 256
#define LOG_NTP_MIN_VALID_SEC 1700000000ULL

typedef struct
{
    char name[LOG_ARCHIVE_NAME_MAX];
    uint64_t size;
    uint64_t mtime;
} archive_log_entry_t;

/**
 * @brief 严格校验文件名是否为可清理的历史归档日志 (绝对排除 run.log 与非 .log 文件)
 */
static bool is_archived_log_name(const char* name)
{
    if (name == NULL) return false;

    const size_t len = strlen(name);
    if (len <= 4 || len >= LOG_ARCHIVE_NAME_MAX) return false;
    if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) return false;

    for (size_t i = 0; i < len; i++)
    {
        const unsigned char c = (unsigned char)name[i];
        if (isalnum(c) == 0 && c != '.' && c != '_' && c != '-') return false;
    }

    if (str_ieq(name + len - 4, ".log") == false) return false;

#ifdef _WIN32
    if (str_ieq(name, g_log_file_name)) return false;
#else
    if (strcmp(name, g_log_file_name) == 0) return false;
#endif
    return true;
}

static int cmp_archive_desc(const void* a, const void* b)
{
    const archive_log_entry_t* left = (const archive_log_entry_t*)a;
    const archive_log_entry_t* right = (const archive_log_entry_t*)b;
    if (left->mtime != right->mtime)
    {
        return (left->mtime > right->mtime) ? -1 : 1;
    }
    const int cmp = strcmp(left->name, right->name);
    return (cmp > 0) ? -1 : (cmp < 0 ? 1 : 0);
}

static bool append_archive_entry(archive_log_entry_t** items, size_t* count, size_t* cap,
    const char* name, const uint64_t size, const uint64_t mtime)
{
    if (*count >= *cap)
    {
        const size_t new_cap = (*cap == 0) ? 16 : (*cap * 2);
        archive_log_entry_t* grown = realloc(*items, new_cap * sizeof(archive_log_entry_t));
        if (grown == NULL) return false;
        *items = grown;
        *cap = new_cap;
    }

    archive_log_entry_t* dst = &(*items)[*count];
    snprintf(dst->name, sizeof(dst->name), "%s", name);
    dst->size = size;
    dst->mtime = mtime;
    (*count)++;
    return true;
}

/**
 * @brief 收集日志目录下的所有合法历史归档普通文件 (严禁跟随软链接/目录)
 */
static bool collect_archived_logs(const char* dir, archive_log_entry_t** out_items, size_t* out_count)
{
    *out_items = NULL;
    *out_count = 0;

    archive_log_entry_t* items = NULL;
    size_t count = 0;
    size_t cap = 0;

#ifdef _WIN32
    char pattern[LOG_PATH_MAX];
    const int pattern_len = snprintf(pattern, sizeof(pattern), "%s%c*", dir, SEP);
    if (pattern_len <= 0 || (size_t)pattern_len >= sizeof(pattern)) return false;

    WIN32_FIND_DATAA find_data;
    HANDLE handle = FindFirstFileA(pattern, &find_data);
    if (handle == INVALID_HANDLE_VALUE)
    {
        return GetLastError() == ERROR_FILE_NOT_FOUND;
    }

    bool ok = true;
    do
    {
        if ((find_data.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0)
        {
            continue;
        }
        if (is_archived_log_name(find_data.cFileName) == false) continue;

        char path[LOG_PATH_MAX];
        const int path_len = snprintf(path, sizeof(path), "%s%c%s", dir, SEP, find_data.cFileName);
        if (path_len <= 0 || (size_t)path_len >= sizeof(path)) continue;

        const uint64_t size = ((uint64_t)find_data.nFileSizeHigh << 32) | (uint64_t)find_data.nFileSizeLow;
        const uint64_t ft = ((uint64_t)find_data.ftLastWriteTime.dwHighDateTime << 32) |
            (uint64_t)find_data.ftLastWriteTime.dwLowDateTime;
        const uint64_t mtime = (ft >= 116444736000000000ULL) ? ((ft - 116444736000000000ULL) / 10000000ULL) : 0;

        if (append_archive_entry(&items, &count, &cap, find_data.cFileName, size, mtime) == false)
        {
            ok = false;
            break;
        }
    } while (FindNextFileA(handle, &find_data) != 0);

    FindClose(handle);
    if (ok == false)
    {
        free(items);
        return false;
    }
#else
    DIR* dir_handle = opendir(dir);
    if (dir_handle == NULL) return false;

    bool ok = true;
    struct dirent* entry;
    while ((entry = readdir(dir_handle)) != NULL)
    {
        if (is_archived_log_name(entry->d_name) == false) continue;

        char path[LOG_PATH_MAX];
        const int path_len = snprintf(path, sizeof(path), "%s%c%s", dir, SEP, entry->d_name);
        if (path_len <= 0 || (size_t)path_len >= sizeof(path)) continue;

        struct stat st;
        if (lstat(path, &st) != 0 || !S_ISREG(st.st_mode)) continue;

        const uint64_t size = (st.st_size > 0) ? (uint64_t)st.st_size : 0;
        const uint64_t mtime = (st.st_mtime > 0) ? (uint64_t)st.st_mtime : 0;

        if (append_archive_entry(&items, &count, &cap, entry->d_name, size, mtime) == false)
        {
            ok = false;
            break;
        }
    }

    closedir(dir_handle);
    if (ok == false)
    {
        free(items);
        return false;
    }
#endif

    *out_items = items;
    *out_count = count;
    return true;
}

void prune_old_logs(void)
{
    if (g_query_mode || g_list_only) return;

    const char* dir = get_logger_dir();
    if (dir == NULL || dir[0] == '\0') return;

    archive_log_entry_t* items = NULL;
    size_t count = 0;
    if (collect_archived_logs(dir, &items, &count) == false || count == 0)
    {
        free(items);
        return;
    }

    const time_t raw_now = time(NULL);
    const uint64_t now_sec = (raw_now > 0) ? (uint64_t)raw_now : 0;
    const bool check_days = (g_log_max_days > 0 && now_sec >= LOG_NTP_MIN_VALID_SEC);
    const uint64_t max_age_sec = check_days ? ((uint64_t)g_log_max_days * 86400ULL) : 0;

    size_t remain = 0;
    for (size_t i = 0; i < count; i++)
    {
        if (check_days && items[i].mtime > 0 && now_sec > items[i].mtime &&
            (now_sec - items[i].mtime) > max_age_sec)
        {
            char path[LOG_PATH_MAX];
            const int n = snprintf(path, sizeof(path), "%s%c%s", dir, SEP, items[i].name);
            if (n > 0 && (size_t)n < sizeof(path))
            {
                remove(path);
            }
            continue;
        }
        if (remain != i) items[remain] = items[i];
        remain++;
    }

    if (remain > 1)
    {
        qsort(items, remain, sizeof(archive_log_entry_t), cmp_archive_desc);
    }

    const long max_files = (g_log_max_files >= 0) ? g_log_max_files : DEFAULT_LOG_MAX_FILES;
    const uint64_t max_total_bytes = (uint64_t)DEFAULT_LOG_MAX_TOTAL_MB * 1024ULL * 1024ULL;
    size_t kept_files = 0;
    uint64_t kept_bytes = 0;
    bool budget_exhausted = false;

    for (size_t i = 0; i < remain; i++)
    {
        bool should_delete = false;
        if (budget_exhausted || (long)kept_files >= max_files)
        {
            should_delete = true;
        }
        else if (items[i].size > max_total_bytes || kept_bytes + items[i].size > max_total_bytes)
        {
            should_delete = true;
            budget_exhausted = true;
        }
        else
        {
            kept_files++;
            kept_bytes += items[i].size;
        }

        if (should_delete)
        {
            char path[LOG_PATH_MAX];
            const int n = snprintf(path, sizeof(path), "%s%c%s", dir, SEP, items[i].name);
            if (n > 0 && (size_t)n < sizeof(path))
            {
                remove(path);
            }
        }
    }

    free(items);
}

bool clear_logs(const bool clear_current, uint32_t* deleted_files, uint64_t* freed_bytes)
{
    if (deleted_files != NULL) *deleted_files = 0;
    if (freed_bytes != NULL) *freed_bytes = 0;

    const char* dir = get_logger_dir();
    if (dir == NULL || dir[0] == '\0') return false;

    archive_log_entry_t* items = NULL;
    size_t count = 0;
    if (collect_archived_logs(dir, &items, &count) == false)
    {
        return false;
    }

    uint32_t removed_cnt = 0;
    uint64_t total_freed = 0;
    bool ok = true;

    for (size_t i = 0; i < count; i++)
    {
        char path[LOG_PATH_MAX];
        const int n = snprintf(path, sizeof(path), "%s%c%s", dir, SEP, items[i].name);
        if (n <= 0 || (size_t)n >= sizeof(path)) continue;

        if (remove(path) == 0)
        {
            removed_cnt++;
            total_freed += items[i].size;
        }
        else
        {
#ifdef _WIN32
            if (GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES) ok = false;
#else
            struct stat st;
            if (lstat(path, &st) == 0) ok = false;
#endif
        }
    }
    free(items);

    if (clear_current)
    {
        char run_log_path[LOG_PATH_MAX];
        logger_lock();
        if (g_logger_cfg.log_file[0] != '\0')
        {
            snprintf(run_log_path, sizeof(run_log_path), "%s", g_logger_cfg.log_file);
        }
        else
        {
            snprintf(run_log_path, sizeof(run_log_path), "%s%c%s", dir, SEP, g_log_file_name);
        }

#ifdef _WIN32
        HANDLE h = CreateFileA(run_log_path, GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (h != INVALID_HANDLE_VALUE)
        {
            LARGE_INTEGER sz;
            if (GetFileSizeEx(h, &sz) && sz.QuadPart > 0)
            {
                total_freed += (uint64_t)sz.QuadPart;
            }
            LARGE_INTEGER zero = {0};
            if (SetFilePointerEx(h, zero, NULL, FILE_BEGIN) && SetEndOfFile(h))
            {
                g_logger_cfg.cur_lines = 0;
                g_logger_cfg.lines_since_check = 0;
            }
            else
            {
                ok = false;
            }
            CloseHandle(h);
        }
        else if (GetLastError() == ERROR_FILE_NOT_FOUND)
        {
            g_logger_cfg.cur_lines = 0;
            g_logger_cfg.lines_since_check = 0;
        }
        else
        {
            ok = false;
        }
#else
        struct stat st;
        if (lstat(run_log_path, &st) == 0)
        {
            if (S_ISREG(st.st_mode))
            {
                if (st.st_size > 0)
                {
                    total_freed += (uint64_t)st.st_size;
                }
                if (truncate(run_log_path, 0) == 0)
                {
                    g_logger_cfg.cur_lines = 0;
                    g_logger_cfg.lines_since_check = 0;
                }
                else
                {
                    ok = false;
                }
            }
            else
            {
                ok = false;
            }
        }
        else if (errno == ENOENT)
        {
            g_logger_cfg.cur_lines = 0;
            g_logger_cfg.lines_since_check = 0;
        }
        else
        {
            ok = false;
        }
#endif
        logger_unlock();
    }

    if (deleted_files != NULL) *deleted_files = removed_cnt;
    if (freed_bytes != NULL) *freed_bytes = total_freed;

    LOG_INFO("已手动清理日志 (删除归档 %" PRIu32 " 个, 释放 %" PRIu64 " 字节)", removed_cnt, total_freed);
    return ok;
}

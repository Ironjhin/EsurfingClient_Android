#include "utils/PlatformUtils.h"
#include "utils/Logger.h"

#include <sys/stat.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <fcntl.h>
#include <errno.h>
#include <pthread.h>
#include <dirent.h>

#ifdef _WIN32
#include <windows.h>
#endif

static const char s_file_name[] = "run.log";
static const char s_rotate_file_name[] = ".rotate.log";

char g_sandbox_path[PATH_MAX] = {0};

static pthread_mutex_t s_log_mutex = PTHREAD_MUTEX_INITIALIZER;

static log_cfg_t s_logger_cfg = {
    .lv = LOG_LEVEL_INFO,
    .log_dir = "",
    .log_file = "",
    .file_handle = NULL,
    .max_lines = 1000,
    .cur_lines = 0
};

static const char* get_level_str(const LogLevel lv)
{
    switch (lv)
    {
    case LOG_LEVEL_VERBOSE: return "VERBOSE";
    case LOG_LEVEL_DEBUG:   return "DEBUG";
    case LOG_LEVEL_INFO:    return "INFO";
    case LOG_LEVEL_WARN:    return "WARN";
    case LOG_LEVEL_ERROR:   return "ERROR";
    case LOG_LEVEL_FATAL:   return "FATAL";
    default:                return "UNKNOWN";
    }
}

/* 轮转后保留的 rotate 文件数量上限 */
#define KEEP_ROTATE_FILES 3

/* 删除超量的旧 rotate 文件，只保留最近的 KEEP_ROTATE_FILES 个 */
static void cleanup_old_rotates()
{
    if (strlen(s_logger_cfg.log_dir) == 0) return;

    DIR* dir = opendir(s_logger_cfg.log_dir);
    if (!dir) return;

    /* 收集所有 rotate 文件名 */
    const size_t suffix_len = strlen(s_rotate_file_name); /* ".rotate.log" */
    char* names[64] = {0};
    int count = 0;
    struct dirent* ent;
    while ((ent = readdir(dir)) != NULL && count < 64)
    {
        size_t len = strlen(ent->d_name);
        if (len > suffix_len && strcmp(ent->d_name + len - suffix_len, s_rotate_file_name) == 0)
        {
            names[count] = strdup(ent->d_name);
            if (names[count]) count++;
        }
    }
    closedir(dir);

    if (count <= KEEP_ROTATE_FILES)
    {
        /* 数量未超限，无需清理 */
        for (int i = 0; i < count; i++) free(names[i]);
        return;
    }

    /* 按文件名排序（时间戳前缀 ⇒ 字典序 = 时间序，最新的在末尾） */
    for (int i = 1; i < count; i++)
    {
        char* key = names[i];
        int j = i - 1;
        while (j >= 0 && strcmp(names[j], key) > 0)
        {
            names[j + 1] = names[j];
            j--;
        }
        names[j + 1] = key;
    }

    /* 删除最旧的，只保留最近 KEEP_ROTATE_FILES 个 */
    for (int i = 0; i < count - KEEP_ROTATE_FILES; i++)
    {
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s%c%s", s_logger_cfg.log_dir, SEP, names[i]);
        remove(path);
        free(names[i]);
    }
    for (int i = count - KEEP_ROTATE_FILES; i < count; i++) free(names[i]);
}

static void rotate()
{
    if (!s_logger_cfg.file_handle || strlen(s_logger_cfg.log_file) == 0 || s_logger_cfg.cur_lines < s_logger_cfg.max_lines) return;
    fclose(s_logger_cfg.file_handle);
    s_logger_cfg.file_handle = NULL;
    char cur_tm[32];
    get_fmt_time(cur_tm, FILE_FORMAT);
    char rotate_file_name[PATH_MAX];
    const uint16_t result = snprintf(rotate_file_name, sizeof(rotate_file_name), "%s%c%s%s", safe_str(s_logger_cfg.log_dir), SEP, safe_str(cur_tm), s_rotate_file_name);
    if (result >= (uint16_t)sizeof(rotate_file_name))
    {
        fprintf(stderr, "[ERROR] 轮转的文件名过长 (最大 %zu)\n", sizeof(rotate_file_name) - 1);
        s_logger_cfg.file_handle = fopen(s_logger_cfg.log_file, "a");
        return;
    }
    rename(s_logger_cfg.log_file, rotate_file_name);
    s_logger_cfg.cur_lines = 0;
    s_logger_cfg.file_handle = fopen(s_logger_cfg.log_file, "a");
    if (s_logger_cfg.file_handle == NULL) fprintf(stderr, "[ERROR] 无法在轮转后重新打开日志文件 %s\n", s_logger_cfg.log_file);

    /* 轮转完成后清理超量的旧 rotate 文件，防止磁盘无限增长 */
    cleanup_old_rotates();
}

void set_log_dir(const char* dir)
{
    if (dir)
    {
        strncpy(g_sandbox_path, dir, sizeof(g_sandbox_path) - 1);
        g_sandbox_path[sizeof(g_sandbox_path) - 1] = '\0';
    }
}

static bool get_log_dir(char* out)
{
    /* 优先使用通过 set_log_dir() 注入的沙盒路径（Android 私有目录） */
    if (strlen(g_sandbox_path) > 0)
    {
        const uint16_t len = snprintf(out, PATH_MAX, "%s", safe_str(g_sandbox_path));
        if ((size_t)len >= PATH_MAX) return false;
        return true;
    }
#ifdef _WIN32
    char dir[PATH_MAX];
    if (get_exec_dir(dir) == false) return false;
    const uint16_t len = snprintf(out, PATH_MAX, "%s%clogs", safe_str(dir), SEP);
    if ((size_t)len >= PATH_MAX) return false;
    if (!CreateDirectoryA(out, NULL))
    {
        const DWORD err = GetLastError();
        if (err != ERROR_ALREADY_EXISTS) return false;
    }
#else
    const char dir[] = "/var/log/esurfing";
    const uint16_t len = snprintf(out, PATH_MAX, "%s%clogs", dir, SEP);
    if ((size_t)len >= PATH_MAX) return false;
    struct stat st;
    if (stat(out, &st) != 0)
    {
        if (mkdir("/var", 0755) != 0 && errno != EEXIST) return false;
        if (mkdir("/var/log", 0755) != 0 && errno != EEXIST) return false;
        if (mkdir(dir, 0755) != 0 && errno != EEXIST) return false;
        if (mkdir(out, 0755) != 0 && errno != EEXIST) return false;
    }
    else if (!S_ISDIR(st.st_mode)) return false;
#endif
    return true;
}

static void write_2_console(const char* msg)
{
    printf("%s", msg);
    fflush(stdout);
}

static void write_2_file(const char* msg)
{
    if (s_logger_cfg.file_handle)
    {
        fprintf(s_logger_cfg.file_handle, "%s", msg);
        fflush(s_logger_cfg.file_handle);
    }
}

static char* get_thread_str()
{
    for (uint8_t i = 0; i < g_prog_cnt; i++)
    {
        if (sim_thread_cur_id() == g_prog_status[i].thread_id)
        {
            static char str[4];
            snprintf(str, sizeof(str), "%" PRIu8, i);
            return str;
        }
    }
    if (tl_thread_idx == -1)
    {
        return "Main";
    }
    return "WebServer";
}

void log_out(const LogLevel level, const char* file, const uint32_t line, const char* fmt, ...)
{
    if (level > s_logger_cfg.lv) return;
    if (!s_logger_cfg.file_handle)
    {
        fprintf(stderr, "[ERROR] 日志系统未打开, 无法输出日志\n");
        return;
    }
    va_list local_args;
    char ts[32];
    char msg[2048];
    char final_msg[2560];
    get_fmt_time(ts, CONSOLE_FORMAT);
    va_start(local_args, fmt);
    vsnprintf(msg, sizeof(msg), fmt, local_args);
    va_end(local_args);
    snprintf(final_msg, sizeof(final_msg),
        "[%s] [TID %" PRIu64 "] [T-%s] [%s] [%s:%d] %s\n",
        safe_str(ts),
        sim_thread_cur_id(),
        get_thread_str(),
        get_level_str(level),
        strrchr(file, '/') ? strrchr(file, '/') + 1 : strrchr(file, '\\') ? strrchr(file, '\\') + 1 : file,
        line,
        safe_str(msg));
    write_2_console(final_msg);
    write_2_file(final_msg);
    s_logger_cfg.cur_lines++;
    rotate();
}

LogLevel get_logger_level()
{
    return s_logger_cfg.lv;
}

void set_logger_level(const LogLevel lv)
{
    if (s_logger_cfg.lv != lv)
    {
        s_logger_cfg.lv = lv;
        LOG_INFO("设置日志等级为 [%s]", get_level_str(lv));
    }
}

bool init_logger()
{
    if (get_log_dir(s_logger_cfg.log_dir) == false)
    {
        fprintf(stderr, "[ERROR] 无法准备日志目录\n");
        return false;
    }
    const uint16_t len = snprintf(s_logger_cfg.log_file, sizeof(s_logger_cfg.log_file), "%s%c%s", safe_str(s_logger_cfg.log_dir), SEP, s_file_name);
    if ((size_t)len >= sizeof(s_logger_cfg.log_file))
    {
        fprintf(stderr, "[ERROR] 日志文件路径太长 (最大 %zu)\n", sizeof(s_logger_cfg.log_file));
        return false;
    }
    s_logger_cfg.file_handle = fopen(s_logger_cfg.log_file, "a");
    if (!s_logger_cfg.file_handle)
    {
        fprintf(stderr, "[ERROR] 无法打开日志文件 %s, 如果是 Linux 系统请使用 sudo 运行程序\n", s_logger_cfg.log_file);
        return false;
    }
    LOG_DEBUG("日志系统初始化完成");
    LOG_DEBUG("日志等级: %s", get_level_str(s_logger_cfg.lv));
    return true;
}

void clear_log_file(void)
{
    pthread_mutex_lock(&s_log_mutex);

    if (strlen(s_logger_cfg.log_file) == 0 || s_logger_cfg.file_handle == NULL)
    {
        pthread_mutex_unlock(&s_log_mutex);
        return;
    }

    fclose(s_logger_cfg.file_handle);
    s_logger_cfg.file_handle = NULL;

    /* 以 "w" 模式打开即截断为零字节 */
    FILE* tmp = fopen(s_logger_cfg.log_file, "w");
    if (tmp) fclose(tmp);

    /* 恢复追加写入 */
    s_logger_cfg.file_handle = fopen(s_logger_cfg.log_file, "a");
    if (!s_logger_cfg.file_handle)
    {
        fprintf(stderr, "[ERROR] 清空日志后重新打开文件失败\n");
    }
    s_logger_cfg.cur_lines = 0;

    pthread_mutex_unlock(&s_log_mutex);
}

const char* get_log_file_path(void)
{
    return s_logger_cfg.log_file;
}

size_t read_full_log(char** out)
{
    *out = NULL;
    if (strlen(s_logger_cfg.log_dir) == 0) return 0;

    /* 1. 收集所有 rotate 文件名并按时间排序（旧 → 新） */
    const size_t suffix_len = strlen(s_rotate_file_name);
    char* names[64] = {0};
    int count = 0;
    DIR* dir = opendir(s_logger_cfg.log_dir);
    if (!dir) return 0;
    struct dirent* ent;
    while ((ent = readdir(dir)) != NULL && count < 64)
    {
        size_t len = strlen(ent->d_name);
        if (len > suffix_len && strcmp(ent->d_name + len - suffix_len, s_rotate_file_name) == 0)
        {
            names[count] = strdup(ent->d_name);
            if (names[count]) count++;
        }
    }
    closedir(dir);

    /* 按文件名排序（时间戳前缀 ⇒ 字典序 = 时间序） */
    for (int i = 1; i < count; i++)
    {
        char* key = names[i];
        int j = i - 1;
        while (j >= 0 && strcmp(names[j], key) > 0)
        {
            names[j + 1] = names[j];
            j--;
        }
        names[j + 1] = key;
    }

    /* 2. 计算总大小：所有 rotate 文件 + 当前 run.log */
    size_t total_size = 0;
    for (int i = 0; i < count; i++)
    {
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s%c%s", s_logger_cfg.log_dir, SEP, names[i]);
        struct stat st;
        if (stat(path, &st) == 0 && st.st_size > 0) total_size += (size_t)st.st_size;
    }
    struct stat st;
    if (stat(s_logger_cfg.log_file, &st) == 0 && st.st_size > 0) total_size += (size_t)st.st_size;

    if (total_size == 0)
    {
        for (int i = 0; i < count; i++) free(names[i]);
        return 0;
    }

    /* 3. 一次性分配缓冲区（+1 用于结尾 \0） */
    char* buf = (char*)malloc(total_size + 1);
    if (!buf)
    {
        for (int i = 0; i < count; i++) free(names[i]);
        return 0;
    }

    /* 4. 依次读取：rotate 文件（旧 → 新） + 当前 run.log */
    size_t pos = 0;
    for (int i = 0; i < count; i++)
    {
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s%c%s", s_logger_cfg.log_dir, SEP, names[i]);
        FILE* fp = fopen(path, "r");
        if (fp)
        {
            pos += fread(buf + pos, 1, total_size - pos, fp);
            fclose(fp);
        }
        free(names[i]);
    }
    FILE* fp = fopen(s_logger_cfg.log_file, "r");
    if (fp)
    {
        pos += fread(buf + pos, 1, total_size - pos, fp);
        fclose(fp);
    }
    buf[pos] = '\0';

    *out = buf;
    return pos;
}

void clean_logger()
{
    LOG_DEBUG("关闭日志系统");
    if (!s_logger_cfg.file_handle)
    {
        fprintf(stderr, "[ERROR] 日志系统未启动\n");
        return;
    }
    fclose(s_logger_cfg.file_handle);
    s_logger_cfg.file_handle = NULL;
    if (strlen(s_logger_cfg.log_file) == 0)
    {
        fprintf(stderr, "[ERROR] 日志路径为空\n");
        return;
    }
    char cur_tm[32];
    get_fmt_time(cur_tm, FILE_FORMAT);
    char new_file_name[PATH_MAX];
    snprintf(new_file_name, sizeof(new_file_name), "%s%c%s.log", safe_str(s_logger_cfg.log_dir), SEP, safe_str(cur_tm));
    rename(s_logger_cfg.log_file, new_file_name);
}

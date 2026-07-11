#ifndef ESURFINGCLIENT_LOGGER_H
#define ESURFINGCLIENT_LOGGER_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#ifndef PATH_MAX
#define PATH_MAX 260
#endif

typedef enum {
    LOG_LEVEL_NONE = 0,
    LOG_LEVEL_FATAL = 1,
    LOG_LEVEL_ERROR = 2,
    LOG_LEVEL_WARN  = 3,
    LOG_LEVEL_INFO  = 4,
    LOG_LEVEL_DEBUG = 5,
    LOG_LEVEL_VERBOSE = 6
} LogLevel;

typedef struct {
    LogLevel    lv;
    char        log_dir[PATH_MAX];
    char        log_file[PATH_MAX];
    FILE*       file_handle;
    size_t      max_lines;
    size_t      cur_lines;
} log_cfg_t;

#define LOG_VERBOSE(fmt, ...) \
log_out(LOG_LEVEL_VERBOSE, __FILE__, __LINE__, fmt, ##__VA_ARGS__)

#define LOG_DEBUG(fmt, ...) \
log_out(LOG_LEVEL_DEBUG, __FILE__, __LINE__, fmt, ##__VA_ARGS__)

#define LOG_INFO(fmt, ...) \
log_out(LOG_LEVEL_INFO, __FILE__, __LINE__, fmt, ##__VA_ARGS__)

#define LOG_WARN(fmt, ...) \
log_out(LOG_LEVEL_WARN, __FILE__, __LINE__, fmt, ##__VA_ARGS__)

#define LOG_ERROR(fmt, ...) \
log_out(LOG_LEVEL_ERROR, __FILE__, __LINE__, fmt, ##__VA_ARGS__)

#define LOG_FATAL(fmt, ...) \
log_out(LOG_LEVEL_FATAL, __FILE__, __LINE__, fmt, ##__VA_ARGS__)

#define LOG_WEB_VERBOSE(file, line, fmt, ...) \
log_out(LOG_LEVEL_VERBOSE, file, line, fmt, ##__VA_ARGS__)

#define LOG_WEB_INFO(file, line, fmt, ...) \
log_out(LOG_LEVEL_INFO, file, line, fmt, ##__VA_ARGS__)

#define LOG_WEB_ERROR(file, line, fmt, ...) \
log_out(LOG_LEVEL_ERROR, file, line, fmt, ##__VA_ARGS__)

/**
 * @brief 打印日志
 * @param level 日志等级
 * @param file 调用的源代码文件名
 * @param line 执行该函数的行数
 * @param fmt 格式
 * @param ... 其它参数
 */
void log_out(LogLevel level, const char* file, uint32_t line, const char* fmt, ...);

/**
 * @brief 获取当前日志等级
 * @return 日志等级
 */
LogLevel get_logger_level();

/**
 * @brief 设置日志等级
 * @param lv 日志等级
 */
void set_logger_level(LogLevel lv);

/**
 * @brief 设置日志沙盒路径（Android 私有数据目录）
 * @param dir 沙盒目录路径，会在此目录下创建 run.log
 */
void set_log_dir(const char* dir);

/**
 * @brief 初始化日志系统
 * @return 初始化状态
 */
bool init_logger();

/**
 * @brief 清理日志系统
 */
void clean_logger();

/**
 * @brief 物理截断日志文件为零字节（线程安全）
 *
 * 在互斥锁保护下关闭当前文件句柄，以 "w" 模式重新打开以清空内容，
 * 再以 "a" 模式重开恢复追加写入。由于在同进程 C 层内部操作，
 * 持有文件句柄的源线程不会遭遇权限拒绝。
 */
void clear_log_file(void);

/**
 * @brief 获取当前日志文件的绝对路径
 * @return 指向内部 log_file 缓冲区的只读指针（如 /data/adb/esurfing/run.log）；
 *         日志系统未初始化时返回空字符串 ""，调用方无需 free。
 */
const char* get_log_file_path(void);

#endif //ESURFINGCLIENT_LOGGER_H

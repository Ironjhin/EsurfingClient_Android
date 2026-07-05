#include "DialerClient.h"
#include "utils/Logger.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>

#define PID_FILE "/data/adb/esurfing/esurfingd.pid"
#define DATA_DIR "/data/adb/esurfing"

static void write_pid()
{
    FILE* f = fopen(PID_FILE, "w");
    if (f) {
        fprintf(f, "%d", getpid());
        fclose(f);
    }
}

static void remove_pid()
{
    remove(PID_FILE);
}

int main(int argc, char* argv[])
{
    // Parse args
    if (argc > 1 && (strcmp(argv[1], "-v") == 0 || strcmp(argv[1], "--version") == 0)) {
        printf("esurfingd 1.0.0\n");
        return 0;
    }

    // Ensure data directory exists
    mkdir(DATA_DIR, 0755);

    // Switch to data directory so relative paths (e.g. "portal" in WebServer.c) resolve correctly
    chdir(DATA_DIR);

    // Set log directory BEFORE work() calls init_logger()
    set_log_dir(DATA_DIR);
    // Write PID file (removed by shut() -> exit() via atexit/cleanup)
    write_pid();

    // work() handles: signal hooks, logger init, web server start, config load,
    // dialer thread creation, and the supervisor loop.
    // It only returns on g_thread_keep_alive == false (shutdown).
    extern void work(void);
    work();

    // Should not reach here — work() calls shut() which calls exit().
    remove_pid();
    return 0;
}

/*
 * daemon_manager.c — TieJia v2.0.0 Daemon Manager
 *
 * Replaces the shell-based sleep-coordination + watchdog with a native C
 * process manager featuring:
 *   - Priority/DAG-based launch order
 *   - Configurable per-daemon launch delays
 *   - Health monitoring via waitpid() + periodic check
 *   - Auto-restart with exponential backoff (max 5 restarts / 10 min)
 *   - Structured logging to logcat (TieJiaDaemon tag) and/or file
 *
 * Build (standalone, no external deps except libc):
 *   $ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang \
 *       -static -o daemon_manager daemon_manager.c
 *
 * Config file: $MODDIR/daemon.conf (see daemon.conf for format)
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <sys/utsname.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <errno.h>
#include <time.h>
#include <fcntl.h>

#define MAX_DAEMONS     32
#define MAX_LINE        512
#define MAX_PATH        512
#define MAX_ARGS        64
#define BACKOFF_BASE    2      /* seconds */
#define BACKOFF_MAX     300    /* 5 minutes */
#define MAX_RESTARTS    5
#define RESTART_WINDOW  600    /* 10 minutes */
#define HEALTH_INTERVAL 30     /* seconds between health checks */

/* ---- data structures ---- */

typedef struct {
    char  name[64];
    char  cmd[MAX_PATH];
    char  args_raw[MAX_LINE];   /* raw args string (may contain ${ABI}) */
    char *args[MAX_ARGS];       /* parsed argv */
    int   argc;
    int   delay;                /* delay before launch (seconds) */
    int   priority;
    int   restart;              /* 1 = auto-restart on death */
    char  depends[MAX_PATH];    /* name of dependency process (or empty) */
    pid_t pid;
    int   launched;
    int   restart_count;
    time_t last_restart;
    int   restarting;            /* 1 = restart in progress, skip health sweep */
} Daemon;

/* ---- globals ---- */

static Daemon daemons[MAX_DAEMONS];
static int ndaemons = 0;
static char moddir[MAX_PATH] = "";
static char abi[32] = "";
static FILE *log_fp = NULL;
static int log_to_file = 0;

/* ---- forward decls ---- */

static void log_msg(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static int  parse_config(const char *path);
static void detect_abi(void);
static int  resolve_deps(void);
static int  launch_daemon(Daemon *d);
static void monitor_loop(void);
static int  pid_alive(pid_t pid);

/* ---- logging ---- */

static void log_msg(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    /* logcat */
    {
        char buf[1024];
        vsnprintf(buf, sizeof(buf), fmt, ap);
        /* best-effort: try writing to kmsg if available, fallback to stdout */
        int fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
        if (fd >= 0) {
            dprintf(fd, "<6>TieJiaDaemon: %s\n", buf);
            close(fd);
        } else {
            fprintf(stdout, "TieJiaDaemon: %s\n", buf);
            fflush(stdout);
        }
        if (log_to_file && log_fp) {
            fprintf(log_fp, "TieJiaDaemon: %s\n", buf);
            fflush(log_fp);
        }
    }
    va_end(ap);
}

/* ---- ABI detection ---- */

static void detect_abi(void) {
    /* Use /system/bin/sh to detect, or just uname -m */
    struct utsname u;
    if (uname(&u) == 0) {
        if (strcmp(u.machine, "aarch64") == 0)      strcpy(abi, "arm64-v8a");
        else if (strstr(u.machine, "armv7"))         strcpy(abi, "armeabi-v7a");
        else if (strstr(u.machine, "armv8l"))        strcpy(abi, "armeabi-v7a");
        else if (strcmp(u.machine, "x86_64") == 0)   strcpy(abi, "x86_64");
        else if (strstr(u.machine, "i686") || strstr(u.machine, "i386"))
            strcpy(abi, "x86");
    }
    if (!abi[0]) strcpy(abi, "arm64-v8a"); /* fallback */
    log_msg("detected ABI: %s", abi);
}

/* ---- config parser ---- */

static void subst_vars(char *dst, size_t dstsize, const char *src) {
    /* Replace ${ABI} and ${MODDIR} in src */
    const char *p = src;
    char *out = dst;
    char *end = dst + dstsize - 1;

    while (*p && out < end) {
        if (strncmp(p, "${ABI}", 6) == 0) {
            size_t n = strlen(abi);
            if (out + n <= end) { memcpy(out, abi, n); out += n; }
            p += 6;
        } else if (strncmp(p, "${MODDIR}", 9) == 0) {
            size_t n = strlen(moddir);
            if (out + n <= end) { memcpy(out, moddir, n); out += n; }
            p += 9;
        } else {
            *out++ = *p++;
        }
    }
    *out = '\0';
}

static int parse_config(const char *path) {
    FILE *f = fopen(path, "r");
    char line[MAX_LINE];
    Daemon *cur = NULL;

    if (!f) {
        log_msg("cannot open config: %s", path);
        return -1;
    }

    while (fgets(line, sizeof(line), f)) {
        /* trim trailing newline */
        size_t len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r'))
            line[--len] = '\0';

        /* skip empty & comments */
        if (!line[0] || line[0] == '#') continue;

        /* section header: [name] */
        if (line[0] == '[' && line[len-1] == ']') {
            line[len-1] = '\0';
            cur = &daemons[ndaemons++];
            memset(cur, 0, sizeof(*cur));
            strncpy(cur->name, line + 1, sizeof(cur->name) - 1);
            cur->restart = 1; /* default: restart */
            cur->priority = 50; /* default priority */
            continue;
        }

        if (!cur) continue; /* no section yet */

        /* key=value */
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        char *key = line;
        char *val = eq + 1;

        /* trim key */
        while (*key == ' ') key++;
        char *kend = key + strlen(key) - 1;
        while (kend > key && *kend == ' ') *kend-- = '\0';

        if (!strcmp(key, "cmd")) {
            subst_vars(cur->cmd, sizeof(cur->cmd), val);
        } else if (!strcmp(key, "args")) {
            subst_vars(cur->args_raw, sizeof(cur->args_raw), val);
        } else if (!strcmp(key, "delay")) {
            cur->delay = atoi(val);
        } else if (!strcmp(key, "priority")) {
            cur->priority = atoi(val);
        } else if (!strcmp(key, "restart")) {
            cur->restart = (val[0] == 't' || val[0] == 'T' || val[0] == '1' || val[0] == 'y' || val[0] == 'Y');
        } else if (!strcmp(key, "depends")) {
            strncpy(cur->depends, val, sizeof(cur->depends) - 1);
        }
    }
    fclose(f);

    /* parse args for each daemon */
    for (int i = 0; i < ndaemons; i++) {
        Daemon *d = &daemons[i];
        /* first arg is cmd itself */
        d->args[0] = d->cmd;
        d->argc = 1;

        if (d->args_raw[0]) {
            char *tok = strtok(d->args_raw, " ");
            while (tok && d->argc < MAX_ARGS - 1) {
                d->args[d->argc++] = tok;
                tok = strtok(NULL, " ");
            }
        }
        d->args[d->argc] = NULL;
    }

    log_msg("parsed %d daemons from %s", ndaemons, path);
    return 0;
}

/* ---- dependency resolution (simple topological sort) ---- */

static int find_daemon(const char *name) {
    for (int i = 0; i < ndaemons; i++)
        if (!strcmp(daemons[i].name, name)) return i;
    return -1;
}

static int resolve_deps(void) {
    /* Simple priority-based ordering with dependency enforcement.
     * For each daemon with a dependency, ensure the dep launches first. */
    for (int i = 0; i < ndaemons; i++) {
        if (daemons[i].depends[0]) {
            int dep_idx = find_daemon(daemons[i].depends);
            if (dep_idx < 0) {
                log_msg("WARNING: daemon '%s' depends on unknown '%s'",
                        daemons[i].name, daemons[i].depends);
                continue;
            }
            /* Ensure dep has lower priority (launches first) */
            if (daemons[dep_idx].priority >= daemons[i].priority) {
                daemons[i].priority = daemons[dep_idx].priority + 1;
            }
        }
    }

    /* Bubble sort by priority */
    for (int i = 0; i < ndaemons - 1; i++) {
        for (int j = 0; j < ndaemons - i - 1; j++) {
            if (daemons[j].priority > daemons[j+1].priority) {
                Daemon tmp = daemons[j];
                daemons[j] = daemons[j+1];
                daemons[j+1] = tmp;
            }
        }
    }
    return 0;
}

/* ---- process management ---- */

static int pid_alive(pid_t pid) {
    if (pid <= 0) return 0;
    if (kill(pid, 0) == 0) return 1;
    return (errno == EPERM); /* EPERM = alive but no permission */
}

static int launch_daemon(Daemon *d) {
    if (d->delay > 0) {
        log_msg("daemon '%s' waiting %ds before launch", d->name, d->delay);
        sleep(d->delay);
    }

    pid_t pid = fork();
    if (pid < 0) {
        log_msg("ERROR: fork failed for '%s': %s", d->name, strerror(errno));
        return -1;
    }
    if (pid == 0) {
        /* child: close inherited FDs except stdout/stderr */
        for (int fd = 3; fd < 256; fd++) close(fd);
        setsid();
        execv(d->args[0], d->args);
        /* exec failed */
        log_msg("ERROR: exec '%s' failed: %s", d->cmd, strerror(errno));
        _exit(127);
    }

    d->pid = pid;
    d->launched = 1;
    d->last_restart = time(NULL);
    log_msg("launched '%s' (pid=%d, priority=%d)", d->name, pid, d->priority);
    return 0;
}

/* ---- main monitor loop ---- */

static void monitor_loop(void) {
    /* Phase 1: launch all daemons in priority order */
    for (int i = 0; i < ndaemons; i++) {
        Daemon *d = &daemons[i];
        launch_daemon(d);
        /* brief yield between launches */
        usleep(100000); /* 100ms */
    }
    log_msg("all daemons launched, entering health monitor");

    /* Phase 2: health monitoring loop */
    time_t last_health = time(NULL);

    while (1) {
        int status;
        pid_t died = waitpid(-1, &status, WNOHANG);
        time_t now = time(NULL);

        if (died > 0) {
            /* find which daemon died */
            for (int i = 0; i < ndaemons; i++) {
                Daemon *d = &daemons[i];
                if (d->pid == died) {
                    int sig = WIFSIGNALED(status) ? WTERMSIG(status) : 0;
                    int rc  = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
                    log_msg("daemon '%s' (pid=%d) died: signal=%d exit=%d",
                            d->name, died, sig, rc);

                    if (d->restart) {
                        /* check backoff window */
                        if (now - d->last_restart < RESTART_WINDOW) {
                            d->restart_count++;
                        } else {
                            d->restart_count = 0;
                        }

                        if (d->restart_count >= MAX_RESTARTS) {
                            log_msg("daemon '%s' exceeded max restarts (%d/%ds), giving up",
                                    d->name, MAX_RESTARTS, RESTART_WINDOW);
                            d->pid = 0;
                        } else {
                            /* exponential backoff */
                            int delay = BACKOFF_BASE << d->restart_count;
                            if (delay > BACKOFF_MAX) delay = BACKOFF_MAX;
                            log_msg("restarting '%s' in %ds (attempt %d)",
                                    d->name, delay, d->restart_count + 1);
                            d->restarting = 1;
                            sleep(delay);
                            launch_daemon(d);
                            d->restarting = 0;
                        }
                    } else {
                        d->pid = 0;
                        log_msg("daemon '%s' has restart=off, not restarting", d->name);
                    }
                    break;
                }
            }
        }

        /* periodic health sweep: check all PIDs */
        if (now - last_health >= HEALTH_INTERVAL) {
            last_health = now;
            for (int i = 0; i < ndaemons; i++) {
                Daemon *d = &daemons[i];
                if (d->pid > 0 && d->launched && d->restart && !d->restarting) {
                    if (!pid_alive(d->pid)) {
                        log_msg("HEALTH: daemon '%s' (pid=%d) not alive, restarting",
                                d->name, d->pid);
                        if (d->restart_count < MAX_RESTARTS) {
                            d->restart_count++;
                            launch_daemon(d);
                        } else {
                            log_msg("daemon '%s' exceeded max restarts, giving up", d->name);
                            d->pid = 0;
                        }
                    }
                }
            }
        }

        /* brief sleep to avoid busy-waiting */
        usleep(500000); /* 500ms */
    }
}

/* ---- signal handler ---- */

static volatile sig_atomic_t g_running = 1;

static void sig_handler(int sig) {
    if (sig == SIGTERM || sig == SIGINT) {
        g_running = 0;
    }
    if (sig == SIGCHLD) {
        /* handled in monitor loop via waitpid */
    }
}

/* ---- main ---- */

int main(int argc, char **argv) {
    const char *config_path = NULL;

    if (argc < 2) {
        fprintf(stderr, "Usage: daemon_manager <MODDIR> [log_file]\n");
        return 1;
    }

    strncpy(moddir, argv[1], sizeof(moddir) - 1);

    char config_file[MAX_PATH + 32];
    snprintf(config_file, sizeof(config_file), "%s/daemon.conf", moddir);
    config_path = config_file;

    /* optional log file */
    if (argc >= 3) {
        log_fp = fopen(argv[2], "a");
        if (log_fp) {
            log_to_file = 1;
            setvbuf(log_fp, NULL, _IOLBF, 0);
        }
    }

    /* setup signal handlers */
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sig_handler;
    sa.sa_flags = SA_NOCLDSTOP | SA_RESTART;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGCHLD, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);

    /* daemonize */
    if (fork() > 0) _exit(0);
    setsid();

    log_msg("TieJia Daemon Manager v2.0.0 starting (moddir=%s)", moddir);
    detect_abi();

    if (parse_config(config_path) != 0) {
        log_msg("FATAL: failed to parse config, exiting");
        return 1;
    }

    if (ndaemons == 0) {
        log_msg("no daemons configured, exiting");
        return 0;
    }

    resolve_deps();
    monitor_loop();

    return 0;
}

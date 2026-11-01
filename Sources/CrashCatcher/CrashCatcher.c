#include "CrashCatcher.h"

#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

// Everything below is set up before a crash, so the handler never formats or allocates.
static const int signals[] = { SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP };
#define SIGNAL_COUNT (sizeof(signals) / sizeof(signals[0]))

static struct sigaction previous[SIGNAL_COUNT];
static int installed = 0;
static char report_path[1024];
static char header[2048];
static size_t header_length = 0;
// Set once the exception handler has written the top of the report, so the abort right after
// adds to it instead of starting over.
static volatile sig_atomic_t exception_written = 0;
static volatile sig_atomic_t crashing = 0;

static void write_all(int fd, const char *bytes, size_t length) {
    while (length > 0) {
        ssize_t written = write(fd, bytes, length);
        if (written <= 0) return;
        bytes += written;
        length -= (size_t)written;
    }
}

static void write_text(int fd, const char *text) {
    write_all(fd, text, strlen(text));
}

/// A number in decimal, without printf.
static void write_number(int fd, long long value) {
    char digits[24];
    int at = (int)sizeof(digits);
    int negative = value < 0;
    unsigned long long n = negative ? (unsigned long long)(-value) : (unsigned long long)value;
    do {
        digits[--at] = (char)('0' + (n % 10));
        n /= 10;
    } while (n > 0 && at > 1);
    if (negative) digits[--at] = '-';
    write_all(fd, digits + at, sizeof(digits) - (size_t)at);
}

static const char *signal_name(int sig) {
    switch (sig) {
    case SIGABRT: return "SIGABRT";
    case SIGSEGV: return "SIGSEGV";
    case SIGBUS: return "SIGBUS";
    case SIGILL: return "SIGILL";
    case SIGFPE: return "SIGFPE";
    case SIGTRAP: return "SIGTRAP";
    default: return "signal";
    }
}

static void handle_crash(int sig, siginfo_t *info, void *context) {
    (void)info;
    (void)context;
    // A second crash while writing the first: skip straight to dying.
    if (!crashing) {
        crashing = 1;
        int flags = O_WRONLY | O_CREAT | O_APPEND | (exception_written ? 0 : O_TRUNC);
        int fd = open(report_path, flags, 0600);
        if (fd >= 0) {
            if (!exception_written) write_all(fd, header, header_length);
            write_text(fd, "Signal: ");
            write_number(fd, sig);
            write_text(fd, " (");
            write_text(fd, signal_name(sig));
            write_text(fd, ")\nCrashed at: ");
            write_number(fd, (long long)time(NULL));
            write_text(fd, "\nStack:\n");
            void *frames[64];
            int count = backtrace(frames, 64);
            backtrace_symbols_fd(frames, count, fd);
            close(fd);
        }
    }

    // Back to the default, then crash for real, so macOS still writes its own report and
    // launchd and the watchdog see the app exit as they always have.
    struct sigaction fallback;
    memset(&fallback, 0, sizeof(fallback));
    fallback.sa_handler = SIG_DFL;
    sigemptyset(&fallback.sa_mask);
    for (size_t i = 0; i < SIGNAL_COUNT; i++) sigaction(signals[i], &fallback, NULL);
    raise(sig);
}

int seawall_crash_install(const char *path, const char *text) {
    if (path == NULL || text == NULL) return -1;
    if (strlen(path) >= sizeof(report_path) || strlen(text) >= sizeof(header)) return -1;
    strlcpy(report_path, path, sizeof(report_path));
    strlcpy(header, text, sizeof(header));
    header_length = strlen(header);
    if (installed) return 0;

    // backtrace loads what it needs on its first call; do that now, not mid-crash.
    void *warm[1];
    backtrace(warm, 1);

    // A stack overflow leaves no stack to run the handler on, so give it one of its own.
    // Only the main thread gets it; that's where Seawall does nearly everything.
    static int has_stack = 0;
    if (!has_stack) {
        stack_t stack;
        stack.ss_size = 64 * 1024;
        stack.ss_sp = malloc(stack.ss_size);
        stack.ss_flags = 0;
        if (stack.ss_sp != NULL && sigaltstack(&stack, NULL) == 0) has_stack = 1;
    }

    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = handle_crash;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&action.sa_mask);
    for (size_t i = 0; i < SIGNAL_COUNT; i++) sigaction(signals[i], &action, &previous[i]);
    installed = 1;
    return 0;
}

void seawall_crash_uninstall(void) {
    if (!installed) return;
    for (size_t i = 0; i < SIGNAL_COUNT; i++) sigaction(signals[i], &previous[i], NULL);
    installed = 0;
}

void seawall_crash_write_exception(const char *text) {
    if (!installed || text == NULL) return;
    int fd = open(report_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return;
    write_all(fd, header, header_length);
    write_text(fd, text);
    write_text(fd, "\n");
    close(fd);
    exception_written = 1;
}

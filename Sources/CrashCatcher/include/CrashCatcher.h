#ifndef SEAWALL_CRASH_CATCHER_H
#define SEAWALL_CRASH_CATCHER_H

/// Writes a small report when Seawall crashes, only while crash reports are on in Settings.
///
/// Everything a crash handler needs (the file path, the header text) is copied in here ahead
/// of time, so the handler itself only calls open, write, close, sigaction and raise, all
/// async-signal-safe. The one exception is backtrace and backtrace_symbols_fd: not on the
/// POSIX list, but they don't allocate once warmed up, and crash reporters commonly use them.

/// Installs handlers for SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE and SIGTRAP. `path` is the
/// file a crash writes to; `header` goes at its top. Returns 0, or -1 if either is too long.
/// Safe to call again with a new path; the handlers stay installed.
int seawall_crash_install(const char *path, const char *header);

/// Puts back whatever handled those signals before.
void seawall_crash_uninstall(void);

/// From the uncaught exception handler: writes the header and `text` (the exception, already
/// scrubbed) to the report. The abort that follows adds the signal and stack below it.
void seawall_crash_write_exception(const char *text);

#endif

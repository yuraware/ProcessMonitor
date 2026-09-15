#ifndef CPROCESSINFO_H
#define CPROCESSINFO_H

#include <sys/types.h>
#include <sys/resource.h>
#include <stdint.h>
#include <libproc.h>

/// Basic, always-available facts about a process (from sysctl KERN_PROC_ALL).
typedef struct {
    pid_t pid;
    pid_t ppid;
    uid_t uid;
    /// Process start time (seconds since epoch). Together with pid this
    /// uniquely identifies a process instance even when pids are reused.
    int64_t start_sec;
    /// Short command name (p_comm, at most 16 chars).
    char comm[32];
} pm_proc_basic;

/// Lists every process on the system.
/// On success returns the number of entries and stores a malloc'd array in
/// *out_list which the caller must free(). Returns -1 on failure.
int pm_list_processes(pm_proc_basic **out_list);

/// Fills `out` with resource usage for `pid`. Returns 0 on success.
/// Fails with EPERM for processes owned by other users (unless root).
int pm_pid_rusage_v4(pid_t pid, struct rusage_info_v4 *out);

/// Full executable path for `pid`. Returns the length written, or <= 0 on failure.
int pm_pid_path(pid_t pid, char *buf, uint32_t len);

/// Process name as known to the kernel (longer than p_comm). Returns length or <= 0.
int pm_pid_name(pid_t pid, char *buf, uint32_t len);

/// Converts mach absolute time units (used by rusage time fields) to nanoseconds.
uint64_t pm_mach_to_ns(uint64_t mach_units);

/// Number of logical CPU cores.
int pm_cpu_count(void);

#endif /* CPROCESSINFO_H */

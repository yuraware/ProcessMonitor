#include "CProcessInfo.h"

#include <errno.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>

int pm_list_processes(pm_proc_basic **out_list) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc *procs = NULL;
    size_t size = 0;

    // The process table can grow between the two sysctl calls; retry with headroom.
    for (int attempt = 0; attempt < 8; attempt++) {
        if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0) {
            return -1;
        }
        size += size / 4 + sizeof(struct kinfo_proc) * 16;
        procs = malloc(size);
        if (procs == NULL) {
            return -1;
        }
        if (sysctl(mib, 4, procs, &size, NULL, 0) == 0) {
            break;
        }
        free(procs);
        procs = NULL;
        if (errno != ENOMEM) {
            return -1;
        }
    }
    if (procs == NULL) {
        return -1;
    }

    size_t count = size / sizeof(struct kinfo_proc);
    pm_proc_basic *list = calloc(count > 0 ? count : 1, sizeof(pm_proc_basic));
    if (list == NULL) {
        free(procs);
        return -1;
    }

    for (size_t i = 0; i < count; i++) {
        list[i].pid = procs[i].kp_proc.p_pid;
        list[i].ppid = procs[i].kp_eproc.e_ppid;
        list[i].uid = procs[i].kp_eproc.e_ucred.cr_uid;
        list[i].start_sec = (int64_t)procs[i].kp_proc.p_starttime.tv_sec;
        strlcpy(list[i].comm, procs[i].kp_proc.p_comm, sizeof(list[i].comm));
    }

    free(procs);
    *out_list = list;
    return (int)count;
}

int pm_pid_rusage_v4(pid_t pid, struct rusage_info_v4 *out) {
    return proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)out);
}

int pm_pid_path(pid_t pid, char *buf, uint32_t len) {
    return proc_pidpath(pid, buf, len);
}

int pm_pid_name(pid_t pid, char *buf, uint32_t len) {
    return proc_name(pid, buf, len);
}

uint64_t pm_mach_to_ns(uint64_t mach_units) {
    static mach_timebase_info_data_t timebase = { 0, 0 };
    if (timebase.denom == 0) {
        mach_timebase_info(&timebase);
    }
    if (timebase.numer == timebase.denom) {
        return mach_units;
    }
    return (uint64_t)((double)mach_units * (double)timebase.numer / (double)timebase.denom);
}

int pm_cpu_count(void) {
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? (int)n : 1;
}

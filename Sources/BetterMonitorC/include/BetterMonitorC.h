#ifndef BetterMonitorC_h
#define BetterMonitorC_h

#include <stdint.h>

typedef struct BetterMonitorRusage {
    uint64_t disk_read_bytes;
    uint64_t disk_written_bytes;
    uint64_t physical_footprint_bytes;
    uint64_t resident_size_bytes;
    uint64_t energy_nanojoules;
    uint64_t wakeups;
} BetterMonitorRusage;

int better_monitor_pid_rusage(int pid, BetterMonitorRusage *usage);

#endif

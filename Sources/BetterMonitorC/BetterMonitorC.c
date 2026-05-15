#include "BetterMonitorC.h"

#include <libproc.h>
#include <sys/resource.h>

int better_monitor_pid_rusage(int pid, BetterMonitorRusage *usage) {
    if (usage == 0) {
        return -1;
    }

    struct rusage_info_v6 info;
    int result = proc_pid_rusage(pid, RUSAGE_INFO_V6, (rusage_info_t *)&info);
    if (result != 0) {
        usage->disk_read_bytes = 0;
        usage->disk_written_bytes = 0;
        usage->physical_footprint_bytes = 0;
        usage->resident_size_bytes = 0;
        usage->energy_nanojoules = 0;
        usage->wakeups = 0;
        return result;
    }

    usage->disk_read_bytes = info.ri_diskio_bytesread;
    usage->disk_written_bytes = info.ri_diskio_byteswritten;
    usage->physical_footprint_bytes = info.ri_phys_footprint;
    usage->resident_size_bytes = info.ri_resident_size;
    usage->energy_nanojoules = info.ri_energy_nj;
    usage->wakeups = info.ri_pkg_idle_wkups + info.ri_interrupt_wkups;
    return 0;
}

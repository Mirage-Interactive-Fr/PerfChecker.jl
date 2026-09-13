/* Valgrind client requests have no effect outside Callgrind. */
#include <valgrind/callgrind.h>

void perfchecker_callgrind_start(void) {
    CALLGRIND_START_INSTRUMENTATION;
    CALLGRIND_ZERO_STATS;
}

void perfchecker_callgrind_stop(void) {
    CALLGRIND_STOP_INSTRUMENTATION;
}

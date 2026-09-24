#include "AllocationWatch.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// The allocator's hook: the kind of event, three arguments whose meaning
// follows the kind, the result, and a frame count. The kind's bits: 2 an
// allocation, 4 a free, 8 the first argument is the zone. An allocation with a
// zone carries its size second, one without carries it first, and a
// reallocation (an allocation and a free together) carries the new size third.
typedef void (allocation_logger)(uint32_t kind, uintptr_t first, uintptr_t second, uintptr_t third,
                                 uintptr_t result, uint32_t skip);

enum { slot_count = 32 };

typedef struct {
    _Atomic(uintptr_t) thread;
    _Atomic(size_t) largest;
    _Atomic(char *) note;
    _Atomic(size_t) note_length;
} watch_slot;

static watch_slot slots[slot_count];
static _Atomic(int) watches_active;
static _Atomic(int) install_state;   // 0 not tried, 1 installed, -1 unavailable
static const size_t ceiling = (size_t)1 << 30;

static void logged(uint32_t kind, uintptr_t first, uintptr_t second, uintptr_t third,
                   uintptr_t result, uint32_t skip) {
    (void)result;
    (void)skip;
    if (!(kind & 2) || atomic_load_explicit(&watches_active, memory_order_relaxed) == 0) return;
    size_t size = (kind & 4) ? third : ((kind & 8) ? second : first);
    uintptr_t me = (uintptr_t)pthread_self();
    for (int index = 0; index < slot_count; index++) {
        watch_slot *slot = &slots[index];
        if (atomic_load_explicit(&slot->thread, memory_order_relaxed) != me) continue;
        if (size > ceiling) {
            static const char message[] =
                "OllinMutation: one block past the allocation watch's ceiling while this case ran: ";
            (void)write(2, message, sizeof message - 1);
            char *note = atomic_load_explicit(&slot->note, memory_order_relaxed);
            size_t length = atomic_load_explicit(&slot->note_length, memory_order_relaxed);
            if (note != NULL && length > 0) (void)write(2, note, length);
            abort();
        }
        if (size > atomic_load_explicit(&slot->largest, memory_order_relaxed)) {
            atomic_store_explicit(&slot->largest, size, memory_order_relaxed);
        }
    }
}

int ollin_allocation_watch_install(void) {
    int state = atomic_load(&install_state);
    if (state != 0) return state == 1;
    int installed = 0;
    allocation_logger **hook = (allocation_logger **)dlsym(RTLD_DEFAULT, "malloc_logger");
    if (hook != NULL && *hook == NULL) {
        *hook = logged;
        installed = 1;
    }
    int expected = 0;
    atomic_compare_exchange_strong(&install_state, &expected, installed ? 1 : -1);
    return atomic_load(&install_state) == 1;
}

int ollin_allocation_watch_begin(const char *note, size_t length) {
    if (!ollin_allocation_watch_install()) return -1;
    // The copy is made before the slot is claimed, so it is not counted.
    char *copy = NULL;
    if (note != NULL && length > 0) {
        copy = malloc(length);
        if (copy != NULL) memcpy(copy, note, length);
    }
    uintptr_t me = (uintptr_t)pthread_self();
    for (int index = 0; index < slot_count; index++) {
        uintptr_t expected = 0;
        if (atomic_compare_exchange_strong(&slots[index].thread, &expected, me)) {
            atomic_store_explicit(&slots[index].largest, 0, memory_order_relaxed);
            atomic_store_explicit(&slots[index].note, copy, memory_order_relaxed);
            atomic_store_explicit(&slots[index].note_length, copy != NULL ? length : 0, memory_order_relaxed);
            atomic_fetch_add(&watches_active, 1);
            return index;
        }
    }
    free(copy);
    return -1;
}

size_t ollin_allocation_watch_end(int index) {
    if (index < 0 || index >= slot_count) return 0;
    watch_slot *slot = &slots[index];
    size_t largest = atomic_load_explicit(&slot->largest, memory_order_relaxed);
    atomic_fetch_sub(&watches_active, 1);
    atomic_store(&slot->thread, 0);
    char *note = atomic_exchange(&slot->note, NULL);
    atomic_store_explicit(&slot->note_length, 0, memory_order_relaxed);
    free(note);
    return largest;
}

size_t ollin_allocation_watch_ceiling(void) { return ceiling; }

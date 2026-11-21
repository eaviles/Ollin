#include "COllinHeapWalk.h"

#include <TargetConditionals.h>

#if TARGET_OS_OSX

#include <CoreFoundation/CoreFoundation.h>
#include <CoreVideo/CoreVideo.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/mach_vm.h>
#include <malloc/malloc.h>
#include <stdatomic.h>

// The low bits of an object's second word: its kind, and flags that are clear
// while it is alive.
static const uint64_t kPlainMask = 0xFFFFFF;

// The allocator the walk was proven on says this of itself in its
// introspection table. Any other kind stands the walk down.
static const unsigned kProvenZoneType = 1;

// A buffer of the leftovers' own shape, so the block it sits in is the block
// one of them sits in.
static CVPixelBufferRef make_specimen(void) {
    CVPixelBufferRef buffer = NULL;
    CFDictionaryRef empty = CFDictionaryCreate(NULL, NULL, NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!empty) return NULL;
    const void *keys[] = { kCVPixelBufferIOSurfacePropertiesKey };
    const void *values[] = { empty };
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (attributes) {
        CVPixelBufferCreate(NULL, 48, 2736, kCVPixelFormatType_OneComponent16Half,
                            attributes, &buffer);
        CFRelease(attributes);
    }
    CFRelease(empty);
    return buffer;
}

// The zone `pointer`'s block comes from, when that is the process's default
// zone and the allocator behind it is the kind the walk was proven on.
static malloc_zone_t *proven_zone(const void *pointer) {
    malloc_zone_t *owner = malloc_zone_from_ptr(pointer);
    vm_address_t *zones = NULL;
    unsigned count = 0;
    if (malloc_get_all_zones(mach_task_self(), NULL, &zones, &count) != KERN_SUCCESS) return NULL;
    if (!owner || !zones || count == 0) return NULL;
    malloc_zone_t *first = (malloc_zone_t *)zones[0];
    // The default zone answers through a stand-in; the first zone is the one behind it.
    if (owner == malloc_default_zone()) owner = first;
    if (!first || owner != first) return NULL;
    if (first->version < 14 || !first->introspect) return NULL;
    const malloc_introspection_t *introspect = first->introspect;
    if (!introspect->enumerator || !introspect->force_lock || !introspect->force_unlock) return NULL;
    if (introspect->zone_type != kProvenZoneType) return NULL;
    return first;
}

int ollin_heap_mark_learn(ollin_heap_mark *mark, uintptr_t *scratch, size_t room) {
    *mark = (ollin_heap_mark){ 0 };
    CVPixelBufferRef a = make_specimen();
    CVPixelBufferRef b = make_specimen();
    if (!a || !b) {
        if (a) CFRelease(a);
        if (b) CFRelease(b);
        return 0;
    }
    _Atomic(uint64_t) *wa = (_Atomic(uint64_t) *)a;
    _Atomic(uint64_t) *wb = (_Atomic(uint64_t) *)b;

    // One owner, two, three, and back, read beside the count the system reports.
    uint64_t isa = atomic_load(&wa[0]);
    uint64_t one = atomic_load(&wa[1]);
    int counted = CFGetRetainCount(a) == 1;
    CFRetain(a);
    uint64_t two = atomic_load(&wa[1]);
    counted = counted && CFGetRetainCount(a) == 2;
    CFRetain(a);
    uint64_t three = atomic_load(&wa[1]);
    counted = counted && CFGetRetainCount(a) == 3;
    CFRelease(a);
    CFRelease(a);
    uint64_t back = atomic_load(&wa[1]);

    uint64_t step = two - one;
    int ok = counted && back == one;
    // An owner more is one fixed step, a single bit above the plain bits, and
    // nothing else in the word moves.
    ok = ok && step != 0 && (step & (step - 1)) == 0 && three - two == step && step > kPlainMask;
    unsigned shift = ok ? (unsigned)__builtin_ctzll(step) : 0;
    ok = ok && (one >> shift) == 1 && (two >> shift) == 2 && (three >> shift) == 3;
    // The plain bits are the object's kind and nothing more.
    CFTypeID kind = CVPixelBufferGetTypeID();
    ok = ok && CFGetTypeID(a) == kind && (one & kPlainMask) == ((uint64_t)kind << 8 | (one & 0xFF));
    // Two fresh buffers look alike, and neither address carries a tag: a
    // tagged heap would fault a read through the plain addresses a walk hands out.
    ok = ok && atomic_load(&wa[0]) == isa && atomic_load(&wb[0]) == isa;
    ok = ok && (atomic_load(&wb[1]) & kPlainMask) == (one & kPlainMask);
    ok = ok && (atomic_load(&wb[1]) >> shift) == 1;
    ok = ok && ((uintptr_t)a >> 56) == 0 && ((uintptr_t)b >> 56) == 0;
    if (ok) {
        // The swap the walk makes reads back as one owner more, and a release undoes it.
        uint64_t expected = one;
        if (atomic_compare_exchange_strong(&wa[1], &expected, one + step)) {
            ok = CFGetRetainCount(a) == 2;
            CFRelease(a);
            ok = ok && atomic_load(&wa[1]) == one;
        } else {
            ok = 0;
        }
    }
    malloc_zone_t *zone = proven_zone(a);
    size_t block = malloc_size(a);
    ok = ok && zone && zone == proven_zone(b) && block >= 16 && block == malloc_size(b);

    mark->isa = (uintptr_t)isa;
    mark->plain = one & kPlainMask;
    mark->plainMask = kPlainMask;
    mark->shift = shift;
    mark->block = block;
    mark->zone = zone;

    if (ok) {
        // A walk finds a buffer planted for it: `a` with two owners comes back
        // held, and reads three.
        CFRetain(a);
        ollin_heap_walk_report report;
        ollin_heap_walk(mark, scratch, NULL, room, &report);
        int met = 0;
        for (uint32_t i = 0; i < report.held; i++) {
            if (scratch[i] == (uintptr_t)a) {
                met = CFGetRetainCount(a) == 3;
            }
            CFRelease((CFTypeRef)scratch[i]);
        }
        CFRelease(a);
        ok = report.status == KERN_SUCCESS && met;
    }
    CFRelease(a);
    CFRelease(b);
    if (!ok) mark->zone = NULL;
    return ok;
}

typedef struct {
    const ollin_heap_mark *mark;
    uintptr_t *out;
    ollin_heap_region *regions;
    size_t room;
    ollin_heap_walk_report *report;
    vm_range_t region;   // the stretch the allocator last named
} walk_context;

// Called by the allocator's listing with the zone locked. It reads two words
// of a block, compares, and swaps one; it takes no memory and calls nothing.
//
// The swap is what makes a found buffer safe to look at afterwards. It
// succeeds only on a word that says "alive, two owners" at that instant, by
// the step a retain makes, so it is a retain taken from an object proven to
// have owners, and a release that races it sees the count it should. A block
// that is no pixel buffer, or one on its way out, fails the comparison and is
// never written to.
static void record_ranges(task_t task, void *raw, unsigned type, vm_range_t *ranges, unsigned count) {
    (void)task;
    walk_context *context = raw;
    if (type & MALLOC_PTR_REGION_RANGE_TYPE) {
        // A stretch of heap, named before the blocks carved from it.
        if (count == 1) context->region = ranges[0];
        if (!(type & MALLOC_PTR_IN_USE_RANGE_TYPE)) return;
    }
    const ollin_heap_mark *mark = context->mark;
    ollin_heap_walk_report *report = context->report;
    report->blocks += count;
    for (unsigned i = 0; i < count; i++) {
        if (ranges[i].size != mark->block) continue;
        _Atomic(uint64_t) *words = (_Atomic(uint64_t) *)ranges[i].address;
        if (atomic_load_explicit(&words[0], memory_order_relaxed) != mark->isa) continue;
        uint64_t word = atomic_load_explicit(&words[1], memory_order_relaxed);
        if ((word & mark->plainMask) != mark->plain || (word >> mark->shift) != 2) continue;
        if (report->held >= context->room) {
            report->dropped++;
            continue;
        }
        if (atomic_compare_exchange_strong(&words[1], &word, word + ((uint64_t)1 << mark->shift))) {
            if (context->regions) {
                vm_range_t region = context->region;
                int inside = ranges[i].address >= region.address
                    && ranges[i].address + ranges[i].size <= region.address + region.size;
                context->regions[report->held] = inside
                    ? (ollin_heap_region){ region.address, region.size }
                    : (ollin_heap_region){ 0, 0 };
            }
            context->out[report->held++] = ranges[i].address;
        }
    }
}

void ollin_heap_walk(const ollin_heap_mark *mark, uintptr_t *out, ollin_heap_region *regions,
                     size_t room, ollin_heap_walk_report *report) {
    *report = (ollin_heap_walk_report){ 0 };
    malloc_zone_t *zone = mark->zone;
    if (!zone) {
        report->status = KERN_FAILURE;
        return;
    }
    walk_context context = { mark, out, regions, room, report, { 0, 0 } };
    mach_timebase_info_data_t base;
    mach_timebase_info(&base);
    uint64_t begun = mach_absolute_time();
    zone->introspect->force_lock(zone);
    report->status = zone->introspect->enumerator(mach_task_self(), &context,
        MALLOC_PTR_IN_USE_RANGE_TYPE | MALLOC_PTR_REGION_RANGE_TYPE, (vm_address_t)zone, NULL,
        record_ranges);
    zone->introspect->force_unlock(zone);
    uint64_t ended = mach_absolute_time();
    report->nanoseconds = (ended - begun) * base.numer / base.denom;
}

void ollin_heap_probe(const ollin_heap_mark *mark, const ollin_heap_region *regions, size_t count,
                      void *scratch, size_t scratchSize, uintptr_t *out, size_t room,
                      ollin_heap_walk_report *report) {
    *report = (ollin_heap_walk_report){ 0 };
    malloc_zone_t *zone = mark->zone;
    if (!zone) {
        report->status = KERN_FAILURE;
        return;
    }
    const uint64_t step = (uint64_t)1 << mark->shift;
    mach_timebase_info_data_t base;
    mach_timebase_info(&base);
    uint64_t begun = mach_absolute_time();
    zone->introspect->force_lock(zone);
    for (size_t r = 0; r < count; r++) {
        ollin_heap_region region = regions[r];
        if (region.size == 0 || region.size > scratchSize) continue;
        // Copied through the kernel: the allocator may have given the stretch
        // back since it was remembered, and a plain read would then fault.
        mach_vm_size_t got = 0;
        if (mach_vm_read_overwrite(mach_task_self(), region.base, region.size,
                                   (mach_vm_address_t)scratch, &got) != KERN_SUCCESS
            || got != region.size) continue;
        for (size_t offset = 0; offset + mark->block <= region.size; offset += mark->block) {
            report->blocks++;
            const uint64_t *seen = (const uint64_t *)((const char *)scratch + offset);
            if (seen[0] != mark->isa) continue;
            uint64_t word = seen[1];
            if ((word & mark->plainMask) != mark->plain || (word >> mark->shift) != 2) continue;
            if (report->held >= room) {
                report->dropped++;
                continue;
            }
            // It read as a live pixel buffer under the lock, so its block is
            // in use and its page stays while the lock is held.
            _Atomic(uint64_t) *words = (_Atomic(uint64_t) *)(region.base + offset);
            if (atomic_compare_exchange_strong(&words[1], &word, word + step)) {
                out[report->held++] = region.base + offset;
            }
        }
    }
    zone->introspect->force_unlock(zone);
    uint64_t ended = mach_absolute_time();
    report->nanoseconds = (ended - begun) * base.numer / base.denom;

    // Asked of the allocator once the lock is gone (it may want one the look
    // held): each is a block of a pixel buffer's size, starting there. A
    // stretch that has since been carved another way could hold a look-alike
    // in the middle of some other block; that one gets its count back.
    uint32_t kept = 0;
    for (uint32_t i = 0; i < report->held; i++) {
        if (malloc_size((const void *)out[i]) == mark->block) {
            out[kept++] = out[i];
        } else {
            atomic_fetch_sub(&((_Atomic(uint64_t) *)out[i])[1], step);
        }
    }
    report->held = kept;
}

long ollin_heap_owner_count(uintptr_t object, const ollin_heap_mark *mark) {
    return (long)(atomic_load(&((_Atomic(uint64_t) *)object)[1]) >> mark->shift);
}

void ollin_heap_release(uintptr_t object, unsigned times) {
    for (unsigned i = 0; i < times; i++) CFRelease((CFTypeRef)object);
}

#else

// Proven on the Mac's allocator only. Elsewhere nothing is learned, so the
// walk never runs.

int ollin_heap_mark_learn(ollin_heap_mark *mark, uintptr_t *scratch, size_t room) {
    (void)scratch;
    (void)room;
    *mark = (ollin_heap_mark){ 0 };
    return 0;
}

void ollin_heap_walk(const ollin_heap_mark *mark, uintptr_t *out, ollin_heap_region *regions,
                     size_t room, ollin_heap_walk_report *report) {
    (void)mark;
    (void)out;
    (void)regions;
    (void)room;
    *report = (ollin_heap_walk_report){ 0 };
    report->status = -1;
}

void ollin_heap_probe(const ollin_heap_mark *mark, const ollin_heap_region *regions, size_t count,
                      void *scratch, size_t scratchSize, uintptr_t *out, size_t room,
                      ollin_heap_walk_report *report) {
    (void)mark;
    (void)regions;
    (void)count;
    (void)scratch;
    (void)scratchSize;
    (void)out;
    (void)room;
    *report = (ollin_heap_walk_report){ 0 };
    report->status = -1;
}

long ollin_heap_owner_count(uintptr_t object, const ollin_heap_mark *mark) {
    (void)object;
    (void)mark;
    return 0;
}

void ollin_heap_release(uintptr_t object, unsigned times) {
    (void)object;
    (void)times;
}

#endif

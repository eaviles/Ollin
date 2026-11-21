#ifndef OLLIN_HEAP_WALK_H
#define OLLIN_HEAP_WALK_H

#include <stddef.h>
#include <stdint.h>

// Finds the pixel buffers in this process that have exactly two owners, and
// takes one more owner of each so they can be looked at safely afterwards.
//
// Kept in C because the walk runs with the allocator locked: nothing in it may
// take or return memory, and generic Swift in a debug build does. The Swift
// side decides what a found buffer is and whether it may be freed; this side
// only finds and holds.

// What a pixel buffer object looks like in memory on this system, learned from
// buffers made for the purpose rather than assumed.
typedef struct {
    uintptr_t isa;       // the first word of every one
    uint64_t plain;      // the low bits of the second word every live one shares
    uint64_t plainMask;  // which bits those are
    unsigned shift;      // where the owner count begins in the second word
    size_t block;        // the size of the block the allocator gives one
    void *zone;          // the allocator zone those blocks come from
} ollin_heap_mark;

typedef struct {
    uint32_t blocks;       // blocks the allocator listed
    uint32_t held;         // pixel buffers found with two owners, now held once more
    uint32_t dropped;      // more of them than there was room for, left alone
    int32_t status;        // what the allocator's own listing returned, 0 for success
    uint64_t nanoseconds;  // how long the zone stayed locked
} ollin_heap_walk_report;

// Learns `mark`. Returns 1 when everything it checked held: two fresh buffers
// look alike, an owner more moves the second word by one fixed step and by
// nothing else, the swap the walk makes reads back as one more owner, the
// blocks come from the default zone of the allocator the walk was proven on,
// and a walk finds a buffer planted for it (`scratch`, `room` addresses long,
// is where that walk writes). Returns 0 otherwise, and the walk must then
// never run.
int ollin_heap_mark_learn(ollin_heap_mark *mark, uintptr_t *scratch, size_t room);

// A stretch of the heap the allocator carves blocks of one size from.
typedef struct {
    uintptr_t base;
    size_t size;
} ollin_heap_region;

// One walk of the whole heap. Every block of a pixel buffer's size whose two
// words say "a pixel buffer with two owners" is given a third owner, by the
// same atomic step a retain makes, and its address is written to `out` (at
// most `room`). The caller owns that third reference to each and must release
// it. `regions`, when given, receives beside each address the stretch of heap
// the allocator said the block sits in, or a size of 0 where it said none.
//
// The zone is locked for the walk and nothing is allocated inside it. The
// allocator's listing visits every block there is, so the lock is held longer
// the more the process holds.
void ollin_heap_walk(const ollin_heap_mark *mark, uintptr_t *out, ollin_heap_region *regions,
                     size_t room, ollin_heap_walk_report *report);

// One look at `count` remembered regions instead of the whole heap: the same
// finding and holding, at a cost that does not grow with the heap.
//
// Each region is copied through the kernel, which answers "not there" where a
// plain read of memory the allocator has since given back would fault, into
// `scratch` (`scratchSize` bytes; a larger region is skipped), and the copy is
// read at every block's place. A place that reads as a pixel buffer with two
// owners is given a third in the live memory, as in the walk, and then asked
// of the allocator: one that is no block of a pixel buffer's size is given
// back its count and left out.
//
// The zone is locked for the look and nothing is allocated inside it.
void ollin_heap_probe(const ollin_heap_mark *mark, const ollin_heap_region *regions, size_t count,
                      void *scratch, size_t scratchSize, uintptr_t *out, size_t room,
                      ollin_heap_walk_report *report);

// The owner count the object's second word carries.
long ollin_heap_owner_count(uintptr_t object, const ollin_heap_mark *mark);

// Releases `object` `times` times.
void ollin_heap_release(uintptr_t object, unsigned times);

#endif

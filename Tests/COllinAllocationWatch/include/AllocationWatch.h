#ifndef OLLIN_ALLOCATION_WATCH_H
#define OLLIN_ALLOCATION_WATCH_H

#include <stddef.h>

// The largest single block one thread asks the system allocator for over a
// stretch of its work, heard through the allocator's own logging hook. Kept in
// C because the hook runs inside the allocator: it must not allocate, and in a
// debug build generic Swift code does (an unspecialized iterator's frame).

// Installs the hook once. Returns 1 when the allocator reports to it, 0 where
// it cannot (another hook is already there, or the allocator has none).
int ollin_allocation_watch_install(void);

// Starts watching the calling thread and returns the slot to hand to
// `ollin_allocation_watch_end`, or -1 when no slot is free or the hook is not
// installed. `note` (`length` bytes, copied) is what a block past the ceiling
// writes to standard error before the process stops.
int ollin_allocation_watch_begin(const char *note, size_t length);

// Stops watching the slot and returns the largest block asked for since it
// began, in bytes.
size_t ollin_allocation_watch_end(int slot);

// The size past which a block asked for on a watched thread stops the process
// rather than being recorded.
size_t ollin_allocation_watch_ceiling(void);

#endif

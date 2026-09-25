# The test suite

`Scripts/test.sh` runs everything here, and it runs a few suites in phases of
their own. This page says why, so that placing a new test is a decision rather
than something re-derived from a failure six months from now.

## Running it

```sh
Scripts/test.sh <Suite>     # one suite, seconds; also the isolation rerun
Scripts/test.sh quick       # the sub-minute pass (no GPU snapshots, no nested builds)
Scripts/test.sh shard       # the whole suite, OllinTests split across processes
Scripts/test.sh             # the whole suite, one process per phase
Scripts/test.sh milestone   # the whole suite plus the five signed-bundle builds
Scripts/test.sh ci          # the runner's own recipe, as build.yml runs it
Scripts/test.sh tsan        # the non-GPU targets under Thread Sanitizer, a second build
```

The whole suite takes many minutes, so run it in the background or with an
explicit long timeout, never as a plain foreground call. `Scripts/shard-tests.sh`
carries the mechanism behind `shard` and what it measured.

Filters and skips are unanchored regexes over the full test ID, so write
`OllinTests.SnapshotTests` and never a bare `SnapshotTests`, which also matches
`OllinPhysicsTests.PhysicsSnapshotTests` and silently drops 46 real tests.

## The one rule behind the phases

**A suite that measures the outside world against a clock, or that holds a
device or a name only one process can have, runs on a quiet machine.** Everything
else runs together.

That is the whole rule. The lists at the top of `Scripts/test.sh` are its cases,
and every one of them is there because a run failed on it.

**`sensitive`, the wall-clock and device suites.** `DataFeedTests` counts polls
per elapsed second. `ListeningTests` waits on the system speech stack.
`FrameSourceTests` and `ModelTrackerTests` want the Vision compute device.
`SpatialVideoTests` is here for a different reason than the rest: its stereo
HEVC readback goes through the hardware video decoder, and under a full parallel
run that wait has wedged indefinitely rather than failing. `PhonePictureRoundTripTests`
decodes the phone's pictures through the same decoder, so it sits beside it. `DataFeedTests` keeps
its place even though the two rules below kill most of what looks like load: its
last test loads through the real system rather than a stub, and that load timed
out inside a batch of every target at once with both rules already applied.

**`loopback`, the suites that talk to a real system service.** They send a clock
train or a frame out through Core MIDI, the Link session's socket, or the laser's
stand-in DAC, and measure what arrives against a window. Beside a full run they
starve: the timecode clock's one-second window closed before its probe ran, and
the tempo clock read no tempo at all (2026-09-08, run 34248343439, both in the
third process at minute ten). Run alone they take seconds.

**`crowded`, the suites that cannot share the machine with the drawing shards.**
`PushFeedTests` drives a real local HTTP server and measures what arrives against
deadlines; beside the shards its tasks resumed so late that seven of them expired
together at three minutes on a stopwatch none of them got to read (2026-09-09,
run 34299549773). `MaterialSourceTests` spawns a `swiftc` to typecheck the source
it prints, which is a minute of compiler on a quiet machine and neither finished
nor useful on a busy one. `PhoneTouchTests` is here for a combination no other
suite has: it is the one `@MainActor` suite carrying a per-test time limit, and a
main-actor hop is measured inside the test's own window, so its seventeen tests
wait on one actor while every drawing test in the phase holds it. The work itself
is 0.012 s on a quiet machine; the phase ran 255 s on 2026-09-14 and passed, then
563 s on the next commit with all seventeen failing together at 527 s against a
one-minute limit, having done nothing.

**`runner`, which is a skip list rather than a phase.** What a CI runner cannot
do at all: the snapshot references are recorded on a developer's GPU and the
runner's paravirtual one anti-aliases differently, Vision reports no compute
device there (optical flow, the segmenter's live wiring), screen capture is
permitted and delivers no frame, the frame-interpolation gate wants a camera, and
the two build suites run whole nested builds inside a test. The virtual camera
suite is the one no probe can guard: its first call into CoreMediaIO makes the
framework initialize its extension plug-ins, which sends an XPC message to an
extension host that never answers on the runner, and a thread parked in a
synchronous C call is beyond any suite time limit (2026-09-08, run 34236822231:
2,971 tests in seven minutes, then silence until the watchdog sampled and killed
it).

A new device test belongs behind an `.enabled(if:)` probe of its device rather
than on that list, because a probe refuses itself wherever the device is absent
and a list has to be maintained per machine.

## What a phase does not fix

A phase helps a suite that is competing with *other targets* for something. A
suite that fails while running alone has a defect, and moving it into a phase
hides the defect. These all looked exactly like load, and none of them was:

- **A suite starving inside its own target.** `OllinVisionTests` reached 113 s
  and 129 s with the target running completely alone, at 15% CPU (2026-08-26).
- **A parked cooperative pool.** The pool is one thread per core, and a helper
  that parks every worker on a semaphore freezes the process. A timeout while
  the process burns 2% CPU is a parked pool, not a busy machine, and
  `sample <pid>` names the culprit in one shot. Never park a worker.
- **A deadline read before the probe.** `while Date() < deadline { probe }` gives
  up having never looked when the task is starved past its own deadline: thirteen
  `DataFeedTests` threw `Timeout` together with the stub's answer already in hand
  (2026-08-29). Probe first, then read the clock, and poll `>=` on a counter
  rather than `==`, since a full run can hand a task back long after the thing it
  watches happened.
- **A main-actor hop from a suite that is not on it.** The drawing suites are
  main-actor bound and run one at a time, so each hop waits behind every one of
  them already queued. Measured in one 3,107-test run: no hop 74.8 s, one hop
  142.6 s, two hops 617.0 s and over the limit, for tests that take 2.5 s
  together on their own. `OllinApp.isRenderingHeadless` is `nonisolated(unsafe)`
  and `DataFeed.start` / `PushFeed.start` are nonisolated so that neither suite
  has to hop at all.
- **A process global held across a suspension.** A test that sets
  `OllinApp.isRenderingHeadless` and then `await`s releases the main actor with
  the flag still up, and every main-actor test scheduled during that suspension
  reads somebody else's export as its own (2026-09-01: two `SessionRecorderTests`
  failed with `isRecording` false because `PushFeedTests` was mid-`await` with
  the flag set). Start off-main work with `startOffTheMainThread`
  (`OllinTests/HeadlessFlagSupport.swift`), which joins a plain `Thread`, so the
  work leaves the main thread without ever yielding the main actor.

## Serializing against a machine-global name

`.serialized` on a suite orders *that suite's* tests. It says nothing about a
sibling suite, so two suites that share a name the whole Mac can see still run at
the same time.

Core MIDI is that case in this tree: the endpoints are machine-global and an
input connects to *every* source on the Mac, so one suite's teardown is the
other's setup change. Both loopback suites are nested under one serialized parent
(`CoreMIDILoopback`), and the trait is recursive, so only one of them holds the
link at a time. Nesting is what makes it work; two `.serialized` siblings do not.

Two *processes* can still collide, and no trait reaches that far: the Core MIDI
endpoint names, the Link session's UDP port, and a few fixed `$TMPDIR` paths are
global to the machine. Don't run the suite in two checkouts at once, and never
record snapshots while another session is running tests.

## Bytes that arrived from outside

Every decoder that reads a network or a cable, and every reader of a file a
sketch is handed, runs under a seeded mutation harness: `OllinMutation` (a regular target under `Tests/`, Foundation only,
for the same reason as the browser gate), driven from `OllinMutationTests`, one
suite per wire. The one thing asserted is that every call comes back: a value,
a `nil`, or a throw. A trap (an index out of range, an overflow, a narrowing
that does not fit, a force unwrap) is the failure, because a stranger's packet
must never end a show.

`MutationRun.run(name, seeds:count:seed:sweeps:decode:)` takes the inputs a
module's own encoder wrote and, for each, tries the seed itself, the empty
input, every truncation, a field sweep (every value in `Mutator.extremes` at
every width and byte order at every offset in the first 128 bytes and the last
32, where the length fields live), and `count` random mutations of one to three
stacked edits (truncate, flip a bit or a byte, splice, insert, delete, an
extreme field, swap, repeat a run, and a number written as text such as `1e300`
over a run of digits, the edit for a protocol that carries numbers as words).
The report says how many cases decoded, were refused, or threw, and which seeds
did not decode as given, since a seed that never decodes tests nothing.

A trap ends the process, and the harness cannot catch that. What it does
instead is write the case it is about to try, before every call, to
`$TMPDIR/ollin-mutation/<name>.log` (the run's name, its seed, the case number,
the byte count, and the bytes in hex), and remove the file when the run
completes. So a log that exists after a run always means a run that died, and
it holds the input that killed it: `MutationLog.lastEntry(for:)` reads it back
and `MutationLog.bytes(fromHex:)` turns the hex into a test's fixture. The
harness's own test proves this end to end: an unsafe decoder runs in a child
process (`#expect(processExitsWith:)`), dies, and the parent reads the dying
case from the child's log.

Adding a decoder: build the seeds with the module's own encoder, hand `run` a
closure that decodes *and reads* the result every way a sketch would (a reader
that narrows a number is on the wire as much as the decoder before it, and
nine of the thirteen traps found were readers), and assert `report.seedsRefused` is
empty. A stateful reader is either fresh per case or small: a room that kept
every mutated block rebuilt a mesh of thousands per case. A decoder reached
only through state (a pong that lands on a measurement in flight) needs that
state set up in the closure. A message the parser reads as nothing is not a
seed.

### Files, and what a file declares

The readers of the files a sketch is handed run under the same harness, one
suite per family: color files (`.cube`, palettes, ICC), timelines (takes,
automations, cue sheets, formula text), MIDI, IES, and SVG, models (glTF text
and binary, OBJ and its material, PLY and STL through Model I/O, and USD as
text, crate, and package), depth recordings and sound files and SFZ
instruments, shader text (the GLSL importer and the include resolver), data
tables and JSON, and physics snapshots. A reader that only opens a path is
handed each case through a file in a `ScratchFolder`. A file adds two things a
datagram does not have.

**What a file declares.** A count or a size in a file is checked against the
bytes that remain before anything is set aside for it, so a forty-byte file
that claims four billion entries is refused rather than answered with a
gigabyte. A block set aside and never touched costs nothing a trap check can
see, so a run can pass `allocations:` and the harness watches the largest
single block the decoding thread asks for, through the allocator's own logging
hook (`AllocationWatch`, written in C in `COllinAllocationWatch` because it
runs inside the allocator, where generic Swift in a debug build allocates). A
case over its `AllocationBound` (16 MB plus so much per byte of input, 64 for
most readers, 4096 for a USD crate, whose LZ4 and integer coding together pack
a thousand values into a byte) is named in `report.oversized`; a block past a
gigabyte stops the process before it can be filled, writing the case to
standard error, and the log holds it as it would for a trap. The watch cannot
see past Thread Sanitizer's own allocator, so the file suites stand down under
`Scripts/test.sh tsan`. Text formats take the **number sweep**
(`numberSweep: true`): every number in the input replaced, one at a time, by
each of `Mutator.numberSpellings` (`-1`, `256`, `65536`, `2147483648`,
`9223372036854775807`, `1e999`, `nan`, …), the field sweep's twin for a format
that writes its numbers as words. A seed built with `JSONSerialization` is
written with `.sortedKeys`, or its bytes (and every case number) change with
the process's hash seed.

**How deep a file nests.** A stack overflow is a trap the edits never reach:
they do not nest a structure ten thousand deep. `DeepInputTests` hands each
reader that recurses such an input directly, on a thread with a 512 KB stack,
the size a background thread or a task gets, where the main thread's eight
megabytes would hide a recursion a background load dies of. The limits are
measured there: a scene nests at most 64 levels (glTF's
`GLTFDocument.maxNodeDepth` and USD's `USDStage.maxDepth`), and a scene at that
depth reads with half the stack to spare in a debug build, because another
compiler's frames are larger: with three percent to spare on the desk, the
runner's compiler overflowed it. A walk the test adds to read a scene keeps its
pending nodes on a list, or the test measures itself; a formula
is at most 1,024 tokens nested 64 deep; the include resolver stops at 32. A
file that names another file (a model's buffer, a material's picture, a
shader's include) reads it only when it is a regular file, never a device such
as `/dev/zero`.

## The handoffs under Thread Sanitizer

`Scripts/test.sh tsan` builds the package a second time with `--sanitize=thread`,
under `.build/tsan` so that no object is shared with the plain build, and runs
every target whose tests run without the GPU. That is where the
producer-to-reader shape lives: a wire's receiver, the audio analyzer, a phone
reader, or a feed produces on a thread of its own and a sketch reads on the
main one, through an `@unchecked Sendable` producer and an
`OSAllocatedUnfairLock` handoff. The convention runs through a dozen
satellites, and until this run no tool had ever checked it. The sanitizer
watches every memory access and every lock, and reports two accesses to one
address from two threads with nothing ordering them.

**What is in.** The `tsan` list at the top of `Scripts/test.sh`: OSC, MIDI,
MQTT, Link, Serial, DMX, the laser, Bluetooth, the controllers, haptics, the
remote surface, the room, the phone's codecs and readers (`OllinPhoneTests`,
`OllinRecord3DTests`), the audio engine, the mutation harness, and the two
feeds out of `OllinTests` (`DataFeedTests`, `PushFeedTests`). One process, one
phase: the sanitizer's own slowdown spreads the suites out, and the loopback
windows held in the measured runs.

**What stays out, and why.** The drawing suites: a render's threads are
Metal's, and Metal, like every system framework, is not instrumented, so the
sanitizer sees a render only where it comes back into Ollin's code; a snapshot
compares pixels, not orderings; and a drawing suite is main-actor bound, so the
run's several-fold slowdown lands on the one thread the whole suite waits on.
Vision and the screen, for the same reasons (the Vision compute device and
ScreenCaptureKit are not instrumented, and their probes pull the GPU in). The
nested project builds, which spawn a `swiftc` the sanitizer has no business in.

**What a run costs** (2026-09-23, the 8 GB M2, on battery). The cold
instrumented build took 3m51s at a 1.7 GB peak, with free memory never under
1.2 GB while a second, plain build ran beside it. The run took 9m28s for 1,310
tests over 17 bundles, about four minutes of it the listing (each bundle is
loaded under the sanitizer twice, once per testing library, before anything
runs), at a 1.6 GB peak with free memory never under 2.4 GB. The tree under
`.build/tsan` is 5.7 GB. That cost is why it is a milestone check rather than a
preflight gate: `Scripts/preflight.sh --milestone` runs it, and a commit that
touches a handoff should run it by hand.

**How to read a report.** A report names two stacks, the access and the
previous one, each with a file and line, and says which thread made each. The
fix is a lock the two accesses share, or an ordering the sanitizer can see (a
dispatch queue, a semaphore, an actor hop); a suppression is never the fix for
Ollin's own code. The script writes the reports to files (`log_path`) and
prints them after the run, so one cannot scroll off among ten thousand test
lines; any report fails the run whatever the tests said, since the sanitizer
sets its own exit status only when its runtime finalizes, which a test process
does not always let it. Driving a bundle by hand, as `Scripts/shard-tests.sh`
does, needs the runtime inserted (`DYLD_INSERT_LIBRARIES` naming the
`libclang_rt.tsan_osx_dynamic.dylib` under the bundle's `Frameworks`), or the
helper refuses to start; `swift test` sets it for its own children.

**One class of report is excused**, in `Scripts/tsan-suppressions.txt`, with
the reason above each entry: an ordering that is real and runs through a system
framework the sanitizer cannot see into. Core MIDI moves a receive block to its
own thread over a lock-free queue in its C++ runtime, so the block's first read
of a field the initializer wrote reports against that write, though the port
was created after the initializer returned. The entry is the narrowest frame
that names the class (`MIDIInput.init`), so every later access on the object
still reports; a race in Ollin's own handoff is fixed in the source, never
listed.

**The exit test's child does not come up under the sanitizer.** The harness's
dying-case self-test (`anUnsafeDecoderGoesRedAndTheLogNamesTheDyingCase`)
spawns a child through `#expect(processExitsWith:)`; under the sanitizer its
exit is reported within a few milliseconds, before a sanitized process could
have loaded, and the log the body would have written is absent. It refuses
itself there through `underThreadSanitizer`, read off the loaded images, and
runs in every plain run.

**Proven both ways.** One lock dropped from one handoff (the serial port's
descriptor store, read by `isOpen` on the test's thread while the read queue
writes it) was reported at both lines with both stacks, and the helper exited
nonzero; the committed tree reports nothing.

## Adding a test

- **Does it need a device?** Put an `.enabled(if:)` probe on it, so it refuses
  itself wherever the device is absent.
- **Does it measure elapsed time?** Probe before reading the clock, and poll `>=`.
- **Is it `@MainActor`?** Don't hop to it from a suite that is not.
- **Does it write a file?** `ollinTempPath` in the test support, never a fixed
  name: the shards deal suites blind, so two suites sharing a literal path can
  land in different processes and clobber each other.
- **Does it set a process global?** Never hold one across an `await`.
- **Does it want the machine to itself?** Run its whole target alone first. If it
  still fails there, it has a defect, and a phase is the wrong tool.
- **Does it decode bytes from outside?** Put its decoder under the mutation
  harness (`OllinMutationTests`, the section above) beside its round trips.
- **Does it hand something between threads?** Run its target under
  `Scripts/test.sh tsan` once before committing; a report there is a defect,
  whatever the plain run said.

## Recording snapshot references

`OLLIN_RECORD_SNAPSHOTS=1` rewrites every reference PNG under
`OllinTests/References/`. Set it to a name instead (any value other than `0` or
`1`, matched as a case-insensitive substring, commas separating several) to
record only those and leave every other case comparing, which is what makes
adding one snapshot a one-file diff. `SnapshotSupport.swift` carries the details.

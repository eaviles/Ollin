# Ollin for coding agents

Ollin is a creative-coding framework for Swift and Metal on Apple platforms, aiming for p5.js ergonomics on an OPENRNDR-grade core. If you're an AI coding agent working in this repo, start here.

## Read this first

The full development guidance lives in [`CLAUDE.md`](CLAUDE.md). It's the single source of truth for how the project is built and the conventions that hold it together, so read it before making changes. This file is a short orientation that points there rather than restating it. When you're about to change one of the larger systems (the renderer, the effects, the 3D path), [`ARCHITECTURE.md`](ARCHITECTURE.md) is the companion that explains how it works inside, the how-and-why behind the terse invariants in `CLAUDE.md`.

## Build and verify

Building and running needs **macOS 26+ and a Metal-capable GPU**. The Swift toolchain and Metal are the hard requirements, so changes are verified on a Mac.

```sh
swift build                       # compile the framework and examples
swift run --package-path Examples Example-Basic-HelloCircle     # open a window running an example
Scripts/test.sh <SuiteName>       # the tests for the area you touched (seconds)
Scripts/test.sh quick             # the sub-minute pass, no GPU snapshots or nested builds
Scripts/test.sh                   # the whole suite, phased (many minutes; background it)
```

A change isn't verified until it builds and runs. If `swift --version` and `xcrun --find metal` both succeed, you're on a Mac with the toolchain, so build and run directly instead of adding caveats about being unable to compile.

On a fresh clone, run `Scripts/install-git-hooks.sh` once: it links the pre-commit hook that lints staged Swift with SwiftFormat and SwiftLint (both from brew; a missing tool blocks the commit rather than skipping). Before committing, `Scripts/preflight.sh` runs the doc and figure gates the diff calls for.

Three test-running rules, learned the hard way:

- **The full suite takes many minutes.** Never run it as a plain foreground call with a default command timeout; run it in the background or with an explicit long timeout, and use the filtered forms for the edit loop.
- **A full-run failure in a wall-clock suite earns an isolation rerun, not a diagnosis.** `DataFeedTests` and `ListeningTests` measure elapsed time or wait on a system model, and `SpatialVideoTests` wants the video decoder to itself, so `Scripts/test.sh` runs them first on a quiet machine. If one fails inside a plain `swift test`, rerun it alone (`Scripts/test.sh <SuiteName>`) before treating it as a signal, and say which tests failed rather than reporting the suite red. **What that rerun must not become is "so it was load."** Measured 2026-08-26: `OllinVisionTests` starved to 113 s *with the target running alone*, and `PushFeedTests` was frozen by its own helper parking all eight cooperative-pool threads. Phase 1 only helps a suite competing with *other targets* for a device; a suite that fails while running alone has a defect, and a timeout while the process burns 2% CPU is a parked thread pool rather than a busy machine.
- **Skip patterns are unanchored regexes over the full test ID.** Write `OllinTests.SnapshotTests`, never a bare `SnapshotTests`, which also matches `PhysicsSnapshotTests` and silently drops 46 real tests.

If another session or agent is working in this repo at the same time: work in a git worktree, expect a second SwiftPM invocation in the same checkout to block on the `.build` lock rather than fail, and never run `OLLIN_RECORD_SNAPSHOTS` or a full test pass while the other session is mid-build (the load makes the wall-clock suites fail, and recording rewrites 242 tracked files under them).

## A few load-bearing rules

These come up most often. `CLAUDE.md` has the full reasoning; the short version:

- **Typed core first, bare call second.** The p5-style calls (`background`, `drawCircle`) are sugar over a public, typed core; they forward to an internal `Drawer`. Build a feature on the core, then add the bare call, so nothing is reachable only through the facade.
- **Draw verbs, not nouns.** Geometry-emitting calls take a `draw` prefix (`drawCircle`, `drawRect`, `drawLine`). State (`fill`/`stroke`/`background`) and transforms (`translate`/`rotate`/`scale`) keep their own names.
- **Inspired by, not ported.** Ollin borrows ideas and API vocabulary from p5.js, OPENRNDR, and openFrameworks, with the implementation written independently. Don't translate their source line by line; p5's LGPL is incompatible with shipping as MIT. The sourcing and attribution rules are in `CLAUDE.md` and [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
- **A feature isn't done until it has an example.** New primitives and capabilities ship with a small sketch in [`Examples/`](Examples/). The anti-rot guard is `swift build --package-path Examples`, run locally at milestones: CI runs only on pull requests (macOS runners bill at 10x and mainline work goes straight to `main`), so while that's true it does not compile-test anything on its own.

## Where things live

- [`CLAUDE.md`](CLAUDE.md) - the full design intent and conventions (start here)
- [`README.md`](README.md) - what Ollin is, and how to run it
- [`CAPABILITIES.md`](CAPABILITIES.md) - everything that ships today, one bullet per capability, with the invariants that must not break
- [`ROADMAP.md`](ROADMAP.md) - what's planned, and good first contributions
- [`DESIGN-NOTES.md`](DESIGN-NOTES.md) - the engineering design behind planned work
- [`ARCHITECTURE.md`](ARCHITECTURE.md) - how the larger shipped systems work inside (the how and why, beyond the conventions)
- [`Docs/`](Docs/) - the user-facing API reference
- [`Examples/`](Examples/) - small, runnable sketches, one idea each

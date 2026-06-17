# Ollin for coding agents

Ollin is a creative-coding framework for Swift and Metal on Apple platforms, aiming for p5.js ergonomics on an OPENRNDR-grade core. If you're an AI coding agent working in this repo, start here.

## Read this first

The full development guidance lives in [`CLAUDE.md`](CLAUDE.md). It's the single source of truth for how the project is built and the conventions that hold it together, so read it before making changes. This file is a short orientation that points there rather than restating it.

## Build and verify

Building and running needs **macOS 26+ and a Metal-capable GPU**. The Swift toolchain and Metal are the hard requirements, so changes are verified on a Mac.

```sh
swift build                       # compile the framework and examples
swift run Example-HelloCircle     # open a window running an example
swift test --skip SnapshotTests   # GPU-independent tests (snapshots stay local)
```

A change isn't verified until it builds and runs. If `swift --version` and `xcrun --find metal` both succeed, you're on a Mac with the toolchain, so build and run directly instead of adding caveats about being unable to compile.

## A few load-bearing rules

These come up most often. `CLAUDE.md` has the full reasoning; the short version:

- **Typed core first, bare call second.** The p5-style calls (`background`, `drawCircle`) are sugar over a public, typed core; they forward to an internal `Drawer`. Build a feature on the core, then add the bare call, so nothing is reachable only through the facade.
- **Draw verbs, not nouns.** Geometry-emitting calls take a `draw` prefix (`drawCircle`, `drawRect`, `drawLine`). State (`fill`/`stroke`/`background`) and transforms (`translate`/`rotate`/`scale`) keep their own names.
- **Inspired by, not ported.** Ollin borrows ideas and API vocabulary from p5.js, OPENRNDR, and openFrameworks, with the implementation written independently. Don't translate their source line by line; p5's LGPL is incompatible with shipping as MIT. The sourcing and attribution rules are in `CLAUDE.md` and [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
- **A feature isn't done until it has an example.** New primitives and capabilities ship with a small sketch in [`Examples/`](Examples/), and CI compile-tests them so they don't rot.

## Where things live

- [`CLAUDE.md`](CLAUDE.md) - the full design intent and conventions (start here)
- [`README.md`](README.md) - what Ollin is, and how to run it
- [`ROADMAP.md`](ROADMAP.md) - what's planned, and good first contributions
- [`DESIGN-NOTES.md`](DESIGN-NOTES.md) - the engineering design behind planned work
- [`Docs/`](Docs/) - the user-facing API reference
- [`Examples/`](Examples/) - small, runnable sketches, one idea each

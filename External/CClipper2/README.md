# CClipper2 — vendored Clipper2

This directory bundles the C++ core of **Clipper2**, Angus Johnson's polygon clipping and offsetting library, as third-party source. It is the engine behind `Shape`'s boolean operations (`union`, `intersection`, `subtracting`, `symmetricDifference`) and `Shape.offset(by:join:)`. It is wrapped behind Ollin's own API; the `Clipper2Lib` symbols are not part of Ollin's public surface.

- **Upstream:** https://github.com/AngusJohnson/Clipper2
- **Version:** 2.0.1 (tag `Clipper2_2.0.1`)
- **Retrieved:** 2026-06-10
- **License:** Boost Software License 1.0 (see `LICENSE` in this directory)
- **Scope:** the `CPP/Clipper2Lib` module only (`include/clipper2/*.h` + `src/*.cpp`), preserved in its upstream `include/` + `src/` layout under `Clipper2Lib/` so its `#include "clipper2/…"` directives resolve. Sample apps, tests, the DLL projects, and the C#/Delphi ports are not included.
- **Modifications:** none. The upstream files are unmodified, per-file headers intact.

The only code of ours here is the thin C shim (`include/cclipper2.h` + `src/cclipper2.cpp`) that exposes the boolean and offset entry points as plain C, so Swift can call them without C++ interop.

See the repo-root `THIRD-PARTY-NOTICES.md` for the notice entry.

# CBox2D — vendored Box2D

This directory contains a verbatim copy of **Box2D**, Erin Catto's 2D
rigid-body physics engine (the v3 line, rewritten in C). Ollin uses it to
back the rigid-body side of `OllinPhysics` — bodies with rotation, polygon
colliders, joints, and stable stacking, past what the from-scratch Verlet
solver does well. It is wrapped behind Ollin's own `World`/`Body` API; the
`b2*` C symbols are not part of Ollin's public surface.

This is bundled third-party source, not an Ollin-authored component. Its
license is separate from Ollin's MIT license (Box2D is also MIT — see the
repo-root `THIRD-PARTY-NOTICES.md`).

## Provenance

- **Upstream:** https://github.com/erincatto/box2d
- **Release:** v3.1.1
- **Commit:** `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`
- **Date:** 2026-06-08
- **License:** MIT (see `LICENSE`)

The source files are unmodified. The upstream `src/` (implementation and
private headers) and `include/box2d/` (public headers) layout is preserved so
the relative `#include "box2d/…"` directives resolve; the per-file copyright
headers and the upstream `LICENSE` are kept intact. The one added file is
`include/module.modulemap`, which lets Swift `import CBox2D` against the
`box2d/box2d.h` umbrella header (it is not upstream source).

The upstream `src/CMakeLists.txt` and `src/box2d.natvis` are present but
excluded from the SwiftPM target (it builds the `.c` directly); only `src/`
and `include/` are vendored — the upstream `samples/`, `test/`, `benchmark/`,
`shared/`, and `extern/` directories are not needed by the core library.

## Updating

Re-clone the upstream repo at the desired release, copy `src/*` and
`include/*` over the files here, restore `include/module.modulemap`, and
update the release/commit/date above. Do not edit the C source; if a local
change is ever unavoidable, note it here so the copy stays auditable.

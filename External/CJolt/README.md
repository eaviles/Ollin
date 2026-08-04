# CJolt: vendored Jolt Physics

This directory contains a verbatim copy of **Jolt Physics**, Jorrit Rouwe's
multi-core rigid-body physics and collision-detection library, the solver
behind `OllinPhysics`' 3D rigid-body `World3D`/`Body3D` API. It is wrapped
behind Ollin's own API through the C bridge in `include/` + `src/`; the `JPH`
C++ symbols are not part of Ollin's public surface, and Swift only ever
imports the C module.

This is bundled third-party source, not an Ollin-authored component. Its
license is separate from Ollin's MIT license, though also MIT; see `LICENSE`
and the repo-root `THIRD-PARTY-NOTICES.md`.

## Provenance

- **Upstream:** https://github.com/jrouwe/JoltPhysics
- **Release:** v5.6.0
- **Commit:** `e77f175595e64cb44218cc9d9d56fc365ad0e36a`
- **Date:** 2026-08-04
- **License:** MIT (see `LICENSE`)

The `Jolt/` subtree is the upstream library directory, unmodified. The GPU
compute backends (`Jolt/Compute/{MTL,DX12,VK,CPU}`), the HLSL shader sources
(`Jolt/Shaders`), and the debug renderer (`Jolt/Renderer`) are present on disk
but excluded from the SwiftPM build; Ollin uses the CPU rigid-body simulation
only, and those subsystems are `#ifdef`-gated off without their `JPH_USE_*` /
`JPH_DEBUG_RENDERER` defines.

The added files are Ollin-authored, not upstream source:

- `include/cjolt.h`: the C bridge header (the target's public surface).
- `include/module.modulemap`: exposes the bridge as the `CJolt` clang module.
- `src/cjolt.cpp`: the bridge implementation, the only code in the repo that
  includes Jolt's C++ headers. All `JPH_*` configuration defines live in this
  one target, so the consistency rule (every compilation unit including Jolt
  headers must agree on them) holds trivially.

## Updating

Re-download the upstream release, replace the `Jolt/` subtree and `LICENSE`
wholesale, restore nothing (the Ollin-authored files live outside `Jolt/`),
and update the release/commit/date above. Do not edit the C++ source; if a
local change is ever unavoidable, note it here so the copy stays auditable.

# CLibtess2 — vendored libtess2

This directory contains a verbatim copy of **libtess2**, a polygon tessellation
library (the GLU tessellator lineage, refactored for games and tools). Ollin
uses it to triangulate concave polygons and polygons with holes for the vector
`Shape`/`Contour` fill path. It is wrapped behind Ollin's own API; the C symbols
are not part of Ollin's public surface.

This is bundled third-party source, not an Ollin-authored component. Its license
is separate from Ollin's MIT license (see the repo-root `THIRD-PARTY-NOTICES.md`).

## Provenance

- **Upstream:** https://github.com/memononen/libtess2
- **Commit:** `8dbd6483e920311a58c9af10a10beb278efebc36`
- **Date:** 2025-10-15
- **License:** SGI Free Software License B, Version 2.0 (see `LICENSE.txt`)

The source files are unmodified but for one line. Only the directory layout is
preserved (`Source/` for the implementation and private headers, `Include/` for
the public `tesselator.h`); the per-file SGI copyright headers and the upstream
`LICENSE.txt` are kept intact, as the license requires.

## Local change

- **`TESSreal` is `double`** (`Include/tesselator.h`, upstream `float`), since
  2026-10-26. The sweep keeps its order by comparing vertices, and in single
  precision a folded ring that crosses itself hundreds of times within a few
  pixels, with points on top of each other, put that order out and tripped its
  asserts (`tesedgeEval`, `AddRightEdges`), which ended a live window. In double
  the same rings, and a quarter million generated like them, tessellate without
  one. The web page's player part is built from this same header, so a fill
  triangulates there as it does here. The asserts are also compiled out
  (`NDEBUG`, set in `Package.swift` and in the page's build), so an input the
  double sweep still cannot order returns a poor fill rather than an abort.

## Updating

Re-clone the upstream repo, copy `Source/*` and `Include/tesselator.h` over the
files here, and update the commit/date above. Do not edit the C source; if a
local change is ever unavoidable, note it here so the copy stays auditable.

# CMikkTSpace — vendored MikkTSpace

This directory contains a verbatim copy of **MikkTSpace**, Morten S. Mikkelsen's
tangent-space generation library — the standard the glTF 2.0 specification names
for computing vertex tangents when a model authors a normal map without them, and
the one normal-map bakers target so a generated tangent basis matches the baked
texture. Ollin uses it to generate `Mesh.tangents` for normal-mapped meshes that
don't carry authored tangents. It is wrapped behind Ollin's own API; the C
symbols are not part of Ollin's public surface.

This is bundled third-party source, not an Ollin-authored component. Its license
is separate from Ollin's MIT license (see the repo-root `THIRD-PARTY-NOTICES.md`).

## Provenance

- **Upstream:** https://github.com/mmikk/MikkTSpace
- **Commit:** `3e895b49d05ea07e4c2133156cfa94369e19e409`
- **Date:** 2026-08-11 (vendored)
- **License:** zlib-style (the per-file notice; upstream ships no standalone
  LICENSE file, so `LICENSE.txt` here reproduces the notice and says so)

The source files are unmodified. The layout follows the vendored-library
convention (`Source/` for the implementation, `Include/` for the public
`mikktspace.h`); the per-file copyright notices are kept intact, as the license
requires.

## Updating

Re-fetch `mikktspace.h` and `mikktspace.c` from the upstream repo, copy them
over the files here, and update the commit/date above. Do not edit the C source;
if a local change is ever unavoidable, note it here so the copy stays auditable.

# CSyphon — vendored Syphon (Metal subset)

This directory contains the **Metal portion of the Syphon Framework**, the
macOS standard for sharing GPU frames between applications in real time
(IOSurface-backed). Ollin uses it to back `OllinSyphon` — publishing a sketch's
rendered frames as a Syphon server and consuming an external Syphon texture as
an input — so an Ollin sketch can trade live visuals with openFrameworks,
Resolume, MadMapper, VDMX, and any other Syphon app. It is wrapped behind
Ollin's own `SyphonServer`/`SyphonClient` API; the `Syphon*` Objective-C symbols
are not part of Ollin's public surface.

This is bundled third-party source, not an Ollin-authored component. Its license
is separate from Ollin's MIT license (Syphon is BSD 2-Clause — see the repo-root
`THIRD-PARTY-NOTICES.md`).

## Provenance

- **Upstream:** https://github.com/Syphon/Syphon-Framework
- **Commit:** `71351d4b484cd2d1917867f7846a5cdca724552d`
- **Date:** 2025-10-06
- **License:** BSD 2-Clause (see `License.txt`)

## What's vendored, and what isn't

Only the **Metal + shared-infrastructure** files are copied — the Metal server
and client, the server renderer, the server directory, the connection managers,
the Mach/CF messaging stack, and the base classes they share. The upstream
**OpenGL** path (`SyphonOpenGL*`, `SyphonGL*`, `SyphonCGL`, the GL renderers,
`SyphonImage*`/`SyphonIOSurfaceImage*`) is **not** vendored: Ollin is Metal-only,
and those files would pull in legacy OpenGL. The dependency closure of the Metal
classes was verified to not reach any OpenGL file.

The files are otherwise upstream source, with the per-file copyright headers and
`License.txt` kept intact. Two kinds of local change were unavoidable for the
SwiftPM `swift run` build and are noted here so the copy stays auditable:

1. **Flat layout + quoted imports.** Upstream's framework-style
   `#import <Syphon/SyphonServerBase.h>` / `<Syphon/SyphonClientBase.h>` angle
   imports (in `SyphonMetalServer.h`, `SyphonMetalClient.h`, `SyphonSubclassing.h`)
   were rewritten to quoted `#import "…"` so they resolve in this flat,
   non-framework target.
2. **Runtime shader compilation** (`SyphonServerRendererMetal.m`). Upstream loads
   a precompiled `default.metallib` from the framework bundle. Under `swift run`,
   SwiftPM does not compile a loose `.metal` into a metallib, and the
   statically-linked class has no resource bundle of its own. The (unchanged)
   texture-blit shader from `SyphonMetalShaders.metal` is therefore embedded as a
   source string and compiled at runtime — the same approach Ollin's own
   renderer uses. The change is marked inline in that file.
3. **Pixel-format-view usage** (`SyphonMetalClient.m`). The client's frame texture
   is created with `MTLTextureUsagePixelFormatView` added, so the consumer can read
   the surface's display-ready bytes through an sRGB view (Ollin shades in linear
   and expects sRGB textures to decode on sample). The change is marked inline.

Added files (not upstream source): `include/CSyphon.h` (a curated umbrella
exposing only the Metal API) and `include/module.modulemap` (so Swift can
`import CSyphon`). The upstream `Syphon_Prefix.pch` is kept and supplied to the
compiler via `-include` (it defines `SYPHONLOG` and imports Cocoa for every
`.m`); it is excluded from the SwiftPM source set.

## Updating

Re-clone the upstream repo at the desired commit, copy the Metal-subset files
over the ones here, re-apply the two local changes above (and the quoted-import
rewrite), restore `include/CSyphon.h` + `include/module.modulemap`, and update
the commit/date. Keep the OpenGL files out.

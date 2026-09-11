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
`License.txt` kept intact. The local changes below were unavoidable for the
SwiftPM build and are noted here so the copy stays auditable:

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
4. **One added import per implementation file.** Each `.m` opens with
   `#import "OllinSyphonPrefix.h"`, inserted after the file's own copyright
   header and before its first upstream import. Upstream relies on a prefix
   header instead, which Xcode forces into every translation unit with
   `-include`. SwiftPM can pass that only as an unsafe build flag, and a target
   carrying one cannot be reached through a package somebody depends on by
   version, so `import OllinSyphon` failed to resolve outside this repository
   before the change. Nothing else in those files moved.

Added files (not upstream source): `include/CSyphon.h` (a curated umbrella
exposing only the Metal API), `include/module.modulemap` (so Swift can
`import CSyphon`), and `OllinSyphonPrefix.h`, which does for each `.m` what the
prefix header did: import Cocoa and define `SYPHONLOG`, empty as it is in any
build without `DEBUG`. The upstream `Syphon_Prefix.pch` is kept for reference
and excluded from the SwiftPM source set; nothing includes it.

## Updating

Re-clone the upstream repo at the desired commit, copy the Metal-subset files
over the ones here, re-apply the local changes above (the quoted-import rewrite,
the runtime shader compilation, the pixel-format-view usage, and the added
prefix import at the top of every `.m`), restore `include/CSyphon.h` +
`include/module.modulemap` + `OllinSyphonPrefix.h`, and update
the commit/date. Keep the OpenGL files out.

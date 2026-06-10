# Third-party notices

Ollin's own source is under the MIT license (see [`LICENSE`](LICENSE)). It also
**bundles** the third-party components listed below, each under its own license.
This file is the aggregate record; the full license text and the original
copyright headers are kept alongside each component's source.

This is distinct from the projects Ollin is merely *inspired by* or *studied as a
reference* — those contribute no code and no license obligations (see the
README's "Influences & attribution"). The components here are actual source
redistributed inside this repository.

---

## libtess2

- **Used for:** triangulating concave polygons and polygons with holes, behind the vector `Shape`/`Contour` fill path (`drawShape`).
- **Location in this repo:** [`External/CLibtess2/`](External/CLibtess2/)
- **Upstream:** https://github.com/memononen/libtess2
- **Version:** commit `8dbd6483e920311a58c9af10a10beb278efebc36` (2025-10-15)
- **License:** SGI Free Software License B, Version 2.0 — full text at [`External/CLibtess2/LICENSE.txt`](External/CLibtess2/LICENSE.txt)

> Copyright (C) [dates of first publication] Silicon Graphics, Inc. All Rights Reserved.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of
> this software and associated documentation files (the "Software"), to deal in the
> Software without restriction, including without limitation the rights to use, copy,
> modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
> and to permit persons to whom the Software is furnished to do so, subject to the
> following conditions:
>
> The above copyright notice including the dates of first publication and either this
> permission notice or a reference to http://oss.sgi.com/projects/FreeB/ shall be
> included in all copies or substantial portions of the Software.
>
> (The software is provided "as is", without warranty of any kind. See `LICENSE.txt`
> for the full text, including the warranty disclaimer and the trademark clause.)

---

## Box2D

- **Used for:** the rigid-body solver behind `OllinPhysics` — bodies with rotation, polygon colliders, joints, and stable stacking — wrapped behind Ollin's own `World`/`Body` API.
- **Location in this repo:** [`External/CBox2D/`](External/CBox2D/)
- **Upstream:** https://github.com/erincatto/box2d
- **Version:** v3.1.1 — commit `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`
- **License:** MIT — full text at [`External/CBox2D/LICENSE`](External/CBox2D/LICENSE)

> MIT License
>
> Copyright (c) 2022 Erin Catto
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of
> this software and associated documentation files (the "Software"), to deal in the
> Software without restriction… (see `LICENSE` for the full text, including the
> warranty disclaimer).

---

## Clipper2

- **Used for:** polygon clipping and offsetting, behind `Shape`'s boolean set operations (`union`, `intersection`, `subtracting`, `symmetricDifference`) and `Shape.offset(by:join:)` — wrapped behind Ollin's own API.
- **Location in this repo:** [`External/CClipper2/`](External/CClipper2/)
- **Upstream:** https://github.com/AngusJohnson/Clipper2
- **Version:** v2.0.1 — tag `Clipper2_2.0.1`, commit `21ebba05db8894f0c7217ad35ea518080f324946` (2026-06-10)
- **License:** Boost Software License 1.0 — full text at [`External/CClipper2/LICENSE`](External/CClipper2/LICENSE)

> Boost Software License - Version 1.0 - August 17th, 2003
>
> Permission is hereby granted, free of charge, to any person or organization
> obtaining a copy of the software and accompanying documentation covered by
> this license (the "Software") to use, reproduce, display, distribute,
> execute, and transmit the Software… (see `LICENSE` for the full text,
> including the warranty disclaimer.)

---

## Syphon Framework

- **Used for:** sharing live GPU frames with other apps on the Mac (openFrameworks via `ofxSyphon`, Resolume, MadMapper, VDMX, …), behind `OllinSyphon`'s `SyphonServer`/`SyphonClient` API. Only the Metal portion is vendored; the OpenGL path is omitted.
- **Location in this repo:** [`External/CSyphon/`](External/CSyphon/)
- **Upstream:** https://github.com/Syphon/Syphon-Framework
- **Version:** commit `71351d4b484cd2d1917867f7846a5cdca724552d` (2025-10-06)
- **License:** BSD 2-Clause — full text at [`External/CSyphon/License.txt`](External/CSyphon/License.txt)
- **Local changes:** the framework-style `<Syphon/…>` imports were rewritten to quoted includes for the flat SwiftPM target; `SyphonServerRendererMetal.m` was changed to compile its (unchanged) blit shader from embedded source at runtime instead of loading a precompiled metallib from a bundle (the `swift run` build produces no metallib); and `SyphonMetalClient.m`'s frame texture gains `MTLTextureUsagePixelFormatView` so the consumer can read the surface through an sRGB view. All are documented in [`External/CSyphon/README.md`](External/CSyphon/README.md); the per-file copyright headers are intact.

> Copyright 2010-2023 bangnoise (Tom Butterworth), vade (Anton Marini), Maxime
> Touroute & Philippe Chaurand. All rights reserved.
>
> Redistribution and use in source and binary forms, with or without modification,
> are permitted provided that the conditions of the BSD 2-Clause license are met
> (see `License.txt` for the full text, including the warranty disclaimer).

---

## Cozette

- **Used for:** the bundled default bitmap font (`BitmapFont.builtin`), loaded at runtime from its BDF by the font loader and rendered by `drawText`.
- **Location in this repo:** [`Sources/Ollin/Resources/cozette.bdf`](Sources/Ollin/Resources/cozette.bdf)
- **Upstream:** https://github.com/the-moonwitch/Cozette
- **Version:** v1.30.0
- **License:** MIT — full text at [`Sources/Ollin/Resources/Cozette-LICENSE.txt`](Sources/Ollin/Resources/Cozette-LICENSE.txt)

> MIT License
>
> Copyright (c) 2020 Samhain &lt;samhain@moonwit.ch&gt; & contributors &lt;https://github.com/the-moonwitch/Cozette/contributors&gt;
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of
> this software and associated documentation files (the "Software"), to deal in the
> Software without restriction… (see `Cozette-LICENSE.txt` for the full text,
> including the warranty disclaimer).

---

## Hershey fonts

- **Used for:** the bundled default stroke (single-line) font (`StrokeFont.builtin`, "Hershey Sans" / `futural`), loaded at runtime from its `.jhf` by the stroke-font parser and drawn by `drawText`.
- **Location in this repo:** [`Sources/Ollin/Resources/futural.jhf`](Sources/Ollin/Resources/futural.jhf) (provenance in [`Sources/Ollin/Resources/Hershey-NOTICE.txt`](Sources/Ollin/Resources/Hershey-NOTICE.txt))
- **Upstream:** the public-domain Hershey data, as widely mirrored (e.g. https://github.com/kamalmostafa/hershey-fonts and https://paulbourke.net/dataformats/hershey/)
- **License:** public domain.

> The Hershey vector fonts were originally created by Dr. A. V. Hershey while
> working at the U.S. National Bureau of Standards, and are in the public domain.
> The public domain carries no attribution requirement; the credit above is given
> freely, and provenance is recorded for the bundled asset.

---

## Marble Madness (example font)

- **Used for:** the `PlaydateFont` example sketch only — a sample Playdate `.fnt` font, loaded at runtime to demonstrate the loader. Not part of the Ollin framework; Ollin bundles no `.fnt` fonts itself.
- **Location in this repo:** [`Examples/Text/PlaydateFont/MarbleMadness.fnt`](Examples/Text/PlaydateFont/MarbleMadness.fnt)
- **Upstream:** https://github.com/idleberg/playdate-arcade-fonts (an original homage to classic arcade typography)
- **License:** CC0 1.0 (Public Domain Dedication) — https://creativecommons.org/publicdomain/zero/1.0/

> The fonts in playdate-arcade-fonts are released into the public domain under CC0,
> which carries no attribution requirement; the credit above is given freely.

---

## El Fandanguito (example audio)

- **Used for:** the `FilePlayer` example sketch only — a sample audio clip, to demonstrate `AudioPlayer` reacting to a file. Not part of the Ollin framework; Ollin (and `OllinAudio`) bundle no audio themselves.
- **Location in this repo:** [`Examples/Audio/FilePlayer/fandanguito.m4a`](Examples/Audio/FilePlayer/fandanguito.m4a)
- **Work:** *El Fandanguito*, a traditional Mexican *son huasteco* (the composition is traditional / public domain). Performed on violin by Cynthia Molina; recorded and edited by Wikimedia Commons users Emropa and ClawisJM (students of Tec de Monterrey).
- **Upstream:** https://commons.wikimedia.org/wiki/File:Viol%C3%ADn_SonHuasteco_ELFandanguito.ogg
- **License:** CC BY-SA 4.0 — https://creativecommons.org/licenses/by-sa/4.0

> Licensed CC BY-SA 4.0 (Attribution-ShareAlike). Attribution is given above as
> required. **Changes:** the original Ogg Vorbis file was transcoded to AAC (with
> short fades) for AVFoundation playback; no other edits. As a ShareAlike work
> this clip remains under CC BY-SA 4.0 — that obligation rides on the audio file
> and its adaptations, not on Ollin's source, which stays MIT (the clip is merely
> bundled alongside it). The root [`LICENSE`](LICENSE) is unaffected.

---

## Voladores de Papantla (example video)

- **Used for:** the `VideoPlayback` example sketch only — a sample video clip, to demonstrate `VideoPlayer` drawing a file as a live image. Not part of the Ollin framework; Ollin (and `OllinVideo`) bundle no video themselves.
- **Location in this repo:** [`Examples/Video/VideoPlayback/voladores.mp4`](Examples/Video/VideoPlayback/voladores.mp4)
- **Work:** *Voladores de Papantla México* — a recording of the *Danza de los Voladores*, the Totonac pole-flying ritual dance from Papantla, Veracruz (performed at an exhibition in Mexico City, 2018). Filmed by José Millán (Wikimedia Commons user Jmillan325).
- **Upstream:** https://commons.wikimedia.org/wiki/File:Voladores_de_Papantla_M%C3%A9xico.webm
- **License:** CC BY-SA 4.0 — https://creativecommons.org/licenses/by-sa/4.0

> Licensed CC BY-SA 4.0 (Attribution-ShareAlike). Attribution is given above as
> required. **Changes:** a ~28-second excerpt was trimmed from the original
> 3-minute VP9/WebM file and re-encoded to H.264 MP4 at 960×540 (mono AAC audio)
> for AVFoundation playback and a small repository footprint; no other edits. As
> a ShareAlike work this clip remains under CC BY-SA 4.0 — that obligation rides
> on the video file and its adaptations, not on Ollin's source, which stays MIT
> (the clip is merely bundled alongside it). The root [`LICENSE`](LICENSE) is
> unaffected.

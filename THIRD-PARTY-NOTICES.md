# Third-party notices

Ollin's own source is under the MIT license (see [`LICENSE`](LICENSE)). It also
**bundles** the third-party components listed below, each under its own license.
This file is the aggregate record; the full license text and the original
copyright headers are kept alongside each component's source.

This is distinct from the projects Ollin is merely *inspired by* or *studied as a
reference*: those contribute no code and no license obligations (see
[`ATTRIBUTION.md`](ATTRIBUTION.md)). The components here are actual source
redistributed inside this repository.

---

## libtess2

- **Used for:** triangulating concave polygons and polygons with holes, behind the vector `Shape`/`Contour` fill path (`drawShape`).
- **Location in this repo:** [`External/CLibtess2/`](External/CLibtess2/)
- **Upstream:** https://github.com/memononen/libtess2
- **Version:** commit `8dbd6483e920311a58c9af10a10beb278efebc36` (2025-10-15)
- **License:** SGI Free Software License B, Version 2.0 — full text at [`External/CLibtess2/LICENSE.txt`](External/CLibtess2/LICENSE.txt)
- **Also shipped as:** part of [`Sources/Ollin/Resources/WebExpander.wasm`](Sources/Ollin/Resources/WebExpander.wasm), the stroke and fill expander compiled to WebAssembly that a web page a sketch exports carries when its strokes and fills travel as points (`Scripts/build-web-expander.sh` builds it). The page's script carries the copyright notice and the license reference beside the module.

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

## Jolt Physics

- **Used for:** the 3D rigid-body solver behind `OllinPhysics` (bodies with full 3D rotation, box/sphere/capsule/cylinder/hull/mesh colliders, joints, stacking, and grabbing), wrapped behind Ollin's own `World3D`/`Body3D` API.
- **Location in this repo:** [`External/CJolt/`](External/CJolt/)
- **Upstream:** https://github.com/jrouwe/JoltPhysics
- **Version:** v5.6.0, commit `e77f175595e64cb44218cc9d9d56fc365ad0e36a` (2026-08-04)
- **License:** MIT, full text at [`External/CJolt/LICENSE`](External/CJolt/LICENSE)

> Copyright 2021 Jorrit Rouwe
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

> Copyright the Syphon Project contributors — bangnoise (Tom Butterworth), vade
> (Anton Marini), Maxime Touroute & Philippe Chaurand. All rights reserved. See
> `License.txt` and the per-file headers for the exact notices.
>
> Redistribution and use in source and binary forms, with or without modification,
> are permitted provided that the conditions of the BSD 2-Clause license are met
> (see `License.txt` for the full text, including the warranty disclaimer).

---

## Hosek-Wilkie sky model

- **Used for:** the procedural-sky environment (`Environment.sky(...)`). Its coefficient dataset and per-channel configuration code (RGB path) are cooked once on the CPU; Ollin's own Metal shader evaluates the sky radiance per texel from the result. Wrapped behind Ollin's own API.
- **Location in this repo:** [`External/CHosekWilkie/`](External/CHosekWilkie/), holding the upstream header and RGB dataset verbatim, with `ArHosekSkyModel.c` trimmed to the RGB path (the spectral/CIE models and their large datasets removed; see the directory's `README.md`).
- **Upstream:** https://github.com/mmp/pbrt-v3 (`src/ext`), the reference implementation by Lukas Hosek and Alexander Wilkie (Charles University), v1.4a. Papers: "An Analytic Model for Full Spectral Sky-Dome Radiance" (SIGGRAPH 2012) and "Adding a Solar-Radiance Function to the Hosek-Wilkie Skylight Model" (IEEE CG&A 2013).
- **License:** 3-clause BSD, full text at [`External/CHosekWilkie/LICENSE`](External/CHosekWilkie/LICENSE)

> Copyright (c) 2012 - 2013, Lukas Hosek and Alexander Wilkie. All rights reserved.
>
> Redistribution and use in source and binary forms, with or without modification,
> are permitted provided that the copyright notice, the list of conditions, and the
> disclaimer are retained, and the contributors' names are not used to endorse
> derived products without permission. (The software is provided "as is"; see
> `LICENSE` for the full text and warranty disclaimer.)

---

## MikkTSpace

- **Used for:** generating vertex tangents (`Mesh.tangents`) for normal-mapped meshes that don't carry authored ones: the tangent-space standard the glTF 2.0 spec names for exactly that case, and the basis normal-map bakers target so a generated basis matches a baked texture. Wrapped behind Ollin's own API; the C symbols are not part of Ollin's public surface.
- **Location in this repo:** [`External/CMikkTSpace/`](External/CMikkTSpace/)
- **Upstream:** https://github.com/mmikk/MikkTSpace, by Morten S. Mikkelsen
- **Version:** commit `3e895b49d05ea07e4c2133156cfa94369e19e409` (vendored 2026-08-11)
- **License:** zlib-style per-file notice (upstream ships no standalone LICENSE file); reproduced at [`External/CMikkTSpace/LICENSE.txt`](External/CMikkTSpace/LICENSE.txt) and kept intact in both source files, as the notice requires.

> Copyright (C) 2011 by Morten S. Mikkelsen
>
> This software is provided 'as-is', without any express or implied warranty.
> Permission is granted to anyone to use this software for any purpose, including
> commercial applications, and to alter it and redistribute it freely, subject to
> the notice's three conditions (origin not misrepresented, altered versions
> marked, notice retained; see `LICENSE.txt` for the full text).

---

## Spectral primaries data (simple-spectral)

- **Used for:** spectral color (`Spectrum`, `.paint` mixing, and the spectral thin-film / diffraction / paint-mix GPU passes): the three BT.709 reflectance basis spectra a color decomposes into, plus the CIE 1931 2° observer and D65 illuminant tables, all at 380-780 nm in 5 nm steps. Cooked once on the CPU; Ollin's own shaders receive derived per-tap constants and never see the tables.
- **Location in this repo:** [`External/CSpectralData/`](External/CSpectralData/), the CSV data reformatted verbatim as C arrays (provenance and the exact files taken in the directory's [`README.md`](External/CSpectralData/README.md))
- **Upstream:** https://github.com/geometrian/simple-spectral (commit `4b36e4d`, 2020-07-19), the reference implementation accompanying *Spectral Primary Decomposition for Rendering with sRGB Reflectance* (Agatha Mallett and Cem Yuksel, EGSR 2019), by the paper's first author.
- **License:** MIT, full text at [`External/CSpectralData/LICENSE`](External/CSpectralData/LICENSE)

> MIT License
>
> Copyright (c) 2019
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction… (see `External/CSpectralData/LICENSE` for
> the full text, including the warranty disclaimer).

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

## Blender matcaps

- **Used for:** the bundled built-in matcap (material-capture) sphere textures (`Matcap.chrome`, `.clay`, `.toon`, …), sampled by the view-space normal by `matcap(_:)` to shade a 3D mesh.
- **Location in this repo:** [`Sources/Ollin/Resources/Matcaps/`](Sources/Ollin/Resources/Matcaps/) (per-file mapping + provenance in [`Sources/Ollin/Resources/Matcaps/Matcaps-LICENSE.txt`](Sources/Ollin/Resources/Matcaps/Matcaps-LICENSE.txt))
- **Upstream:** the matcaps bundled with Blender — https://projects.blender.org/blender/blender/src/branch/main/release/datafiles/studiolights/matcap (each source `.exr` was combined from its diffuse + specular passes into a single sRGB PNG at native 512×512)
- **License:** CC0 1.0 / public domain — per the upstream [`license.txt`](https://projects.blender.org/blender/blender/src/branch/main/release/datafiles/studiolights/matcap/license.txt)

> These matcap images are licensed as CC0 or public domain. Thanks to the Blender
> community for contributing these matcaps. CC0 carries no attribution requirement;
> the credit above is given freely, and provenance is recorded for the bundled assets.

---

## Bundled HDRI environments

- **Used for:** the built-in HDRI environment maps that light 3D surfaces through image-based lighting. **Eight are bundled** in this repo (`Environment.studio`, `.city`, `.courtyard`, `.forest`, `.interior`, `.night`, `.sunrise`, `.sunset`), loaded at runtime. A curated dozen more (`.day`, `.dusk`, `.snow`, …), plus any `highRes(_:)` 2K/4K/8K upgrade and any user `hdri(downloadURL:)`, **download on demand from Poly Haven** and are cached on the user's machine, not redistributed in this repo.
- **Location in this repo:** [`Sources/Ollin/Resources/Environments/`](Sources/Ollin/Resources/Environments/) (the eight bundled files; per-file mapping + provenance in [`Sources/Ollin/Resources/Environments/Environments-LICENSE.txt`](Sources/Ollin/Resources/Environments/Environments-LICENSE.txt))
- **Upstream:** two CC0 sources. Blender's bundled "world" studiolights (https://projects.blender.org/blender/blender/src/branch/main/release/datafiles/studiolights/world), themselves created by Greg Zaal from Poly Haven; and Poly Haven directly (https://polyhaven.com/hdris), by Greg Zaal and contributors. Each bundled file was resampled to 1024×512 and saved as a half-float PIZ OpenEXR (the most compact HDR format ImageIO decodes natively); the on-demand downloads come from Poly Haven at their native resolution.
- **License:** CC0 1.0 / public domain, per the upstream license pages ([Blender world](https://projects.blender.org/blender/blender/src/branch/main/release/datafiles/studiolights/world/license.txt), [Poly Haven](https://polyhaven.com/license)).

> These HDRIs are licensed as CC0 / public domain. Thanks to Greg Zaal, Poly Haven,
> and the Blender community. CC0 carries no attribution requirement; the credit above
> is given freely, and provenance is recorded for the bundled assets.

---

## LTC lookup tables

- **Used for:** area-light shading (`rectLight` / `diskLight` / `tubeLight`): the fitted linearly-transformed-cosine tables the lit-mesh fragments sample to approximate the GGX response of a glowing rectangle, disk, or tube.
- **Location in this repo:** [`Sources/Ollin/Resources/LTC/ltc_tables.bin`](Sources/Ollin/Resources/LTC/ltc_tables.bin) (conversion recipe + provenance in [`Sources/Ollin/Resources/LTC/LTC-NOTICE.txt`](Sources/Ollin/Resources/LTC/LTC-NOTICE.txt))
- **Upstream:** https://github.com/selfshadow/ltc_code (commit `31e5e96`), the reference implementation accompanying *Real-Time Polygonal-Light Shading with Linearly Transformed Cosines* (Eric Heitz, Jonathan Dupuy, Stephen Hill, and David Neubelt, SIGGRAPH 2016). The two 64×64 float tables from `fit/results/ltc.js`, repacked as raw little-endian float32 with no reordering.
- **License:** BSD 3-Clause; full text at [`Sources/Ollin/Resources/LTC/LTC-NOTICE.txt`](Sources/Ollin/Resources/LTC/LTC-NOTICE.txt)

> Copyright (c) 2017, Eric Heitz, Jonathan Dupuy, Stephen Hill and David Neubelt.
> All rights reserved.
>
> Redistribution and use in source and binary forms, with or without modification,
> are permitted provided that the conditions in the upstream license are met,
> including reproducing the copyright notice and referencing the paper… (see
> `LTC-NOTICE.txt` for the full text, including the warranty disclaimer).

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

- **Used for:** the `FilePlayer` and `SoundReactive` example sketches only: a sample audio clip, to demonstrate `AudioPlayer` reacting to a file and `Soundtrack` analyzing a video's audio. Not part of the Ollin framework; Ollin (and `OllinAudio`) bundle no audio themselves.
- **Location in this repo:** [`Examples/Audio/FilePlayer/fandanguito.m4a`](Examples/Audio/FilePlayer/fandanguito.m4a); it is also the audio track of [`Examples/Video/SoundReactive/voladores-fandanguito.mp4`](Examples/Video/SoundReactive/voladores-fandanguito.mp4) (see the *Voladores de Papantla* entry)
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

- **Used for:** the `VideoPlayback` and `SoundReactive` example sketches only: a sample video clip, to demonstrate `VideoPlayer` drawing a file as a live image and a soundtrack analyzer reacting to it. Not part of the Ollin framework; Ollin (and `OllinVideo`) bundle no video themselves.
- **Location in this repo:** [`Examples/Video/VideoPlayback/voladores.mp4`](Examples/Video/VideoPlayback/voladores.mp4); [`Examples/Video/SoundReactive/voladores-fandanguito.mp4`](Examples/Video/SoundReactive/voladores-fandanguito.mp4) is a further-trimmed excerpt paired with the *El Fandanguito* recording below as its soundtrack (the source video's own audio track is silent)
- **Work:** *Voladores de Papantla México* — a recording of the *Danza de los Voladores*, the Totonac pole-flying ritual dance from Papantla, Veracruz (performed at an exhibition in Mexico City, 2018). Filmed by José Millán (Wikimedia Commons user Jmillan325).
- **Upstream:** https://commons.wikimedia.org/wiki/File:Voladores_de_Papantla_M%C3%A9xico.webm
- **License:** CC BY-SA 4.0 — https://creativecommons.org/licenses/by-sa/4.0

> Licensed CC BY-SA 4.0 (Attribution-ShareAlike). Attribution is given above as
> required. **Changes:** a ~28-second excerpt was trimmed from the original
> 3-minute VP9/WebM file and re-encoded to H.264 MP4 at 960×540 (mono AAC audio)
> for AVFoundation playback and a small repository footprint; no other edits.
> The `SoundReactive` variant is a further 16-second excerpt of that trim,
> muxed with the *El Fandanguito* recording (see its own entry) as the audio
> track. As a ShareAlike work this clip remains under CC BY-SA 4.0: that
> obligation rides on the video file and its adaptations, not on Ollin's
> source, which stays MIT (the clip is merely bundled alongside it). The root
> [`LICENSE`](LICENSE) is unaffected.

---

## Sample photographs (example assets)

- **Used for:** the `OllinSamplePhotos` library, which the `Images`, `Color`, and `Effects` example sketches and the Guide's and reference's figures read so a filter, a mosaic, a dither, or a winding can be shown on a real picture. A product of its own, so an app that never imports it ships none of them; the `Ollin` framework itself bundles no photograph.
- **Location in this repo:** [`Sources/OllinSamplePhotos/Resources/`](Sources/OllinSamplePhotos/Resources/), nineteen JPEGs, re-encoded at quality 72 to 95 with the metadata stripped. The seventeen photographs are 1600 pixels on the long side: four faces cropped square from their originals, four whole figures kept in whatever frame holds the body, two tables seen from above, cropped square, four streets cropped to the largest square each original held, two landscapes at dusk kept wide at three to two, and a book page in its whole frame. The two surface textures are 1024-pixel squares, the size a GPU mips evenly. Each credit is also carried in code as `SamplePhoto.credit`.
- **`portrait.jpg`:** *Vibrant portrait of a woman in traditional Oaxaca attire* by Jhovani Morales, Oaxaca de Juárez, Mexico. https://www.pexels.com/photo/13402074/ (Pexels License).
- **`scarf.jpg`:** *An elderly woman with a scarf looks directly at viewer* by Matthew Stephenson, Oaxaca, Mexico. https://unsplash.com/photos/j6OYgSMVuiI — Unsplash License.
- **`profile.jpg`:** *Profile of a woman with a braided ponytail against a solid tan background* by Jessica Felicio, Berrien County, United States. https://unsplash.com/photos/QS9ZX5UnS14 — Unsplash License.
- **`marigolds.jpg`:** *Portrait of an elderly Mexican woman with vibrant cempasuchil flowers for Día de Muertos celebration* by Fernando Paleta, Mexico City, Mexico. https://www.pexels.com/photo/29302608/ (Pexels License).
- **`reaching.jpg`:** *Man Dancing Alone* by Los Muertos Crew, Mexico. https://www.pexels.com/photo/8854016/ (Pexels License).
- **`wrestler.jpg`:** *Masked wrestler triumphs in lively arena* by Juan TM, Santiago de Querétaro, Mexico. https://www.pexels.com/photo/30098566/ (Pexels License).
- **`dancer.jpg`:** *Graceful contemporary dancer posing barefoot in a flowing black skirt* by Gustavo Fring. https://www.pexels.com/photo/7447230/ (Pexels License).
- **`handstand.jpg`:** *Energetic breakdancer in urban setting performing a handstand mid-move* by Gabriel Jiménez. https://www.pexels.com/photo/26870547/ (Pexels License).
- **`breakfast.jpg`:** *Top view of a vibrant Oaxacan breakfast with various dishes on a wooden table* by Jorge Acre, Oaxaca de Juárez, Mexico. https://www.pexels.com/photo/17061842/ (Pexels License).
- **`desk.jpg`:** *flat-lay photography of MacBook, coffee-filled cup, book, and wristwatch* by Ben Kolde, Oxford, United States. https://unsplash.com/photos/H29h6a8j8QM (Unsplash License).
- **`alley.jpg`:** *Colorful Guanajuato Street Under Blue Sky* by Emanuel Estrada, Guanajuato, Mexico. https://www.pexels.com/photo/33880220/ (Pexels License).
- **`street.jpg`:** *Colorful Decorations over Street* by Jorge Acre, San Miguel de Allende, Mexico. https://www.pexels.com/photo/16625366/ (Pexels License).
- **`textiles.jpg`:** *multicolored textiles lot* by analuisa gamboa, Teotitlán del Valle, Oaxaca, Mexico. https://unsplash.com/photos/0ohjyDUIUq0 (Unsplash License).
- **`city.jpg`:** *people walking on street near brown concrete building during daytime* by Gerardo Martin Fernandez Vallejo, Guanajuato, Mexico. https://unsplash.com/photos/ukIew--AEOc (Unsplash License).
- **`page.jpg`:** *Shadows on Open Book* by Saliha Öner. https://www.pexels.com/photo/8466090/ (Pexels License).
- **`talavera.jpg`:** *Traditional tin glazed tilework with colorful pattern* by rotekirsche 20. https://www.pexels.com/photo/5438689/ (Pexels License).
- **`stone.jpg`:** *Textured Stone Wall Surface Close-Up* by Memet Öz. https://www.pexels.com/photo/36023243/ (Pexels License).
- **`headland.jpg`:** *Silhouette of Mountain Near Body of Waters* by Joe Leineweber, Loreto, Baja California Sur, Mexico. https://www.pexels.com/photo/12848727/ (Pexels License).
- **`boats.jpg`:** *boats in the water* by Elesban Landero Berriozábal, Cozumel, Quintana Roo, Mexico. https://unsplash.com/photos/ACQmpRYafPg (Unsplash License).
- **Licenses:** Unsplash License (https://unsplash.com/license); Pexels License (https://www.pexels.com/license/)

> Both licenses grant a free, worldwide license to download, copy, modify, and
> use the photographs, commercial use included, with no attribution required;
> the photographers are credited here and in code all the same. Both forbid
> selling unaltered copies and compiling the pictures into a competing stock
> service, and the Pexels License adds that an identifiable person may not be
> shown in a bad light or as endorsing anything, which is how they are used:
> as the picture under a filter, a screen, a winding, or a pose skeleton.
> **Changes:** each was resized to 1600 pixels on its long side, converted to
> sRGB, and re-encoded as JPEG with its metadata (location included) removed.
> The four faces were also cropped square around the subject, and `reaching`
> was cropped to bring the figure up in the frame; the other three figures keep
> the whole frame the photographer shot. Both tables were cropped square, the
> desk cropped in far enough that the print on the notebook can be read. No
> other edits. The desk photograph carries a notebook whose printed cover names
> its maker, which the text recognizer reads aloud in the `TextScan` example;
> that is incidental to a photograph of a desk and is not an endorsement. The licenses ride on the photographs, not on Ollin's code,
> which stays MIT. The root [`LICENSE`](LICENSE) is unaffected.

---

## Video Depth Anything, small (example model, built locally, not bundled)

- **Used for:** the `DepthContours` and `FootageDepth` example sketches and the `DepthTracker` and `DepthClip` they demonstrate: temporally consistent video depth over the live feed, and over a whole recording read ahead of time. Not part of the Ollin framework; Ollin (and `OllinVision`) bundle no model weights themselves.
- **Location in this repo:** none. Nobody publishes a Core ML build of this model, so [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) makes one on a developer's machine: [`Scripts/convert-video-depth.sh`](Scripts/convert-video-depth.sh) clones the upstream repository at a pinned commit, downloads the checkpoint, and [`Scripts/convert-video-depth.py`](Scripts/convert-video-depth.py) traces the model's streaming step into `VideoDepthAnythingSmallF16.mlpackage` and its 32-frame window into `VideoDepthAnythingSmallClipF16.mlpackage` (each checked against the upstream code), and writes `VideoDepthClipReference.bin`, the upstream clip inference over a fixed synthetic clip that the tests check the Swift scheduler against, all under the gitignored `Models/`. The upstream source is used only at conversion time, in that work directory; none of it is copied into this repository.
- **Work:** *Video Depth Anything: Consistent Depth Estimation for Super-Long Videos* (the **small** checkpoint, `video_depth_anything_vits.pth`), Sili Chen, Hengkai Guo, Shengnan Zhu, Feihu Zhang, Zilong Huang, Jiashi Feng, Bingyi Kang (CVPR 2025), https://arxiv.org/abs/2501.12375. Its temporal head builds on the AnimateDiff motion module (Yuwei Guo et al., Apache-2.0), which the upstream code credits in its own headers.
- **Upstream:** https://github.com/DepthAnything/Video-Depth-Anything (code, Apache-2.0) and https://huggingface.co/depth-anything/Video-Depth-Anything-Small (the checkpoint).
- **License:** Apache-2.0, https://www.apache.org/licenses/LICENSE-2.0 (the code and the small checkpoint; the Base and Large checkpoints are CC BY-NC 4.0 and are not used)

> Apache-2.0 applies to the checkpoint the script downloads and to the package
> it derives from it; nothing from the model is redistributed in this
> repository, so the root [`LICENSE`](LICENSE) is unaffected. The conversion
> script is Ollin's own work (MIT with the rest of the repository), written
> against the model's published inference, streaming and windowed.

---

## Depth Anything V2, small (example model — downloaded, not bundled)

- **Used for:** the `DepthRelief` example sketch only — a monocular depth-estimation model, to demonstrate `ModelTracker` running a custom Core ML model. Not part of the Ollin framework; Ollin (and `OllinVision`) bundle no model weights themselves.
- **Location in this repo:** none. The weights are **not committed**: [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) downloads them into the gitignored `Models/` directory on a developer's machine.
- **Work:** *Depth Anything V2* (the **small** checkpoint), Lihe Yang, Bingyi Kang, Zilong Huang, Zhen Zhao, Xiaogang Xu, Jiashi Feng, Hengshuang Zhao (2024) — in Apple's official Core ML conversion (`DepthAnythingV2SmallF16.mlpackage`).
- **Upstream:** https://huggingface.co/apple/coreml-depth-anything-v2-small (conversion), via Apple's model gallery https://developer.apple.com/machine-learning/models/ — original model https://github.com/DepthAnything/Depth-Anything-V2
- **License:** Apache-2.0 — https://www.apache.org/licenses/LICENSE-2.0 (the small checkpoint; the larger Depth Anything V2 checkpoints are CC BY-NC 4.0 and are not used)

> Apache-2.0 applies to the model weights the script downloads; nothing from the
> model is redistributed in this repository, so the root [`LICENSE`](LICENSE) is
> unaffected. This entry records the provenance of what the script fetches.

---

## YOLOv3-tiny (example model — downloaded, not bundled)

- **Used for:** the `ObjectDetection` example sketch only — an object-detection model (80 COCO classes), to demonstrate `ModelTracker`'s labeled-box surface. Not part of the Ollin framework; Ollin (and `OllinVision`) bundle no model weights themselves.
- **Location in this repo:** none. The weights are **not committed**: [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) downloads them into the gitignored `Models/` directory on a developer's machine.
- **Work:** *YOLOv3-tiny*, Joseph Redmon and Ali Farhadi — "YOLOv3: An Incremental Improvement" (2018) — in Apple's Core ML conversion (`YOLOv3TinyFP16.mlmodel`).
- **Upstream:** https://developer.apple.com/machine-learning/models/ (conversion) — original model https://github.com/pjreddie/darknet, https://pjreddie.com/darknet/yolo/
- **License:** YOLO License, Version 2 (a public-domain dedication: "Darknet is public domain. Do whatever you want with it.") — https://github.com/pjreddie/darknet/blob/master/LICENSE

> The YOLO License applies to the model the script downloads; nothing from the
> model is redistributed in this repository, so the root [`LICENSE`](LICENSE) is
> unaffected. This entry records the provenance of what the script fetches.

---

## MNIST drawing classifier (example model — downloaded, not bundled)

- **Used for:** the `DigitReader` example sketch only — a handwritten-digit classifier, to demonstrate `ModelTracker` reading a sketch's own pixel-authored drawing through the still `detect(in:)` path. Not part of the Ollin framework; Ollin (and `OllinVision`) bundle no model weights themselves.
- **Location in this repo:** none. The weights are **not committed**: [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) downloads them into the gitignored `Models/` directory on a developer's machine.
- **Work:** *MNISTClassifier* — Apple's Turi Create-trained drawing classifier from the Core ML model gallery, trained on the MNIST dataset of handwritten digits (LeCun, Cortes, Burges).
- **Upstream:** https://developer.apple.com/machine-learning/models/ — dataset http://yann.lecun.com/exdb/mnist/
- **License:** MIT (Copyright 2019 Apple Inc.) — https://docs-assets.developer.apple.com/coreml/models/Image/DrawingClassification/MNISTClassifier/LICENSE-MIT.txt

> MIT applies to the model the script downloads; nothing from the model is
> redistributed in this repository, so the root [`LICENSE`](LICENSE) is
> unaffected. This entry records the provenance of what the script fetches.
> (The `StyleMirror` example needs no entry here at all: its style-transfer
> model is trained by the user — `Scripts/train-style-model.swift`, over the
> CreateML framework — so the weights are the user's own work; nothing is
> fetched or redistributed.)

---

## DeepLabV3 (example model — downloaded, not bundled)

- **Used for:** the `PaintByClass` example sketch only — a semantic-segmentation model (21 PASCAL VOC classes), to demonstrate `ModelTracker`'s class-mask surface. Not part of the Ollin framework; Ollin (and `OllinVision`) bundle no model weights themselves.
- **Location in this repo:** none. The weights are **not committed**: [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) downloads them into the gitignored `Models/` directory on a developer's machine.
- **Work:** *DeepLabV3* (MobileNetV2 backbone), Liang-Chieh Chen, Yukun Zhu, George Papandreou, Florian Schroff, Hartwig Adam — "Encoder-Decoder with Atrous Separable Convolution for Semantic Image Segmentation" (2018) — in Apple's Core ML conversion (`DeepLabV3FP16.mlmodel`).
- **Upstream:** https://developer.apple.com/machine-learning/models/ (conversion) — original model https://github.com/tensorflow/models/tree/master/research/deeplab (TensorFlow)
- **License:** Apache-2.0 — https://github.com/tensorflow/models/blob/master/LICENSE (per the model's own embedded license metadata, which points at the TensorFlow repositories)

> Apache-2.0 applies to the model weights the script downloads; nothing from the
> model is redistributed in this repository, so the root [`LICENSE`](LICENSE) is
> unaffected. This entry records the provenance of what the script fetches.

---

## MobileCLIP-S0 (example model, downloaded, not bundled)

- **Used for:** `ConceptTracker` and its `TugOfWords` example sketch. The framework provides no bundled weights.
- **Location in this repo:** none. [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) downloads the weights into the gitignored `Models/` directory.
- **Work:** *MobileCLIP-S0* (CVPR 2024), by Pavan Kumar Anasosalu Vasu, Hadi Pouransari, Fartash Faghri, Raviteja Vemulapalli, and Oncel Tuzel, in Apple's Core ML exports (`mobileclip_s0_image.mlpackage`, `mobileclip_s0_text.mlpackage`).
- **Upstream:** https://huggingface.co/apple/coreml-mobileclip (export); original release https://github.com/apple/ml-mobileclip
- **License:** the 2024 release's `LICENSE_weights_data`: redistributable with attribution; no research-only clause. The export's model card declares `apple-ascl`. The fetch script uses the 2024 model (MobileCLIP2 is research-only).

> The license applies to the downloaded weights. This repository does not
> redistribute them; the root [`LICENSE`](LICENSE) is unaffected.

---

## Segment Anything 2.1 (example model, downloaded, not bundled)

- **Used for:** `PointSegmenter` and its `PointLift` example sketch. The framework provides no bundled weights.
- **Location in this repo:** none. [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) downloads the weights into the gitignored `Models/` directory.
- **Work:** *SAM 2: Segment Anything in Images and Videos* (2024), Nikhila Ravi, Valentin Gabeur, Yuan-Ting Hu, Ronghang Hu, Chaitanya Ryali, Tengyu Ma, Haitham Khedr, Roman Rädle, Chloe Rolland, Laura Gustafson, Eric Mintun, Junting Pan, Kalyan Vasudev Alwala, Nicolas Carion, Chao-Yuan Wu, Ross Girshick, Piotr Dollár, Christoph Feichtenhofer (Meta AI): the 2.1 "small" checkpoint, in Apple's official Core ML conversion, split as `SAM2_1SmallImageEncoderFLOAT16.mlpackage`, `SAM2_1SmallPromptEncoderFLOAT16.mlpackage`, and `SAM2_1SmallMaskDecoderFLOAT16.mlpackage`.
- **Upstream:** https://huggingface.co/apple/coreml-sam2.1-small (conversion); original release https://github.com/facebookresearch/sam2
- **License:** Apache-2.0 (both the original release and the Core ML conversion's model card).

> Apache-2.0 applies to the model weights the script downloads; nothing from the
> model is redistributed in this repository, so the root [`LICENSE`](LICENSE) is
> unaffected. This entry records the provenance of what the script fetches.

---

## CLIP byte-pair-encoding vocabulary (example data, downloaded, not bundled)

- **Used for:** `ConceptTracker`'s tokenizer (`PhraseTokenizer`), which turns a typed phrase into the token sequence the text encoder expects. The tokenizer implementation is Ollin's own, credited in [`ATTRIBUTION.md`](ATTRIBUTION.md); this entry covers the vocabulary file.
- **Location in this repo:** none. [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) downloads `bpe_simple_vocab_16e6.txt.gz` into the gitignored `Models/` directory and unpacks it.
- **Work:** the byte-pair-encoding merges file from OpenAI's CLIP tokenizer. MobileCLIP's text encoder was trained on this vocabulary.
- **Upstream:** https://github.com/openai/CLIP (`clip/bpe_simple_vocab_16e6.txt.gz`)
- **License:** MIT (Copyright 2021 OpenAI): https://github.com/openai/CLIP/blob/main/LICENSE

> The license applies to the downloaded file. This repository does not
> redistribute it; the root [`LICENSE`](LICENSE) is unaffected.

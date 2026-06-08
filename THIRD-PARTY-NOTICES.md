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

## Open Goldberg Variations (example audio)

- **Used for:** the `FilePlayer` example sketch only — a sample audio clip, to demonstrate `AudioPlayer` reacting to a file. Not part of the Ollin framework; Ollin (and `OllinAudio`) bundle no audio themselves.
- **Location in this repo:** [`Examples/Audio/FilePlayer/goldberg.m4a`](Examples/Audio/FilePlayer/goldberg.m4a)
- **Work:** J.S. Bach, *Goldberg Variations*, BWV 988 (an ~18-second excerpt of Variation 4), performed by Kimiko Ishizaka.
- **Upstream:** https://archive.org/details/OpenGoldbergVariations — the Open Goldberg Variations project (https://opengoldbergvariations.org)
- **License:** CC0 1.0 (Public Domain Dedication) — https://creativecommons.org/publicdomain/zero/1.0/

> The Open Goldberg Variations recording was deliberately released into the public
> domain under CC0, which carries no attribution requirement; the credit above is
> given freely. The bundled file is a short excerpt, trimmed and re-encoded to AAC.

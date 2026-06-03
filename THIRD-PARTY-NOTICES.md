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

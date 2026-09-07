# The Ollin mark

Ollin is the Aztec day sign for movement: two bands crossing, four lobes around them, and an eye at the center. The mark keeps that reading in plain geometry. Two rounded bars cross at the center, an eye sits where they meet, and four small marks stand at the cardinal points, each ending the same distance from the center, so the whole sits in a square.

## The files

| File | What it is |
|---|---|
| [`ollin-mark.svg`](ollin-mark.svg) | The full mark, ink on nothing. For a light background. |
| [`ollin-mark-dark.svg`](ollin-mark-dark.svg) | The same drawing in paper, for a dark background. |
| [`ollin-favicon.svg`](ollin-favicon.svg) | The small form on its dark tile. The favicon, and any icon under about 32 px. |
| [`ollin-favicon-light.svg`](ollin-favicon-light.svg) | The small form on a paper tile. |

Every file is drawn in a 100 by 100 box. The bars are 84 by 20 with fully rounded ends, turned 45 degrees each way about the center; the eye is a ring of radius 14 around a dot of radius 5.5. The full mark draws with a 5 unit stroke and carries a chevron above, a small ring below, and an arc to each side. The small form draws with a 9 unit stroke, drops the satellites, and puts a dot of radius 4.5 at each cardinal point instead, which is what still reads at 16 px.

The bars are cut away under the eye with a mask rather than covered by a filled disc, so the drawings are transparent outside their ink and sit on any background. On the design's paper they draw the same picture the filled disc did.

## The colors

Ink is `#0B0F14` and paper is `#F4F3F0`. Where the mark sits on a page of its own, the site draws it in the page's text color instead, so it follows the reader's light or dark setting. The README shows the light drawing and switches to the dark one with the reader's setting.

## Where it comes from

The mark was drawn in Claude Design with [@eaviles](https://github.com/eaviles) directing, across fourteen rounds of variations; the full mark is the round 14 form he settled on, and the small form is the favicon from round 8. The files here are written from those drawings.

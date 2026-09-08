# The Ollin mark

Ollin is the Aztec day sign for movement: two bands crossing, four lobes around them, and an eye at the center. The mark keeps that reading in plain geometry. Two rounded bars cross at the center, an eye sits where they meet, and four small marks stand at the cardinal points, each ending the same distance from the center, so the whole sits in a square.

## The files

Two masters, drawn in Sketch and exported here, and one file written from them.

| File | What it is |
|---|---|
| [`ollin-mark.svg`](ollin-mark.svg) | The full mark. A master. |
| [`ollin-favicon.svg`](ollin-favicon.svg) | The small form: heavier lines, no satellites, a dot at each cardinal point. A master, and the one to use under about 32 px. |
| [`ollin-mark-dark.svg`](ollin-mark-dark.svg) | The full mark in paper, for the README on GitHub. Written by `Scripts/logo.sh`, never edited. |

Both masters are black ink on nothing. Every shape is a filled outline, no color is written into the file, and the background is transparent. A drawing takes whatever color is set on it and sits on any ground. The full mark is drawn in a 100 by 100 box, the small form in a 14 by 14 box.

## The geometry

In the full mark's box, the bars are 20 units wide with fully rounded ends, turned 45 degrees each way about the center. They stop 22 units from it. The eye is a ring of radius 14 around a dot of radius 5.5. A chevron sits above, a small ring of radius 6 below, and an arc to each side. Every line is 5 units wide, drawn as an outline, so the crossing is cut in the shapes themselves and nothing is masked or covered.

The small form keeps the bars, cut 26 units from the center on the same scale, and the eye, with every line 9 units wide. It drops the satellites and puts a dot of radius 4.5 at each cardinal point instead, which is what still reads at 16 px.

## The colors

The masters carry none. Where the site draws the mark, ink is `#0B0F14` and paper is `#F4F3F0`. In a page the drawing is inlined with `currentColor`, so it takes the page's text color and follows the reader's light or dark setting. The favicon is the small form in paper on an ink tile, since a tab bar is whatever color the browser makes it. The README shows the master and switches to the paper twin with the reader's setting.

## After an export

Export the drawing from Sketch over its master, then run `Scripts/logo.sh`. It cleans both masters in place and writes the dark twin. The XML prolog, the title, the editor ids, the pixel size, the written-out black, and the group's offset go. Coordinates round to five decimals, and the layout stays readable. The site's tests check the twin against the master, and the masters for an export's leftovers. A re-export that skips the script fails there.

## Where it comes from

The mark was drawn in Claude Design with [@eaviles](https://github.com/eaviles) directing, across fourteen rounds of variations; the full mark is the round 14 form he settled on, and the small form is the favicon from round 8. He then redrew both in Sketch as the outlines here, and the files are its exports, cleaned.

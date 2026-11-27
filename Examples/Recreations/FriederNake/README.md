#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Frieder Nake</sup>

---

## Frieder Nake

| [![HommageAPaulKlee](https://media.ollin.art/examples/Recreations/FriederNake/HommageAPaulKlee/still-640.jpg?v=4b1402e3)](HommageAPaulKlee/) | [![RandomPolygon](https://media.ollin.art/examples/Recreations/FriederNake/RandomPolygon/still-640.jpg?v=071ef2ca)](RandomPolygon/) | [![WalkThroughRaster](https://media.ollin.art/examples/Recreations/FriederNake/WalkThroughRaster/still-640.jpg?v=1f3aa7da)](WalkThroughRaster/) |  |
|---|---|---|---|
| [HommageAPaulKlee](HommageAPaulKlee/) | [RandomPolygon](RandomPolygon/) | [WalkThroughRaster](WalkThroughRaster/) |  |

| Born | Wing |
|---|---|
| Stuttgart, 1938 | [Chance](../README.md#chance) |

### His life

**Frieder Nake** is a German mathematician who studied at the Technische Hochschule Stuttgart and took his doctorate in probability theory. In 1965, working at the school's computing center, he wrote programs in machine language for the Standard Elektrik Lorenz ER56 and drew their output on a **Zuse Graphomat Z64** flatbed plotter, the same machine Georg Nees used. He showed the results at Galerie Wendelin Niedlich in Stuttgart in November 1965, beside Nees's plates; with Nees and A. Michael Noll he is one of the "3N" who exhibited computer art first. He estimates he made three or four hundred plotter works between 1965 and 1969. He names their phases after the programs behind them: the package *compArt ER56* (1963 to 1965), *Walk-through-raster* (1966), *Matrix multiplication* (1967 and 1968), and *Generative aesthetics I* (1968 and 1969). His book *Ästhetik als Informationsverarbeitung* (1974) was one of the first to connect aesthetics, computing, and information theory, and he has been a professor of interactive computer graphics at the University of Bremen since 1972.

### What he made

**"13/9/65 Nr. 2" (1965)** is his best-known drawing, usually called *Hommage à Paul Klee* after the painting that set it going, Klee's *Hauptweg und Nebenwege* (1929, Museum Ludwig, Cologne). Ink on paper, 50 by 50 centimeters, with a screenprint edition of forty the next year, it is one of the most reproduced images of the first computer art. The sheet is cut into horizontal bands of unequal width whose edges bend from vertex to vertex on the way across, never crossing. Every quadrilateral in a band is left empty, filled with vertical lines, or set with triangles, and a handful of circles is thrown over the whole. Nake listed the chance decisions himself, in *Programm-Information* PI-21: the band widths at the left edge, the buckling of the edges, the choice for each quadrilateral, the number and place of its signs, and the number, place, and size of the circles. It is not a simulation of Klee, and he has said so: the painting has no circles, and its rhythm runs the other way.

**"13/9/65 Nr. 3" and "Nr. 7" (1965)**, both titled *Zufälliger Polygonzug* (random polygon), carry the same date as the Klee drawing and come from the same package of programs. Each is a single line. A random polygon is the simplest program there is: from the current point, draw an edge whose direction and length are chosen by chance, and stay on the sheet. The usual version lets the line leave in any direction with the same chance. Here the choice is restricted, as the compArt database describes it: "Only the horizontal, two oblique directions, and slight deviations from the vertical were permitted." That one restriction makes the sheet look composed, with parallels, triangles, and bundles of long uprights. PI-21 lists what was rolled: the number of vertices, the direction of each edge, and its length. The two drawings share one program and one set of settings.

***Walk-Through-Raster* (1966)** is a program more than a picture. He wrote it in ALGOL 60 for the Telefunken TR4 and drew its output on the same Graphomat, in series he numbered. A FORTRAN IV version for an IBM 360/65 and a Calcomp plotter made the screenprint in the *Art Ex Machina* portfolio (Gilles Gheerbrant, Montréal, 1972). In May 2021 he described the program in a short note, without mathematics. It needs five things: a repertoire of signs, a picture plane covered by a grid of cells, a way to choose the first sign, a transition probability that chooses each next sign from the one before it, and a set of mapping modes. A mapping mode is a rule for which cell comes next. The program makes a chain of signs and then lays the chain into the cells along one of the modes. His own summary of the method is "Think the image, don't make it!"

The note shows four small pictures that share one repertoire: a short horizontal stroke, a vertical stroke of the same length, and the empty sign. In each the empty sign is likely at the start, the vertical stroke gains on it until the middle of the chain, and the empty sign comes back toward the end. Only the mapping mode differs: diagonals, hooks along the top and down the left side, plain rows, and a square spiral toward the center. So the same thin, dense, thin chain lands in four different places.

The note gives no numbers. The ones in the sketch were read off the Victoria and Albert Museum's photograph of one drawing of the series, the diagonal one, by counting its cells. It has 50 by 50 of them: 1,593 hold the common stroke, 255 the rare one, and 652 are empty. No cell holds two strokes, and a stroke lies on an edge of its cell, which is why neighbors join into long lines and corners. Along the walk the empty sign falls from about three cells in four at the corners to one in a hundred across the middle. The rare stroke stays near one in ten. A count could find no sign leaning on the one before it, so in that drawing every row of the table seems to have been the same. The photograph appears to show the sheet a quarter turn from the way the note prints it. The sketch follows the note.

### Rebuilding his work

For his best-known drawing he listed every chance decision the program made, and for *Walk-Through-Raster* he left a note on how the chain is rolled. Those are enough to write the programs again, with the numbers the note leaves out read off a museum's photograph. Two of the sketches open finished, clear, and draw themselves again at the speed of a pen.

- [**HommageAPaulKlee**](HommageAPaulKlee/): the bands, their buckled edges, the rolled choice for every quadrilateral, and the circles, after Nake's *13/9/65 Nr. 2*.

  An original Ollin interpretation written from the work and from Nake's own list of its chance decisions. `sheetSeed` is the whole piece and every seed is a new sheet; `buckling`, `density`, and `circles` are dials on the rolls.

  ```sh
  swift run Example-Recreations-FriederNake-HommageAPaulKlee
  ```

  The plotter drawing back, as strokes:

  ```sh
  swift run Example-Recreations-FriederNake-HommageAPaulKlee --export-svg sheet.svg
  ```

- [**RandomPolygon**](RandomPolygon/): one line inside a frame, after the two *Zufälliger Polygonzug* drawings.

  At every vertex it rolls a kind of direction (level, one of two obliques, or an upright that may lean a little), which way to take it, and a length. An edge that would leave the frame stops on it. The sheet opens finished, clears, and the pen draws the line again at one speed. `sheetSeed` is the whole piece. `uprights` is the share of near-vertical edges, `oblique` the angle of the slanted ones, `lean` how far an upright may tip, `span` the mean length of an edge, `reach` how much longer the uprights run, and `vertices` about how many corners the line has. An original Ollin interpretation written from the database's description and from PI-21's list. The weights, the angle, the lengths, and the rule at the frame are the sketch's own, tuned by eye against the two sheets.

  ```sh
  swift run Example-Recreations-FriederNake-RandomPolygon
  ```

  The line as one stroke, for a pen:

  ```sh
  swift run Example-Recreations-FriederNake-RandomPolygon --export-svg polygon.svg
  ```

- [**WalkThroughRaster**](WalkThroughRaster/): the four pictures of his note on one sheet.

  Each is a chain of 2,500 signs rolled from one table that moves along the chain, laid into a raster of 50 by 50 cells along its own walk. The sheet opens finished, clears, and the four walks lay their chains again side by side, a red mark on the cell each has reached. `sheet` shows the four together or one walk large. `sheetSeed` rolls new chains. `swell` is how soon a chain fills, `strays` the chance of each stroke at its two ends, and `memory` the share of the table that repeats the sign before, which is 0 in the drawing that was counted. `cells` sets the raster. An original Ollin interpretation written from his note. The table's numbers and the edge each stroke lies on are readings off the photograph.

  ```sh
  swift run Example-Recreations-FriederNake-WalkThroughRaster
  ```

  One walk large, as strokes for a pen, with joined strokes drawn as one line:

  ```sh
  swift run Example-Recreations-FriederNake-WalkThroughRaster --param sheet=rows --export-svg rows.svg
  ```

  One whole lap, which loops exactly:

  ```sh
  swift run Example-Recreations-FriederNake-WalkThroughRaster --export-loop raster.mp4
  ```

### Further reading

- [Frieder Nake on Wikipedia](https://en.wikipedia.org/wiki/Frieder_Nake)
- [*13/9/65 Nr. 2* in the compArt database of digital art](http://dada.compart-bremen.de/item/artwork/414), which quotes the list of random decisions
- [*Hommage à Paul Klee* in the Victoria and Albert Museum collection](https://collections.vam.ac.uk/item/O211685/hommage-a-paul-klee-13965-print-nake-frieder/)
- [*13/9/65 Nr. 3 "Zufälliger Polygonzug"*](http://dada.compart-bremen.de/item/artwork/1326) and [*Nr. 7*](http://dada.compart-bremen.de/item/artwork/405) in the compArt database, with the description of the restricted directions, and [the sheet of Nr. 3 in the Victoria and Albert Museum](https://collections.vam.ac.uk/item/O1258796/zufalliger-polygon-plotter-drawing-frieder-nake/)
- [*Walk-Through-Raster* at the Digital Art Museum](https://dam.org/museum/artists_ui/artists/nake-frieder/walk-through-raster/), with his note ["Walk-through-Raster, a Generative Aesthetics from 1966"](https://dam.org/museum/wp-content/uploads/2021/05/FN_WalkThroughRaster.pdf) (May 2021)
- [*Walk-Through-Raster, series 2.1-4* in the Victoria and Albert Museum collection](https://collections.vam.ac.uk/item/O214165/walk-through-raster-series-2-photograph-nake-frieder/), the photograph the cells were counted on

### About these homages

This is a homage after Frieder Nake, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist.

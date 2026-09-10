#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Frieder Nake</sup>

---

## Frieder Nake

| [![HommageAPaulKlee](https://media.ollin.art/examples/Recreations/FriederNake/HommageAPaulKlee/still-640.jpg?v=4b1402e3)](HommageAPaulKlee/) |  |  |  |
|---|---|---|---|
| [HommageAPaulKlee](HommageAPaulKlee/) |  |  |  |

**Frieder Nake** (born 1938, Stuttgart) is a German mathematician who studied at the Technische Hochschule Stuttgart and took his doctorate in probability theory. In 1965, working at the school's computing center, he wrote programs in machine language for the Standard Elektrik Lorenz ER56 and drew their output on a **Zuse Graphomat Z64** flatbed plotter, the same machine Georg Nees used. He showed the results at Galerie Wendelin Niedlich in Stuttgart in November 1965, beside Nees's plates; with Nees and A. Michael Noll he is one of the "3N" who exhibited computer art first. He estimates he made three or four hundred plotter works between 1965 and 1969. His book *Ästhetik als Informationsverarbeitung* (1974) was one of the first to connect aesthetics, computing, and information theory, and he has been a professor of interactive computer graphics at the University of Bremen since 1972.

**"13/9/65 Nr. 2" (1965)** is his best-known drawing, usually called *Hommage à Paul Klee* after the painting that set it going, Klee's *Hauptweg und Nebenwege* (1929, Museum Ludwig, Cologne). Ink on paper, 50 by 50 centimeters, with a screenprint edition of forty the next year, it is one of the most reproduced images of the first computer art. The sheet is cut into horizontal bands of unequal width whose edges bend from vertex to vertex on the way across, never crossing. Every quadrilateral in a band is left empty, filled with vertical lines, or set with triangles, and a handful of circles is thrown over the whole. Nake listed the chance decisions himself, in *Programm-Information* PI-21: the band widths at the left edge, the buckling of the edges, the choice for each quadrilateral, the number and place of its signs, and the number, place, and size of the circles. It is not a simulation of Klee, and he has said so: the painting has no circles, and its rhythm runs the other way.

Learn more:

- [Frieder Nake on Wikipedia](https://en.wikipedia.org/wiki/Frieder_Nake)
- [*13/9/65 Nr. 2* in the compArt database of digital art](http://dada.compart-bremen.de/item/artwork/414), which quotes the list of random decisions
- [*Hommage à Paul Klee* in the Victoria and Albert Museum collection](https://collections.vam.ac.uk/item/O211685/hommage-a-paul-klee-13965-print-nake-frieder/)

### Recreations here

- [**HommageAPaulKlee**](HommageAPaulKlee/): the bands, their buckled edges, the rolled choice for every quadrilateral, and the circles, after Nake's *13/9/65 Nr. 2*. An original Ollin interpretation written from the work and from Nake's own list of its chance decisions. `sheetSeed` is the whole piece and every seed is a new sheet; `buckling`, `density`, and `circles` are dials on the rolls.

  ```sh
  swift run Example-Recreations-FriederNake-HommageAPaulKlee
  ```

  The plotter drawing back, as strokes:

  ```sh
  swift run Example-Recreations-FriederNake-HommageAPaulKlee --export-svg sheet.svg
  ```

This is a homage after Frieder Nake, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist.


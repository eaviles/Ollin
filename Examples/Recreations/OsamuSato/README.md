#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Osamu Sato</sup>

---

## Osamu Sato

| [![Alphabet](https://media.ollin.art/examples/Recreations/OsamuSato/Alphabet/still-640.jpg?v=543c2329)](Alphabet/) | [![StraightLines](https://media.ollin.art/examples/Recreations/OsamuSato/StraightLines/still-640.jpg?v=c1bd0a64)](StraightLines/) | [![Totem](https://media.ollin.art/examples/Recreations/OsamuSato/Totem/still-640.jpg?v=538b7d5a)](Totem/) | [![TotemBuilder](https://media.ollin.art/examples/Recreations/OsamuSato/TotemBuilder/still-640.jpg?v=598eeb50)](TotemBuilder/) |
|---|---|---|---|
| [Alphabet](Alphabet/) | [StraightLines](StraightLines/) | [Totem](Totem/) | [TotemBuilder](TotemBuilder/) |

**Osamu Sato** (佐藤理, b. 1960) is a Japanese multimedia artist, designer, and musician. He is known for surreal, dreamlike digital work built from a vocabulary of simple shapes and ancient-feeling symbols. That work includes the PlayStation cult titles *LSD: Dream Emulator* (1998) and *Eastern Mind: The Lost Souls of Tong Nou* (1994), and his electronic music.

His book **_The Art of Computer Designing: A Black and White Approach_** (1993, Graphic-Sha; reissued by Colpa Press) is a guide and compendium. It builds designs entirely out of basic vector shapes, with a chapter for each family: straight lines, curves, squares, and circles. Everything is in bold black and white with a single red accent. The original edition shipped with a **3.5″ floppy disk** of the work. The recreations here draw on three of its chapters: "Straight Lines", "Squares", and "Circles". They are written from the printed pages, and the disk was never used.

Learn more:

- [Osamu Sato on Wikipedia](https://en.wikipedia.org/wiki/Osamu_Sato)
- [*The Art of Computer Designing* scanned on the Internet Archive](https://archive.org/details/satoArtOfComputerDesigning)
- [The Colpa Press reissue](https://www.colpapress.com/products/the-art-of-computer-designing-osamu-sato)

### Recreations here

- [**Totem**](Totem/): a symmetric "computer totem" after the figures of the book's "Circles" chapter. It is assembled from Ollin's analytic SDF primitives. Around the core circle/ring/moon set it adds a horseshoe crown and ears, a parabola finial, a tunnel torso, a blobby-cross heart, cool-S ornaments, tapered-capsule legs, and a stairs pedestal.

  ```sh
  swift run Example-Recreations-OsamuSato-Totem
  ```

- [**Alphabet**](Alphabet/): a type-specimen sheet of A–Z and 0–9 in a square-module font, after the shape-built alphabets of the book's "Squares" chapter. Each glyph is a 5×7 grid of `drawRect` squares. The squares shimmer on a traveling wave, and a red accent sweeps through the glyphs.

  ```sh
  swift run Example-Recreations-OsamuSato-Alphabet
  ```

- [**StraightLines**](StraightLines/): the eye of the "Straight Lines" chapter, captioned "An eyeball, created with nothing but straight lines", framed by a word set in hatched letters. The chapter's moves are the whole method. Each lid is one bent line copied five times, the blocks around the eye are one block rotated sixteen times, and everything is mirrored both ways. Every angle is a whole multiple of 3.75 degrees. The pupil turns a click at a time, the lids blink by folding their copies into one line, and once a cycle the page is taken apart down to one line and built again. Type a word into `word` and the letters spell it. `--export-svg` gives back nothing but straight segments.

  ```sh
  swift run Example-Recreations-OsamuSato-StraightLines
  ```

- [**TotemBuilder**](TotemBuilder/): "a monster made of a circle", built from the pieces the "Circles" chapter takes its opening figure apart into: hands, feet, a tail, eyes, an antenna, a nose, a mouth, a neck, ears, a face, and a body. Each piece has a few forms made the chapter's way, by cutting circles, mirroring, or rotating. Every mark is a disk, a ring, a crescent, or a lens, and at most one piece is red. The seed deals one form of each piece and the proportions, so every seed is a different monster. A pulse runs down the circles of his face and body, he blinks, and his hands wave together. Proof a day's pile with `--export-grid`.

  ```sh
  swift run Example-Recreations-OsamuSato-TotemBuilder
  swift run Example-Recreations-OsamuSato-TotemBuilder --export-grid pile.png --seeds 16
  ```

These are homages after Osamu Sato, made for learning. They aren't reproductions of specific works, and they aren't affiliated with or endorsed by the artist.

#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Osamu Sato</sup>

---

## Osamu Sato

| [![Alphabet](https://media.ollin.art/examples/Recreations/OsamuSato/Alphabet/still-640.jpg?v=543c2329)](Alphabet/) | [![StraightLines](https://media.ollin.art/examples/Recreations/OsamuSato/StraightLines/still-640.jpg?v=c1bd0a64)](StraightLines/) | [![Totem](https://media.ollin.art/examples/Recreations/OsamuSato/Totem/still-640.jpg?v=538b7d5a)](Totem/) | [![TotemBuilder](https://media.ollin.art/examples/Recreations/OsamuSato/TotemBuilder/still-640.jpg?v=598eeb50)](TotemBuilder/) |
|---|---|---|---|
| [Alphabet](Alphabet/) | [StraightLines](StraightLines/) | [Totem](Totem/) | [TotemBuilder](TotemBuilder/) |

| Born | Lives in | Wing |
|---|---|---|
| Kyoto, 1960 | Tokyo | [Signs and letters](../README.md#signs-and-letters) |

### His life

**Osamu Sato** (佐藤理) is a Japanese multimedia artist, designer, and musician. He was born in Kyoto. His father and grandfather were photographers, there was a darkroom in the house, and he had a camera from when he was small. He studied design and photographic science at two schools and spent most of that time printing silkscreens. His first release, in 1983, was a cassette of his music sold in one package with a silkscreen print.

He worked for an advertising company, went freelance, and at the end of the 1980s set up a design office in Tokyo, which became OutSide Directors Company. He bought a Macintosh II, which then cost about four million yen, and Adobe Illustrator, which had just come out and could draw curves. He used them first to design logos. His first solo exhibition, *The Alphabetical Orgasm*, opened in Tokyo in November 1991, and in 1993 he published the book the sketches here are built from. The same year a demo he had put on a floppy disk won the grand prize in a contest run by Sony Music, and in 1994 Sony Music published his first game.

He is known for surreal, dreamlike digital work built from a vocabulary of simple shapes and ancient-feeling symbols. That work includes two cult games and his electronic music. *Eastern Mind: The Lost Souls of Tong Nou* (1994) was a CD-ROM for personal computers. *LSD: Dream Emulator* (1998), for the PlayStation, took its material from a dream diary one of his staff had kept for years. He lives and works in Tokyo, where he goes on showing photographs and graphics and releasing records.

### What he made

His book **_The Art of Computer Designing: A Black and White Approach_** (1993, Graphic-sha; reissued by Colpa Press in 2020) is a guide and compendium. It builds designs out of basic shapes, and its first four chapters take one family each: straight lines, curves, squares, and circles. Each of those chapters goes through the same few moves, dividing and combining, symmetry, and rotation, and then makes pictures and an alphabet with them. The lesson pages are in bold black and white with one red ink. He made the book on a Macintosh in Adobe Illustrator, and Wired reported that it took five weeks. "You don't create by following directions," its afterword says. "You create because you want to make something new."

The original edition shipped with a **3.5″ floppy disk** for the Macintosh: an animation with sound, pictograms to open in Illustrator, and the typeface from the cover. The recreations here draw on three of its chapters: "Straight Lines", "Squares", and "Circles". They are written from the printed pages, and the disk was never used.

### Rebuilding his work

Each of the book's first chapters takes one kind of shape and builds its designs with a few moves: copy, mirror, rotate, cut. Those are the moves a sketch has, and the shapes are ones the framework draws exactly. The four sketches here follow the chapters' own steps, and in one of them a seed deals the pieces, so every seed is a different monster.

- [**Totem**](Totem/): a symmetric "computer totem" after the figures of the book's "Circles" chapter.

  It is assembled from Ollin's analytic SDF primitives. Around the core circle/ring/moon set it adds a horseshoe crown and ears, a parabola finial, a tunnel torso, a blobby-cross heart, cool-S ornaments, tapered-capsule legs, and a stairs pedestal.

  ```sh
  swift run Example-Recreations-OsamuSato-Totem
  ```

- [**Alphabet**](Alphabet/): a type-specimen sheet of A–Z and 0–9 in a square-module font, after the shape-built alphabets of the book's "Squares" chapter.

  Each glyph is a 5×7 grid of `drawRect` squares. The squares shimmer on a traveling wave, and a red accent sweeps through the glyphs.

  ```sh
  swift run Example-Recreations-OsamuSato-Alphabet
  ```

- [**StraightLines**](StraightLines/): the eye of the "Straight Lines" chapter, captioned "An eyeball, created with nothing but straight lines", framed by a word set in hatched letters.

  The chapter's moves are the whole method. Each lid is one bent line copied five times, the blocks around the eye are one block rotated sixteen times, and everything is mirrored both ways. Every angle is a whole multiple of 3.75 degrees. The pupil turns a click at a time, the lids blink by folding their copies into one line, and once a cycle the page is taken apart down to one line and built again. Type a word into `word` and the letters spell it. `--export-svg` gives back nothing but straight segments.

  ```sh
  swift run Example-Recreations-OsamuSato-StraightLines
  ```

- [**TotemBuilder**](TotemBuilder/): "a monster made of a circle", built from the pieces the "Circles" chapter takes its opening figure apart into: hands, feet, a tail, eyes, an antenna, a nose, a mouth, a neck, ears, a face, and a body.

  Each piece has a few forms made the chapter's way, by cutting circles, mirroring, or rotating. Every mark is a disk, a ring, a crescent, or a lens, and at most one piece is red. The seed deals one form of each piece and the proportions, so every seed is a different monster. A pulse runs down the circles of his face and body, he blinks, and his hands wave together. Proof a day's pile with `--export-grid`.

  ```sh
  swift run Example-Recreations-OsamuSato-TotemBuilder
  swift run Example-Recreations-OsamuSato-TotemBuilder --export-grid pile.png --seeds 16
  ```

### Further reading

- [Osamu Sato on Wikipedia](https://en.wikipedia.org/wiki/Osamu_Sato)
- [*The Art of Computer Designing* scanned on the Internet Archive](https://archive.org/details/satoArtOfComputerDesigning)
- [The Colpa Press reissue](https://www.colpapress.com/products/the-art-of-computer-designing-osamu-sato)
- [osamusato.net](https://www.osamusato.net/), his own site, with his graphics, his photographs, and a short biography
- [An interview at Red Bull Music Academy](https://daily.redbullmusicacademy.com/2017/11/osamu-sato-interview) (2017), the longest in English, on Kyoto, the darkroom, the first Macintosh, the design office, and the games
- ["Digital Art"](https://www.wired.com/1994/07/digital-art/), a short piece on the book in Wired (July 1994)
- [An interview at OTOTOY](https://ototoy.jp/feature/2018072601) (2018), in Japanese, on his student years, the silkscreens, the first cassette, the demo on a floppy disk, and the dream diary
- [His company's profile](https://web.archive.org/web/20061114155937/http://www.osd.co.jp/sato/index.html) and [its list of his work](https://web.archive.org/web/20061126040451/http://www.osd.co.jp/sato/sato_history.html), in Japanese, as the Internet Archive kept them in 2006: the exhibitions, the prizes, and the games by year
- [Osamu Sato at SOMSOC Gallery](https://somsoc.jp/en/pages/artists/osamu-sato), Tokyo, with his recent exhibitions and records

### About these homages

These are homages after Osamu Sato, made for learning. They aren't reproductions of specific works, and they aren't affiliated with or endorsed by the artist.

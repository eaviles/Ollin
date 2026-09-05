#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Osamu Sato</sup>

---

## Osamu Sato

**Osamu Sato** (佐藤理, b. 1960) is a Japanese multimedia artist, designer, and musician. He is known for surreal, dreamlike digital work built from a vocabulary of simple shapes and ancient-feeling symbols. That work includes the PlayStation cult titles *LSD: Dream Emulator* (1998) and *Eastern Mind: The Lost Souls of Tong Nou* (1994), and his electronic music.

His book **_The Art of Computer Designing: A Black and White Approach_** (1993, Graphic-Sha; reissued by Colpa Press) is a guide and compendium. It builds designs entirely out of basic vector shapes, with a chapter for each family: straight lines, curves, squares, and circles. Everything is in bold black and white with a single red accent. The original edition shipped with a **3.5″ floppy disk** of the work. The recreations here draw on two of its chapters: the totemic figures of "Circles", and the modular shape-alphabets of "Squares".

Learn more:

- [Osamu Sato on Wikipedia](https://en.wikipedia.org/wiki/Osamu_Sato)
- [*The Art of Computer Designing* scanned on the Internet Archive](https://archive.org/details/satoArtOfComputerDesigning)
- [The Colpa Press reissue](https://www.colpapress.com/products/the-art-of-computer-designing-osamu-sato)

### Recreations here

- [**Totem**](Totem/): a symmetric "computer totem" after the figures of the book's "Circles" chapter. It is assembled from Ollin's analytic SDF primitives. Around the core circle/ring/moon set it adds a horseshoe crown and ears, a parabola finial, a tunnel torso, a blobby-cross heart, cool-S ornaments, tapered-capsule legs, and a stairs pedestal.

  ```sh
  swift run Example-Recreations-OsamuSato-Totem
  ```

- [**Alphabet**](Alphabet/): a type-specimen sheet of A–Z and 0–9 in a square-module font, after the shape-built alphabets of the book's "Squares" chapter. Each glyph is a 5×7 grid of `drawRect` squares. The squares shimmer on a travelling wave, and a red accent sweeps through the glyphs.

  ```sh
  swift run Example-Recreations-OsamuSato-Alphabet
  ```

These are homages after Osamu Sato, made for learning. They aren't reproductions of specific works, and they aren't affiliated with or endorsed by the artist.

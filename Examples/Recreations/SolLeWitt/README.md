#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Sol LeWitt</sup>

---

## Sol LeWitt

| [![ArcsCirclesGrids](https://media.ollin.art/examples/Recreations/SolLeWitt/ArcsCirclesGrids/still-640.jpg?v=2133da44)](ArcsCirclesGrids/) | [![FiftyPoints](https://media.ollin.art/examples/Recreations/SolLeWitt/FiftyPoints/still-640.jpg?v=878f8441)](FiftyPoints/) |  |  |
|---|---|---|---|
| [ArcsCirclesGrids](ArcsCirclesGrids/) | [FiftyPoints](FiftyPoints/) |  |  |

**Sol LeWitt** (1928, Hartford, Connecticut; 2007, New York) is the artist who separated the idea of a drawing from the hand that draws it. He took a fine arts degree at Syracuse University in 1949, worked as a graphic designer in I. M. Pei's office, and from 1960 sat at the night desk of the Museum of Modern Art, where Robert Ryman and Dan Flavin were also on the staff. In "Paragraphs on Conceptual Art" (*Artforum*, 1967) he wrote the sentence that names the whole practice: "The idea becomes a machine that makes the art." The first wall drawing followed in 1968, at the opening show of the Paula Cooper Gallery in New York. Between then and his death he wrote more than 1,270 of them.

A wall drawing is a set of instructions, sometimes with a diagram, and a certificate. LeWitt did not draw them. Drafters do, on whatever wall the owner has, and the drawing is painted over when the show ends. The same work drawn on a new wall is a different drawing, and LeWitt compared the instructions to a musical score, played fresh each time. Where an instruction leaves a choice, the drafter makes it. "The number of lines and their length are determined by the draftsman," reads the note on *Wall Drawing 273*.

The instructions are short. *Wall Drawing 118* (1971) is three sentences: fifty points at random, evenly distributed, all connected by straight lines. In 1972 he drew the combinations of a compass alphabet for a book published by the Kunsthalle Bern: arcs from the four corners and the four sides of a square, circles, and grids. It runs to 195 drawings in four chapters. Many of them went onto walls. *Wall Drawing 138* is circles and arcs from the midpoints of four sides. *Wall Drawing 146* at the Guggenheim is every two-part combination of arcs and lines, in blue crayon. A retrospective of 105 wall drawings opened at MASS MoCA in 2008 and stays up for twenty-five years.

He belongs in this set because an instruction anyone can carry out, and that comes out different every time, is what a sketch is. His wall drawings are programs written for people. The two here are the same kind of program written for a machine, and the machine is one more drafter.

Learn more:

- [Sol LeWitt on Wikipedia](https://en.wikipedia.org/wiki/Sol_LeWitt)
- [*Wall Drawing #118* at the Art Institute of Chicago](https://www.artic.edu/artworks/196148/wall-drawing-118-50-randomly-placed-points-connected-by-straight-lines), with the instruction in full
- [*Wall Drawing #146* at the Guggenheim](https://www.guggenheim.org/artwork/2472) and [*Wall Drawing 138* at MASS MoCA](https://massmoca.org/event/walldrawing138/), two of the drawings made from the compass alphabet
- [*Arcs, Circles & Grids* at the Stedelijk Museum](https://www.stedelijk.nl/en/collection/9579-sol-lewitt-arcs-circles-and-grids), the 1972 book
- [SFMOMA, "Recreate Sol LeWitt's *Wall Drawing 273*"](https://www.sfmoma.org/read/drawing-with-instructions/), an invitation to draw one yourself
- [*Sol LeWitt: A Wall Drawing Retrospective* at MASS MoCA](https://massmoca.org/sol-lewitt/)

### Recreations here

- [**FiftyPoints**](FiftyPoints/): *Wall Drawing 118*, carried out over and over. The sketch is the drafter. It places the fifty points, keeping the farthest of a handful of throws for each, so that "at random" and "evenly distributed" both hold. Then it connects them one line at a time at a drafter's pace, holds the finished wall, paints it over, and starts the next one. `points` is the number in the instruction, `pace` how many lines a second get drawn, and `hold` how long a finished wall stays up. `firstWall` picks which drawing comes first, and a press moves on to the next wall. An original Ollin interpretation written from the published instruction. There is no code to port, since the work is the instruction.

  ```sh
  swift run Example-Recreations-SolLeWitt-FiftyPoints
  ```

  All 1,225 lines back as strokes, from a frame after the drafter has finished:

  ```sh
  swift run Example-Recreations-SolLeWitt-FiftyPoints --export-svg wall.svg --frame 1200
  ```

- [**ArcsCirclesGrids**](ArcsCirclesGrids/): the forty-five two-part combinations of the compass alphabet, one square each, nine across and five down. Each element is evenly spaced lines from one fixed point, cut where they leave the square, and the moire where two families cross is the picture. The spacing is the one thing the instruction leaves to the drafter, so it is the one thing that moves. `lines` is how many cross a square, and `breath` lets that drift over `period` seconds, which is also the length of one exact loop. `lineWeight` is the pen. An original Ollin interpretation written from the vocabulary in the book's title.

  ```sh
  swift run Example-Recreations-SolLeWitt-ArcsCirclesGrids
  ```

  The compass drawing back, as strokes cut at their squares:

  ```sh
  swift run Example-Recreations-SolLeWitt-ArcsCirclesGrids --export-svg sheet.svg
  ```

This is a homage after Sol LeWitt, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or his estate.

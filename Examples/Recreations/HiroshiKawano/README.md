#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Hiroshi Kawano</sup>

---

## Hiroshi Kawano

| [![ArtificialMondrian](https://media.ollin.art/examples/Recreations/HiroshiKawano/ArtificialMondrian/still-640.jpg?v=1ab01368)](ArtificialMondrian/) | [![Design](https://media.ollin.art/examples/Recreations/HiroshiKawano/Design/still-640.jpg?v=4d005352)](Design/) |  |  |
|---|---|---|---|
| [ArtificialMondrian](ArtificialMondrian/) | [Design](Design/) |  |  |

**Hiroshi Kawano** (1925, Fushun; 2012, Kobe) was a philosopher of aesthetics who left his desk for the computer center to test a theory. He was born in China to Japanese parents and moved to Japan in 1935. From 1948 he studied philosophy and aesthetics at the University of Tokyo, where he worked as an assistant in the Department of Aesthetics from 1955 to 1961. He began with neo-Kantianism, then turned to semiotics and finally to information theory. In the writings of the Stuttgart philosopher Max Bense he found a way to join semiotics, information theory, and aesthetics, and in Claude Shannon's papers the Markov chain that could carry the idea into pictures. He published his first essay on information aesthetics in 1962. The university had opened a computer center that anyone on its staff could use, and in the autumn of 1963 Kawano taught himself to program there, in assembly language on an OKITAC 5090A.

His method was to count and then run forward. He analyzed a few pictures of a kind he admired to find out how often, and after what, each color appeared. He gave those counts to the computer as the transition probabilities of a Markov chain. Then he let it decide a grid of cells one after another, each from the cells before it. The line printer typed the decisions as characters, and he painted them by hand in gouache, sometimes with his students' help. The first of these designs appeared in the Japanese *IBM Review* in September 1964, and on the cover of the science magazine *Kagaku Yomiuri* that November. That made him one of the first anywhere to publish pictures made with a computer. He said later that the interest was not artistic but scientific: "I set out to understand the logic of the creative process in human art."

The designs grew with the machines. *Simulated Color Mosaic* (1969) ran its chain across the rows and down the columns together. For the *Artificial Mondrian* series of 1969, computed on the university's HITAC 5020 in FORTRAN IV, he named the painter he admired while claiming no close likeness to his work. There the chain decided how long horizontal and vertical lines ran and whether they crossed. The lines closed into forms, and the colors were dealt at random. His first solo exhibition was at the Plaza DIC in Tokyo in October 1970. The credits in *Graphic Design* gave him "planning, programming and text" and the HITAC 5020 "design and works." In the 1970s he left the Markov model for artificial intelligence. He studied LOGO with Seymour Papert at MIT in 1978. He wrote on computer art and the mind for the rest of his life, some three hundred articles and fourteen books. He took his doctorate at Osaka University in 1986. In 2010 he gave his archive and the works still in his hands to the ZKM | Center for Art and Media Karlsruhe. The museum held his first retrospective, *Hiroshi Kawano. The Philosopher at the Computer*, in 2011. He died in Kobe on December 18, 2012.

He belongs in this set because his rule is a table you can hold. A Markov chain is a list of counts: after these colors, how often each color came next. Counted off a picture, it carries that picture's habits into new ones. Ollin's `MarkovChain` does the same thing in a few lines, and these sketches declare their counts as plain numbers in the source. For *Design* the counts were taken off his sheets cell by cell. For *Artificial Mondrian*, where he wrote his own matrix, the sketch writes one of its own.

Learn more:

- [*Design 3-1. Data 4, 5, 6, 6, 6*](https://zkm.de/en/artworks/design-3-1-data-4-5-6-6-6-design-1-4-data-1-2-3-3-3) and [*Design 3-2. Data 4, 4, 5, 5, 5*](https://zkm.de/en/artworks/design-3-2-data-4-4-5-5-5-design-1-2-data-1-1-2-2-2), the two 1964 sheets the first sketch was read from, at the ZKM
- [*KD 55*](https://zkm.de/en/artworks/kd-55), [*KD 27*](https://zkm.de/en/artworks/kd-27), and [*KD 52*](https://zkm.de/en/artworks/kd-52) from the *Artificial Mondrian* series, and the museum's account of the method on [*KD 28*](https://zkm.de/en/artworks/kd-28)
- [Hiroshi Kawano](https://zkm.de/en/persons/hiroshi-kawano) at the ZKM, with his posts and early publications, and the museum's [notice of his death](https://zkm.de/en/news/in-memory-of-hiroshi-kawano-1925-2012)
- Simone Gristwood, ["Hiroshi Kawano (1925–2012): Japan's Pioneer of Computer Arts"](https://doi.org/10.1162/LEON_a_01605), *Leonardo* 52, no. 1 (2019), drawn from her interviews with him and his archive
- Yoshiyuki Abe, ["The Genealogy of the Pioneers"](https://www.computer-arts-society.com/casarchive/cas/uploads/page-66.pdf), *PAGE* 66, the bulletin of the Computer Arts Society (2007/2008)

### Recreations here

- [**Design**](Design/): the Markov-chain designs of 1964, after *Design 3-1. Data 4, 5, 6, 6, 6* and *Design 3-2. Data 4, 4, 5, 5, 5*. A grid of 40 cells by 39 in black, red, blue, yellow, and white is decided in reading order. Each row carries on from the end of the one above. A chain of order 2 chooses each paint from what followed the last two in the counts. The counts were measured off photographs of the two sheets, and they hold the habit that makes the pictures. A run of color seldom turns into another color directly. It ends in black, and the black hands over to white or to the next color. Each title lists five data numbers. The sketch reads them as five bands of rows, each walked with the counts of its number, which is how a sheet changes partway down. That reading is the sketch's own, not a documented fact. `look` picks the title, `columns` and `rows` set the grid, and the seed deals the sheet. Under one seed the two looks share their first band, since both titles begin with data 4. Over one cycle the printer types a code for each cell, row by row. Then the gouache goes on cell by cell in the order the chain decided, holds, and fades back to paper. A press deals the next sheet. An original Ollin interpretation written from the sheets. There is no code to port.

  ```sh
  swift run Example-Recreations-HiroshiKawano-Design
  ```

  The grid back as one square per cell. Read in rows, its transitions match the declared counts:

  ```sh
  swift run Example-Recreations-HiroshiKawano-Design --seed 7 --param look=design31 --export-svg design.svg --frame 768
  ```

- [**ArtificialMondrian**](ArtificialMondrian/): the series of 1969, after *KD 55*, *KD 27*, and *KD 52*. The sheet is a raster of `units` cells, and every band is one cell wide. A chain over the gaps between lines sets where the lines can run, each gap (narrow, medium, or wide) deciding the next. A few forms grow over that lattice, their outline always drawn. Inside a form a second chain walks every line from crossing to crossing. It decides whether the next stretch is drawn or left open, so a line runs on through some crossings and stops at others. A stretch that leads nowhere is taken back. A line that stops at a crossing sometimes runs one cell past it, the notch of the paintings. Every region the black closes gets a color dealt from the look. `look` picks the painting the colors and the number of forms come from. `kd55` has three forms in blues, greens, yellow, crimson, and orange. `kd27` has one form in lemon, petrol, maroon, red, orange, and violet, with white holes. `kd52` has one form in teal, purple, olive, red, and yellow. `share` is how much of the lattice the forms take, and `notches` how often a stopped line runs on. Over one cycle the black is laid line by line, the regions are painted one after another, the sheet holds, and it fades back to paper. A press deals the next sheet. An original Ollin interpretation written from the paintings and the museum's account of the method. The two transition tables are the sketch's own.

  ```sh
  swift run Example-Recreations-HiroshiKawano-ArtificialMondrian
  ```

  The sheet back as rectangles on the raster, every band, notch, and region tile:

  ```sh
  swift run Example-Recreations-HiroshiKawano-ArtificialMondrian --seed 4 --param look=kd27 --export-svg artificial-mondrian.svg --frame 650
  ```

This is a homage after Hiroshi Kawano, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or his estate.

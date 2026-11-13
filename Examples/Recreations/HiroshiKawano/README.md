#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Hiroshi Kawano</sup>

---

## Hiroshi Kawano

| [![ArtificialMondrian](https://media.ollin.art/examples/Recreations/HiroshiKawano/ArtificialMondrian/still-640.jpg?v=1ab01368)](ArtificialMondrian/) | [![Design](https://media.ollin.art/examples/Recreations/HiroshiKawano/Design/still-640.jpg?v=4d005352)](Design/) | [![Flow](https://media.ollin.art/examples/Recreations/HiroshiKawano/Flow/still-640.jpg?v=a0e7e43c)](Flow/) | [![SimulatedColorMosaic](https://media.ollin.art/examples/Recreations/HiroshiKawano/SimulatedColorMosaic/still-640.jpg?v=393b4323)](SimulatedColorMosaic/) |
|---|---|---|---|
| [ArtificialMondrian](ArtificialMondrian/) | [Design](Design/) | [Flow](Flow/) | [SimulatedColorMosaic](SimulatedColorMosaic/) |

**Hiroshi Kawano** (1925, Fushun; 2012, Kobe) was a philosopher of aesthetics who left his desk for the computer center to test a theory. He was born in China to Japanese parents and moved to Japan in 1935. From 1948 he studied philosophy and aesthetics at the University of Tokyo, where he worked as an assistant in the Department of Aesthetics from 1955 to 1961. He began with neo-Kantianism, then turned to semiotics and finally to information theory. In the writings of the Stuttgart philosopher Max Bense he found a way to join semiotics, information theory, and aesthetics, and in Claude Shannon's papers the Markov chain that could carry the idea into pictures. He published his first essay on information aesthetics in 1962. The university had opened a computer center that anyone on its staff could use, and in the autumn of 1963 Kawano taught himself to program there, in assembly language on an OKITAC 5090A.

His method was to count and then run forward. He analyzed a few pictures of a kind he admired to find out how often, and after what, each color appeared. He gave those counts to the computer as the transition probabilities of a Markov chain. Then he let it decide a grid of cells one after another, each from the cells before it. The line printer typed the decisions as characters, and he painted them by hand in gouache, sometimes with his students' help. The first of these designs appeared in the Japanese *IBM Review* in September 1964, and on the cover of the science magazine *Kagaku Yomiuri* that November. That made him one of the first anywhere to publish pictures made with a computer. He said later that the interest was not artistic but scientific: "I set out to understand the logic of the creative process in human art."

He described the program as a body with three parts. The eye read a few pictures drawn by a person, a line at a time, the way a television scans. The brain counted how their cells sat next to each other, then ran the counts forward with random numbers. The hand was the line printer, and after it people painted or drew the result. The black and white pictures he called *Patterns of Flow*, or *Series of Pattern: Flow*, came out of it in several versions through the decade. One, made in 1966 in FORTRAN IV on a HITAC 5020, is in the Tama Art University Museum. Another was printed in the magazine *Computopia* in November 1969, beside the three pictures it had learned from. His note there gives the whole procedure in a paragraph. In July 1970 the United States Department of the Army wrote to ask for a copy of *Pattern of Flow*, for a display in the Pentagon. He sent one, and explained that his computer art was scientific research about art made by computers.

The designs grew with the machines. *Simulated Color Mosaic*, published in 1969, was a long painted strip. Counted off the photographs, it is about a hundred cells across. Its chain ran across the lines and down them together. Its counts came from three small pictures of colored fields held in black lines. The ZKM dates the work 1970, and rebuilt it as a print a meter wide for its retrospective, hung down a wall and run out across the floor. A page of it was printed again on an IBM System/360 on September 26, 1974, and colored by hand. For the *Artificial Mondrian* series of 1969, computed on the university's HITAC 5020 in FORTRAN IV, he named the painter he admired while claiming no close likeness to his work. There the chain decided how long horizontal and vertical lines ran and whether they crossed. The lines closed into forms, and the colors were dealt at random. His first solo exhibition was at the Plaza DIC in Tokyo in October 1970. The credits in *Graphic Design* gave him "planning, programming and text" and the HITAC 5020 "design and works." In the 1970s he left the Markov model for artificial intelligence. He studied LOGO with Seymour Papert at MIT in 1978. He wrote on computer art and the mind for the rest of his life, some three hundred articles and fourteen books. He took his doctorate at Osaka University in 1986. In 2010 he gave his archive and the works still in his hands to the ZKM | Center for Art and Media Karlsruhe. The museum held his first retrospective, *Hiroshi Kawano. The Philosopher at the Computer*, in 2011. He died in Kobe on December 18, 2012.

He belongs in this set because his rule is a table you can hold. A Markov chain is a list of counts: after these colors, how often each color came next. Counted off a picture, it carries that picture's habits into new ones. Ollin's `MarkovChain` does the same thing in a few lines, and these sketches declare their counts as plain numbers in the source. For *Design* the counts were taken off his sheets cell by cell. For *Artificial Mondrian*, where he wrote his own matrix, the sketch writes one of its own. The mosaic and *Flow* count data pictures of their own, as he counted his, and keep them in the source as rows of letters. Their chain reads a cell's neighbors in two directions, so those two sketches write it out themselves.

Learn more:

- [*Design 3-1. Data 4, 5, 6, 6, 6*](https://zkm.de/en/artworks/design-3-1-data-4-5-6-6-6-design-1-4-data-1-2-3-3-3) and [*Design 3-2. Data 4, 4, 5, 5, 5*](https://zkm.de/en/artworks/design-3-2-data-4-4-5-5-5-design-1-2-data-1-1-2-2-2), the two 1964 sheets the first sketch was read from, at the ZKM
- [*KD 55*](https://zkm.de/en/artworks/kd-55), [*KD 27*](https://zkm.de/en/artworks/kd-27), and [*KD 52*](https://zkm.de/en/artworks/kd-52) from the *Artificial Mondrian* series, and the museum's account of the method on [*KD 28*](https://zkm.de/en/artworks/kd-28)
- [*Simulated Color Mosaic*](https://zkm.de/en/artworks/simulated-color-mosaic) at the ZKM, in the reconstruction of 2011, and the [screen print](https://spencerart.ku.edu/art/collections-online/object/25303) of it in the *SDL Portfolio* of 1973 at the Spencer Museum of Art
- Hasaqui Yamanobe, ["Patterns of Flow | Revisiting Hiroshi Kawano"](https://www.rightclicksave.com/article/patterns-of-flow-revisiting-hiroshi-kawano-japanese-digital-generative-art), *Right Click Save* (2024), on the Tokyo exhibition that showed the *Flow* of 1966
- Hasaqui Yamanobe, [the second essay of a series on Japan's early computer art](https://themassage.jp/en/archives/21790), *Massage Magazine* (2024), in Japanese. It reproduces the *Computopia* page of 1969, the three data pictures of the mosaic, and the account of the eye, the brain, and the hand
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

- [**SimulatedColorMosaic**](SimulatedColorMosaic/): the frieze published in 1969, after a published photograph of part of it and the museum's reconstruction. The sketch holds three data pictures of its own, forty cells a side, written in the source as rows of letters. A chain counts what paint each of their cells holds after the four cells already decided around it. Those are the cell before it in its line and the three nearest it in the line before. A new cell is drawn from the counts of its own four. When the data never showed that arrangement, the chain forgets the farthest cell and asks again. The accounts of his chain are short. One calls it a quadruple chain for the vertical and horizontal directions, and his note on *Flow* speaks of how nine picture elements join. This sketch reads the nine as a block of three by three, and the four as the cells in it that are already settled. That reading is the sketch's own. A chain that read only its own line and column could not keep the far side of a rectangle straight, and the strip is full of rectangles. The strip lies on its side as it hung, a hundred cells from top to bottom, and it has no end. The printer types a code for each cell at the right edge, the gouache follows a few lines behind, and the strip travels left. `data` picks which pictures the chain has read, `all` or one alone. `cells` is the length of a line, and `pace` is lines a second. The seed deals the strip, and a press deals the next. The data pictures were adjusted until the five paints came out in about the shares measured off that photograph. An original Ollin interpretation, written from the accounts and the photographs. There is no code to port, and the data pictures are not his.

  ```sh
  swift run Example-Recreations-HiroshiKawano-SimulatedColorMosaic
  ```

  The strip back as one square per painted cell. Read in lines, its transitions match the counts of the data pictures:

  ```sh
  swift run Example-Recreations-HiroshiKawano-SimulatedColorMosaic --seed 3 --export-svg mosaic.svg --frame 600
  ```

- [**Flow**](Flow/): the black and white strip, after the version of 1966 and the one printed in *Computopia* in 1969. His note gives the procedure. There are two kinds of picture element, white and black, and eight thousand of them in a format of 40 by 200. They are drawn by chance from a table of how nine picture elements join. The table is counted off three data works drawn by a person. The line printer types the result, and a human hand draws it at the end. The sketch lays that out from top to bottom on one sheet. Its three data pictures are its own: black leaves on white, the same leaves in white on black, and a wave that changes sides halfway across. A line passes over them as the eye scans. Beside them, the sixteen arrangements of four settled cells fill with their counts, each with a bar for its share of black. Below, the strip is typed line by line, 200 lines of 40. Below that, the hand draws it again without its corners and leaves out a cell that stands alone. The chain is the one the mosaic uses, and the reading of the nine elements is the sketch's own there too. `data` picks which pictures are read, `roundness` is how far the hand rounds the cells, and the seed deals the strip. One cycle of `seconds` scans, types, draws, holds, and fades, which is also the export loop. A press deals the next strip. An original Ollin interpretation, written from his note and from photographs of the two versions. There is no code to port, and the data pictures are not his.

  ```sh
  swift run Example-Recreations-HiroshiKawano-Flow
  ```

  The strip back as one square per black cell, with the data pictures and the bars, from a frame in the hold:

  ```sh
  swift run Example-Recreations-HiroshiKawano-Flow --seed 2 --export-svg flow.svg --frame 972
  ```

This is a homage after Hiroshi Kawano, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or his estate.

#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Owen Schuh</sup>

---

## Owen Schuh

| [![CountingTheRationals](https://media.ollin.art/examples/Recreations/OwenSchuh/CountingTheRationals/still-640.jpg?v=fe9774fd)](CountingTheRationals/) | [![DiagonalArgument](https://media.ollin.art/examples/Recreations/OwenSchuh/DiagonalArgument/still-640.jpg?v=e4720d01)](DiagonalArgument/) |  |  |
|---|---|---|---|
| [CountingTheRationals](CountingTheRationals/) | [DiagonalArgument](DiagonalArgument/) |  |  |

**Owen Schuh** (born 1982 in Stevens Point, Wisconsin) paints and draws mathematics by hand. He studied fine art and philosophy at Haverford College and took an MFA at the Tyler School of Art in Philadelphia, with his last year in Rome. He worked in San Francisco and then Philadelphia, and now lives in Westminster, in southeastern Vermont, where he and Candace Jensen run In Situ Polyculture Commons, an arts residency they founded in 2021. His work is in the Kupferstichkabinett of the Staatliche Museen zu Berlin and the Flaten Art Museum, and he is represented by Silas von Morisse Gallery in New York.

The rule comes first. He picks a function, a data set, or a procedure, and then carries it out: the output of one step is the input of the next, and the drawing stops when the rule runs out or he does. *Bounded Iteration in the Complex Plane* (2006) is a Julia set worked out by hand, point by point; *Julia Set* (2009) is the second try, with the points that run away marked in white; *Diatom* (2011) grows circles by an iterative rule and lays a Voronoi diagram over them. Cellular automata, circle packing, watersheds, fractals, and the combinatorics of discrete structures all turn up. The tools are pencils, paint, a compass, and at most a pocket calculator. Nothing is plotted or printed.

From 2013 to 2015 he worked with the mathematician Satyan Devadoss on the space of evolutionary trees, a collaboration that produced a triptych, a show at Satellite Berlin, a set of open mathematics questions, and an article the two of them wrote for *Leonardo*. That article carries the clearest statement of why the work is made by hand rather than by machine: a drawing "must be drawn one line at a time, similar to the distinction between mathematical insight and the rigor of a proof," and putting a mathematical object into a frame that takes a long time to render "forces one to slow down and perhaps approach it differently." And on what a drawing adds to a definition: "The mathematical definition of a line has neither thickness nor color, but in drawing there is no line without these characteristics."

The notebooks run alongside the paintings and are where the rules are found. "Working in notebooks (usually several at a time) is a crucial part of my process," he writes. "This is where I explore new forms and ideas, do calculation and simply take notes." He likes that a notebook is the one form every discipline keeps, and that it lets you work an idea out and think with your hands.

The spread these two sketches come from is one of those pages, from 2022. Across the two leaves he painted the two facts that sit at the start of the theory of infinite sets, one on each side. The left leaf, headed *Natural = Rational*, is the table of fractions woven as a piece of cloth, every row a numerator, every column a denominator, and the zigzag that counts every one of them off. The right leaf, headed *Natural ≠ Real*, is a list of numbers written as colored digits with the diagonal picked out, and under it the number the diagonal builds, which is not on the list. The rule for building it is lettered under the drawing in his own blackletter hand, in the two colors it names.

He belongs in this set because the arithmetic is the drawing. The count and the picture are the same object, made one mark at a time, which is what a sketch does too.

Learn more:

- [owenschuh.com](https://www.owenschuh.com), and its [notebooks](https://www.owenschuh.com/notebooks)
- [Silas von Morisse Gallery](https://www.silasvonmorisse.com), which represents him
- [*Owen Schuh: Drawings, Rules*](https://www.meer.com/en/22530-owen-schuh-drawings-rules), a review of the hand-computed Julia sets and the *Diatom* pieces
- ["Cartography of Tree Space"](https://leonardo.info/journal-issue/leonardo/52/3), the article he wrote with Satyan Devadoss for *Leonardo* 52.3 (2019), on drawing a mathematical space by hand
- [*Uncertainty*](https://leonardo.info/blog/2017/01/17/uncertainty-exhibition-review), an exhibition review that puts the tree space paintings beside other work about what cannot be pinned down
- [Owen Schuh discusses visual research of mathematics](https://www.commonsnews.org/issue/835/835Art_talk), a note on the Vermont years and the residency

### Recreations here

- [**CountingTheRationals**](CountingTheRationals/): the left leaf. Fractions are laid out in a table, rows the numerator and columns the denominator, and the walk takes the diagonals in turn, up one and down the next, so it reaches every cell and the fractions can be counted off one after another. The table is woven: every number is painted the color of its last digit, so the tenth row starts the scale again, and the crossing shows whichever ribbon the walk let pass over, which works out to the plain over-one-under-one weave of cloth. A fraction that is not in lowest terms was counted already, so the crossing is left as a hole in the fabric and what stays painted is one cell for each counting number. `table` is how much of the endless table the page shows, `pace` how fast the loom runs, `hold` how long the finished page stays up, and `firstPage` numbers the first one. An original Ollin interpretation written from the drawing and the mathematics. There is no code to port: the work is paint on paper.

  ```sh
  swift run Example-Recreations-OwenSchuh-CountingTheRationals
  ```

  The table back as marks, from a frame after the weave is finished:

  ```sh
  swift run Example-Recreations-OwenSchuh-CountingTheRationals --export-svg weave.svg --frame 900
  ```

- [**DiagonalArgument**](DiagonalArgument/): the right leaf. Somebody hands you a list of the numbers between nought and one, and every one of them is written across the page as colored digits. The diagonal is read off one place at a time, each cell boxed in red as it is taken and carried into the strip at the left, and the band under the list is the new number, whose nth place is deliberately not what the nth number has there. That number is on no line of the list, so the list was never complete. `list` and `places` are how much of it the page shows, `pace` writes the list, `dwell` is how long the hand rests on each place of the diagonal, and `firstPage` is the seed the digits come from. The rule is Schuh's two-color one with the two digits moved to the middle of the scale, so the number it writes can never end in an endless tail of nines and be read as a different number. An original Ollin interpretation.

  ```sh
  swift run Example-Recreations-OwenSchuh-DiagonalArgument
  ```

  The list, the diagonal, and the new number back as marks:

  ```sh
  swift run Example-Recreations-OwenSchuh-DiagonalArgument --export-svg page.svg --frame 800
  ```

This is a homage after Owen Schuh, made for learning. It isn't a reproduction of a specific work, it isn't affiliated with or endorsed by the artist, and none of his work was used to make it.

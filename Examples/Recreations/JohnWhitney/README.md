#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → John Whitney</sup>

---

## John Whitney

| [![Arabesque](https://media.ollin.art/examples/Recreations/JohnWhitney/Arabesque/still-640.jpg?v=55b81612)](Arabesque/) | [![Matrix](https://media.ollin.art/examples/Recreations/JohnWhitney/Matrix/still-640.jpg?v=cf5c6824)](Matrix/) | [![Permutations](https://media.ollin.art/examples/Recreations/JohnWhitney/Permutations/still-640.jpg?v=a2722897)](Permutations/) |  |
|---|---|---|---|
| [Arabesque](Arabesque/) | [Matrix](Matrix/) | [Permutations](Permutations/) |  |

**John Whitney** (1917, Pasadena, California; 1995, Los Angeles) spent fifty years making motion out of arithmetic. With his brother James he made *Five Film Exercises* (1940-45), which won a prize for sound in Belgium in 1949. In the late 1950s he converted the mechanism of a World War II M-5 antiaircraft gun director into a mechanical analog computer, later adding an M-7 to it, until the rig stood twelve feet high. He founded Motion Graphics Incorporated in 1960 and ran film and television titles and commercials through that machine. He worked on the title sequence of *Vertigo* (1958) with Saul Bass. In 1966 IBM made him its first artist in residence, and the films he made from then on, *Permutations* (1968) among them, are the ones that demonstrate what he called harmonic progression. *Matrix* (1971) was made at the California Institute of Technology, with a program created by Frederick B. Thompson, and its music is sonatas by Antonio Soler. *Arabesque* (1975) was made with Larry Cuba as its programmer, and its music is santur improvised by Manoochehr Sadeghi. He set the theory down in *Digital Harmony: On the Complementarity of Music and Visual Art* (Byte Books/McGraw-Hill, 1980), which prints his own sample programs, in Pascal, in the back.

His claim was that motion has harmony in it the way sound does, and that the harmony comes from whole numbers. The rule is one paragraph of that book:

> "if one element were set to move at a given rate, the next element might be moved two times that rate. Then the third would move at three times that rate and so on. Each element would move at a different rate and in a different direction within the field of action. So long as all elements obey a rule of direction and rate, and none drifts about aimlessly or randomly, then pattern configurations form and reform. This is harmonic resonance and it echoes musical harmony, stated in explicit terms."

The example worked in the book puts those elements on a series of increasingly wider concentric circles. Everything else follows: because every rate is a whole multiple of the first, the points leave together and come back together, and on the way they pass through the fractions of the cycle. At half a cycle they lie on two arms, at a third on three, at an eighth on eight. Whitney called those gatherings resonance and thought them the visual equal of a chord.

The book also says how two of the films were made. Of *Matrix* he writes: "All motion is along a closed invisible pathway (the matrix) which is a classical Lissajous figure positioned symmetrically within the motion picture field." The film, he says, "is simply a sequence of events of clustering and dispersal of the lines, squares and cubes". *Arabesque* gets a chapter of its own. Its whole structure is "an array of 360 points distributed around a circle". The points are numbered, and all move to the right, each at the rate its number gives. A point that reaches the right edge of the field comes back in at the left. The action runs to a whole-number fraction of its cycle and stops there. Then the picture turns over, by a switch of the sign of X, of Y, or of both, and the run goes on. He compares the result to "a very slow and stately dance".

He belongs in this set because he is the reason motion is the default here. His work cannot be shown as a print. It is a rule about rates, and the picture is what the rule does over time.

Learn more:

- [John Whitney on Wikipedia](https://en.wikipedia.org/wiki/John_Whitney_(animator))
- [*Permutations* (1968) at the Internet Archive](https://archive.org/details/john-whitney-permutations-1968), and [*Experiments in Motion Graphics*](https://archive.org/details/experimentsinmotiongraphics), where he explains the machine and the method himself
- [*Digital Harmony* at the Internet Archive](https://archive.org/details/DigitalHarmony_201611). Chapter IX is his analysis of *Arabesque*, section by section, and the appendix has his word about *Matrix*
- [*Arabesque* in the ACM SIGGRAPH history archive](https://history.siggraph.org/artwork/john-whitney-arabesque)
- [Jim Bumgardner, "The Whitney Music Box"](https://jbum.com/papers/whitney_paper.pdf) (Bridges 2007), which quotes the rule above and plays a note for each point

### Recreations here

- [**Permutations**](Permutations/): a hundred and fifty points on concentric circles, the first making one turn in a cycle, the second two, the hundred and fiftieth a hundred and fifty. Nothing is random, and nothing is tuned by hand: the whole picture is that one rule, so the fan of points falls into a star at every simple fraction of the cycle and comes back to a single spoke at the end of it. `points` sets how many turn, `cycle` how long the slowest takes, `step` the whole number between one rate and the next, and `dotSize` the marks. An original Ollin interpretation, written from his own statement of the rule; no code was ported, and his own programs are printed in Pascal in the back of a book rather than published as software.

  ```sh
  swift run Example-Recreations-JohnWhitney-Permutations
  ```

  One whole cycle, which loops exactly:

  ```sh
  swift run Example-Recreations-JohnWhitney-Permutations --export-video permutations.mp4 --seconds 30
  ```

- [**Arabesque**](Arabesque/): a ring of 360 numbered points, all moving to the right, point 1 at one rate and point 360 at three hundred and sixty times it. A point that leaves on the right comes back on the left, so the ring is combed out across the field until it reads as scatter. At every fifth of the cycle the points stand on five rings again. There the action stops and the picture turns over, in X, in Y, or in both, which is his switch of polarity, and then the run goes on. Three copies play a second and a third apart, as a canon, each in its own color. `points` sets how many make the ring, `cycle` how long a lap takes, and `parts` the whole number the cycle is cut into. `proportion` shapes the ring, from the circle that opens the film to the upright ellipse of its third section. `voices` and `canon` set the copies and the delay between them, and `dotSize` the marks. An original Ollin interpretation, written from his own analysis of the film in chapter IX of the book. Chapter XII also prints a short Pascal program for the ring's first action. It was read to check the reading, and none of it was copied. How long a run and a switch take, the ring's size, the copies, and the color are the sketch's own.

  ```sh
  swift run Example-Recreations-JohnWhitney-Arabesque
  ```

  One whole lap, which loops exactly:

  ```sh
  swift run Example-Recreations-JohnWhitney-Arabesque --export-loop arabesque.mp4
  ```

- [**Matrix**](Matrix/): twenty-four outlined squares on one closed path that is never drawn, square 1 traveling it at one rate and square 24 at twenty-four times that. The path is a Lissajous figure in three dimensions. Across and down it is a figure eight on its side, gone around twice, and the third dimension is depth, so a square is drawn larger the nearer it is. The squares leave the middle as one square, string out along the path, and keep meeting in small companies, a small square inside a large one where two passes cross. The cycle steps through twenty-four stops, and each stop finds every square on one of twenty-four places. `squares` sets how many travel (an even number), `cycle` how long a lap takes, `depth` how much larger the nearest square is than the farthest, and `lineWidth` the lines. An original Ollin interpretation, written from his own account of the film; no code was ported. The pathway's numbers, the turning of the squares, the stops, and the color are the sketch's own. The book's one figure of the film shows the squares meeting in a block of two by two. This path brings every meeting to the middle of the frame, so that figure does not appear here.

  ```sh
  swift run Example-Recreations-JohnWhitney-Matrix
  ```

  One whole lap, which loops exactly:

  ```sh
  swift run Example-Recreations-JohnWhitney-Matrix --export-loop matrix.mp4
  ```

This is a homage after John Whitney, made for learning. It isn't a reproduction of a specific film, and it isn't affiliated with or endorsed by the artist or his estate.

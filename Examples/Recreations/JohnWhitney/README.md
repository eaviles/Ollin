#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → John Whitney</sup>

---

## John Whitney

**John Whitney** (1917, Pasadena, California; 1995, Los Angeles) spent fifty years making motion out of arithmetic. With his brother James he made *Five Film Exercises* (1940-45), which won a prize for sound in Belgium in 1949. In the late 1950s he converted the mechanism of a World War II M-5 antiaircraft gun director into a mechanical analog computer, later adding an M-7 to it, until the rig stood twelve feet high. He founded Motion Graphics Incorporated in 1960 and ran film and television titles and commercials through that machine. He worked on the title sequence of *Vertigo* (1958) with Saul Bass. In 1966 IBM made him its first artist in residence, and the films he made from then on, *Permutations* (1968) among them, are the ones that demonstrate what he called harmonic progression. *Arabesque* (1975) was made with Larry Cuba as its programmer. He set the theory down in *Digital Harmony: On the Complementarity of Music and Visual Art* (Byte Books/McGraw-Hill, 1980), which prints his own sample programs in the back.

His claim was that motion has harmony in it the way sound does, and that the harmony comes from whole numbers. The rule is one paragraph of that book:

> "if one element were set to move at a given rate, the next element might be moved two times that rate. Then the third would move at three times that rate and so on. Each element would move at a different rate and in a different direction within the field of action. So long as all elements obey a rule of direction and rate, and none drifts about aimlessly or randomly, then pattern configurations form and reform. This is harmonic resonance and it echoes musical harmony, stated in explicit terms."

The example worked in the book puts those elements on a series of increasingly wider concentric circles. Everything else follows: because every rate is a whole multiple of the first, the points leave together and come back together, and on the way they pass through the fractions of the cycle. At half a cycle they lie on two arms, at a third on three, at an eighth on eight. Whitney called those gatherings resonance and thought them the visual equal of a chord.

He belongs in this set because he is the reason motion is the default here. His work cannot be shown as a print. It is a rule about rates, and the picture is what the rule does over time.

Learn more:

- [John Whitney on Wikipedia](https://en.wikipedia.org/wiki/John_Whitney_(animator))
- [*Permutations* (1968) at the Internet Archive](https://archive.org/details/john-whitney-permutations-1968), and [*Experiments in Motion Graphics*](https://archive.org/details/experimentsinmotiongraphics), where he explains the machine and the method himself
- [*Digital Harmony* at the Internet Archive](https://archive.org/details/DigitalHarmony_201611)
- [Jim Bumgardner, "The Whitney Music Box"](https://jbum.com/papers/whitney_paper.pdf) (Bridges 2007), which quotes the rule above and plays a note for each point

### Recreations here

- [**Permutations**](Permutations/): a hundred and fifty points on concentric circles, the first making one turn in a cycle, the second two, the hundred and fiftieth a hundred and fifty. Nothing is random, and nothing is tuned by hand: the whole picture is that one rule, so the fan of points falls into a star at every simple fraction of the cycle and comes back to a single spoke at the end of it. `points` sets how many turn, `cycle` how long the slowest takes, `step` the whole number between one rate and the next, and `dotSize` the marks. An original Ollin interpretation, written from his own statement of the rule; no code was ported, and his own programs are printed in BASIC in a book rather than published as software.

  ```sh
  swift run Example-Recreations-JohnWhitney-Permutations
  ```

  One whole cycle, which loops exactly:

  ```sh
  swift run Example-Recreations-JohnWhitney-Permutations --export-video permutations.mp4 --seconds 30
  ```

This is a homage after John Whitney, made for learning. It isn't a reproduction of a specific film, and it isn't affiliated with or endorsed by the artist or his estate.

| [![Permutations](https://media.ollin.art/examples/Recreations/JohnWhitney/Permutations/still-640.jpg)](Permutations/) |  |  |  |
|---|---|---|---|
| [Permutations](Permutations/) |  |  |  |

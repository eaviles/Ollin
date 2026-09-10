#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Manfred Mohr</sup>

---

## Manfred Mohr

**Manfred Mohr** (born 1938 in Pforzheim, Germany) started out as a jazz musician and an action painter. In 1961 he read Max Bense on a rational aesthetics, and it changed what he thought a picture was. A picture could be stated as information, so its statement could be examined. In 1967 he met the composer Pierre Barbaud in Paris, who told him to go and use a computer. He wrote his first drawing programs in Fortran in 1969.

The computer was not his. He asked the Paris institute of meteorology for time on theirs. In 1970 they gave him a CDC 6400 and a Benson 1284 flatbed plotter, and that arrangement lasted eleven years. In May 1971 the ARC at the Musée d'Art Moderne de la Ville de Paris gave him a solo show. It was called *Computer Graphics: Une esthétique programmée*. It is remembered since as the first solo museum exhibition of work calculated and drawn entirely by a computer. He put the plotter in the gallery and let it draw while people watched. Almost none of them had seen that before.

In 1973 he chose the cube, and he has worked with it ever since. He did not choose it to draw a cube, but to use one. He wanted a structure that held still, so that what a viewer saw would be the rule he had written and not his taste. He compared this to a musician choosing an instrument. First he took the twelve lines of an ordinary cube apart and used them as an alphabet. Then he applied the same idea in four dimensions, and later in six. Nobody can picture a solid in six dimensions, but it still casts a shadow that anybody can read. Every work carries a `P-` number, for the program that made it.

He moved to New York in 1981 and works there. He received the Golden Nica at Ars Electronica in 1990 and the ACM SIGGRAPH Distinguished Artist Award for lifetime achievement in digital art in 2013.

He belongs in this set because he leaves so little to his own taste. The two pieces here are two of his rules. Each rule is small enough to say in a sentence, and each one produces a whole sheet with nothing else added.

Learn more:

- [Manfred Mohr on Wikipedia](https://en.wikipedia.org/wiki/Manfred_Mohr)
- [emohr.com](https://www.emohr.com), his own site, where he states the algorithm behind each series in [a few lines each](https://www.emohr.com/themes/combinatoric.html)
- [*Une esthétique programmée*, Paris 1971](https://www.emohr.com/paris-1971/index.html), the show, with photographs of the plotter at work
- [Cubic Limit at Media Art Net](http://www.medienkunstnetz.de/works/cubic-limit/) and [at the Digital Art Museum](https://dam.org/museum/artists_ui/artists/mohr-manfred/cubic-limit-i/)

### Recreations here

- [**CubicLimit**](CubicLimit/): the twelve lines of a cube used as an alphabet. Every cell holds the same cube at the same rotation. Each row keeps one more of its lines than the row above. Across a row, the signs are the different ways to keep that many lines, counted off rather than chosen. So the sheet fills as your eye goes down. An original Ollin interpretation, written from the work and from Mohr's own statement of the rule.

  ```sh
  swift run Example-Recreations-ManfredMohr-CubicLimit
  ```

  The same alphabet exported as a drawing a pen could make, which is where the work came from:

  ```sh
  swift run Example-Recreations-ManfredMohr-CubicLimit --export-svg alphabet.svg
  ```

- [**DiagonalPath**](DiagonalPath/): every way to walk from one corner of a cube to the corner farthest from it, crossing each dimension exactly once. Three dimensions give six walks, four give twenty four, and five give a hundred and twenty. Each cell is one of those walks, with the whole solid in thin line and the walk in heavy line. An original Ollin interpretation, written from the work and from Mohr's own statement of the rule.

  ```sh
  swift run Example-Recreations-ManfredMohr-DiagonalPath
  ```

  The three dimension counts side by side:

  ```sh
  swift run Example-Recreations-ManfredMohr-DiagonalPath \
    --export-sweep dimensions.png --sweep-param dimensions --values "3,4,5"
  ```

These are homages after Manfred Mohr, made for learning. They are not reproductions of specific works, and they are not affiliated with or endorsed by the artist. No source of his was used, because his programs ran on a mainframe and are not published.

| [![CubicLimit](https://media.ollin.art/examples/Recreations/ManfredMohr/CubicLimit/still-640.jpg?v=7ad32943)](CubicLimit/) | [![DiagonalPath](https://media.ollin.art/examples/Recreations/ManfredMohr/DiagonalPath/still-640.jpg?v=40742459)](DiagonalPath/) |  |  |
|---|---|---|---|
| [CubicLimit](CubicLimit/) | [DiagonalPath](DiagonalPath/) |  |  |

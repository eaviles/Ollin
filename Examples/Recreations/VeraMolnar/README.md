#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Vera Molnár</sup>

---

## Vera Molnár

| [![DesOrdres](https://media.ollin.art/examples/Recreations/VeraMolnar/DesOrdres/still-640.jpg?v=18751e3f)](DesOrdres/) | [![Interruptions](https://media.ollin.art/examples/Recreations/VeraMolnar/Interruptions/still-640.jpg?v=ecf815ff)](Interruptions/) |  |  |
|---|---|---|---|
| [DesOrdres](DesOrdres/) | [Interruptions](Interruptions/) |  |  |

**Vera Molnár** (1924-2023) was a Hungarian-French artist and a pioneer of generative computer art. She was among the first women to use computers in a fine-art practice. From the late 1960s she wrote programs in Fortran and BASIC and drew the results with plotters. Her programs explored simple geometric forms (squares, lines, rule-based compositions) and, above all, the tension between **order and controlled disorder**. She introduced small, deliberate amounts of randomness into rigorous grids, which she called her "1% disorder", the phrase she is best known for.

Learn more:

- [Vera Molnár on Wikipedia](https://en.wikipedia.org/wiki/Vera_Moln%C3%A1r)
- Notable works and series: *Interruptions* (1968 to 1969), *(Dés)Ordres*, *Transformations*, and her studies of concentric squares.

### Recreations here

- [**Interruptions**](Interruptions/), a field of 56 by 56 short lines, each turned about its middle and leaning toward the vertical, with patches of them left out. The grid is the order, and the turns and gaps are the disorder. Its numbers were measured off one plate of the series, the plotter drawing the Victoria and Albert Museum holds as E.269-2011: how many lines, how long each is, how far they lean, how many are missing, and how large the patches are. How the patches are made is the sketch's own reading of that plate. It is after Molnár, in the spirit of her *Interruptions* (1968 to 1969). **Click to recreate** a new variation.

  ```sh
  swift run Example-Recreations-VeraMolnar-Interruptions
  ```

- [**(Dés)Ordres**](DesOrdres/), after Molnár's [*(Dés)Ordres*](https://dam.org/museum/artists_ui/artists/molnar-vera/des-ordres/) (1974). It draws a grid of concentric squares, and each square is drawn only ~95% of the time, so the orderly nesting breaks down into disorder. The title is a pun: *désordres* (disorders) versus *des ordres* (some orders), which points to the logic within the apparent disarray. `mouseX` seeds the randomness, so moving the mouse scrubs back and forth through the patterns.

  ```sh
  swift run Example-Recreations-VeraMolnar-DesOrdres
  ```

These sketches are homages after Vera Molnár, made for learning. They are not reproductions of specific works. They are not affiliated with or endorsed by the artist or her estate.


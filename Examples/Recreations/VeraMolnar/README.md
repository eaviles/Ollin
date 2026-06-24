#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Vera Molnár</sup>

---

## Vera Molnár

**Vera Molnár** (1924-2023) was a Hungarian-French artist and a pioneer of generative computer art, and among the first women to use computers in a fine-art practice. From the late 1960s she wrote programs (in Fortran and BASIC, drawing with plotters) to explore simple geometric forms (squares, lines, rule-based compositions) and, above all, the tension between **order and controlled disorder**: she introduced small, deliberate amounts of randomness (her famous "1% disorder") into rigorous grids.

Learn more:

- [Vera Molnár on Wikipedia](https://en.wikipedia.org/wiki/Vera_Moln%C3%A1r)
- Notable works and series: *Interruptions* (1969), *(Dés)Ordres*, *Transformations*, and her studies of concentric squares.

### Recreations here

- [**Interruptions**](Interruptions/), a field of short line segments at random rotations, some omitted by a noise threshold: the grid is the order, the rotations and gaps are the disorder. After Molnár, in the spirit of her *Interruptions* (1969). **Click to recreate** a new variation.

  ```sh
  swift run Example-Recreations-VeraMolnar-Interruptions
  ```

- [**(Dés)Ordres**](DesOrdres/), after Molnár's [*(Dés)Ordres*](https://dam.org/museum/artists_ui/artists/molnar-vera/des-ordres/) (1974): a grid of concentric squares, each drawn only ~95% of the time so the orderly nesting frays into disorder. The title is a pun: *désordres* (disorders) versus *des ordres* (some orders), finding logic within the apparent disarray. `mouseX` seeds the randomness, so moving the mouse scrubs the pattern.

  ```sh
  swift run Example-Recreations-VeraMolnar-DesOrdres
  ```

These are homages after Vera Molnár, made for learning. They aren't reproductions of specific works, and they aren't affiliated with or endorsed by the artist or her estate.

#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Vera Molnár</sup>

---

## Vera Molnár

| [![DesOrdres](https://media.ollin.art/examples/Recreations/VeraMolnar/DesOrdres/still-640.jpg?v=18751e3f)](DesOrdres/) | [![Interruptions](https://media.ollin.art/examples/Recreations/VeraMolnar/Interruptions/still-640.jpg?v=ecf815ff)](Interruptions/) |  |  |
|---|---|---|---|
| [DesOrdres](DesOrdres/) | [Interruptions](Interruptions/) |  |  |

| Born | Died | Wing |
|---|---|---|
| Budapest, 1924 | Paris, 2023 | [Chance](../README.md#chance) |

### Her life

**Vera Molnár** was a Hungarian-French artist and a pioneer of generative computer art. She was among the first women to use computers in a fine-art practice.

She was born in Budapest. As a girl she drew the same sunset over Lake Balaton every evening, with a box of pastels an uncle had given her. She gave herself a rule, always take the next pastel to the right, so each picture looked like the last and was still different. She later said that rule was already a program. From 1942 to 1947 she studied painting, art history, and aesthetics at the Budapest College of Fine Arts, where she met François Molnár. They moved to Paris in 1947 and married the next year, and she lived there until she died at ninety-nine.

In Paris she painted with a few plain shapes and changed one small thing at a time. From about 1959 she worked with what she called her *machine imaginaire*: she imagined she had a computer, wrote a program for it, and carried out the steps by hand. In 1968, by her own account, she knocked at the door of the university computing center at Orsay and explained that she wanted to try to make art with a computer. She took a course in Fortran and learned to punch cards. From the late 1960s she wrote programs in Fortran and BASIC and drew the results with plotters.

Recognition came late. Her first solo show was in London in 1976, and she began to sell her work only after her husband died in 1993. In 2022, at ninety-eight, she was the oldest living artist shown at the Venice Biennale. The Centre Pompidou's retrospective opened in February 2024, less than three months after her death.

### What she made

Her programs explored simple geometric forms (squares, lines, rule-based compositions) and, above all, the tension between **order and controlled disorder**. She introduced small, deliberate amounts of randomness into rigorous grids, which she called her "1% disorder", the phrase she is best known for. "I love order but I can't stand it," she told the curator Hans Ulrich Obrist. Her way to live with both was to build an ordered structure and put in "1% of chaos".

She never left the chance to itself. She set how far a pen could stray, and of everything a program could draw she accepted, in her words, "only a very small percentage". "The computer helps," she said, "but it does not 'do', does not 'design' or 'invent' anything."

### Rebuilding her work

Her method is a grid with a small amount of chance let into it. A sketch can state that exactly: one rule for where every mark goes, and a random number for how far each one strays from it. The seed fixes the random numbers, so any variation can be drawn again.

- [**Interruptions**](Interruptions/), a field of 56 by 56 short lines, each turned about its middle and leaning toward the vertical, with patches of them left out.

  The grid is the order, and the turns and gaps are the disorder. Its numbers were measured off one plate of the series, the plotter drawing the Victoria and Albert Museum holds as E.269-2011: how many lines, how long each is, how far they lean, how many are missing, and how large the patches are. How the patches are made is the sketch's own reading of that plate. It is after Molnár, in the spirit of her *Interruptions* (1968 to 1969). **Click to recreate** a new variation.

  ```sh
  swift run Example-Recreations-VeraMolnar-Interruptions
  ```

- [**(Dés)Ordres**](DesOrdres/), after Molnár's [*(Dés)Ordres*](https://dam.org/museum/artists_ui/artists/molnar-vera/des-ordres/) (1974).

  It draws a grid of concentric squares, and each square is drawn only ~95% of the time, so the orderly nesting breaks down into disorder. The title is a pun: *désordres* (disorders) versus *des ordres* (some orders), which points to the logic within the apparent disarray. `mouseX` seeds the randomness, so moving the mouse scrubs back and forth through the patterns.

  ```sh
  swift run Example-Recreations-VeraMolnar-DesOrdres
  ```

### Further reading

- [Vera Molnár on Wikipedia](https://en.wikipedia.org/wiki/Vera_Moln%C3%A1r)
- Notable works and series: *Interruptions* (1968 to 1969), *(Dés)Ordres*, *Transformations*, and her studies of concentric squares.
- [*Vera Molnár: Speak to the Eye*](https://www.centrepompidou.fr/en/program/calendar/event/PA7jRZ5), the Centre Pompidou's 2024 retrospective, with a short biography
- ["Vera Molnár, aux sources du code"](https://www.centrepompidou.fr/fr/pompidou-plus/magazine/article/vera-molnar-aux-sources-du-code), the Pompidou's long portrait, in French, with the sunsets over Lake Balaton in her own words
- [Her conversation with Hans Ulrich Obrist](https://vintage.hu/wp-content/uploads/2019/03/Molnar-Vera-HUO-interview.pdf), where she tells of the rule for the pastels, the door at Orsay, and the "1% of chaos"
- [Vera Molnár at the Digital Art Museum](https://dam.org/museum/artists_ui/artists/molnar-vera/), with her own statement on the *machine imaginaire* and on method, and a page for each series
- [Her entry in the compArt database](http://dada.compart-bremen.de/item/agent/14), a chronology year by year
- [An interview at Right Click Save](https://www.rightclicksave.com/article/an-interview-with-vera-molnar) (2022), on learning Fortran and on choosing among the results
- [*Interruptions* at the Victoria and Albert Museum](https://collections.vam.ac.uk/item/O1193775/interruptions-drawing-molnar-vera/), the plate the sketch was measured from
- [The New York Times obituary](https://ropac.net/news/1609-vera-molnar-pioneer-of-computer-art-dies-at-experimenting-with-algorithms-she-began-to-employ-the/), as her gallery reprints it

### About these homages

These sketches are homages after Vera Molnár, made for learning. They are not reproductions of specific works. They are not affiliated with or endorsed by the artist or her estate.

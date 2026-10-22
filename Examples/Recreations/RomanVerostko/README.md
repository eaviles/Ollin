#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Roman Verostko</sup>

---

## Roman Verostko

| [![Cyberflower](https://media.ollin.art/examples/Recreations/RomanVerostko/Cyberflower/still-640.jpg?v=c3260f2f)](Cyberflower/) | [![Pathway](https://media.ollin.art/examples/Recreations/RomanVerostko/Pathway/still-640.jpg?v=09cc52bc)](Pathway/) |  |  |
|---|---|---|---|
| [Cyberflower](Cyberflower/) | [Pathway](Pathway/) |  |  |

**Roman Verostko** (Tarrs, Pennsylvania, 1929; Minneapolis, 2024) was an American painter who wrote the software that made his paintings, and one of the founders of the Algorists. He entered the Benedictine community of Saint Vincent Archabbey in Latrobe, Pennsylvania, in 1950, was ordained a priest in 1959, and studied printmaking at Atelier 17 in Paris in 1962 and 1963. He left religious life in 1968 and taught at the Minneapolis College of Art and Design from that year until he retired in 1994. His paintings of the 1960s set two kinds of mark in one field: rectangles laid out and painted by rule, and gestures made as fast and as free of thought as he could make them. He called it "a visual dialectic between control and uncontrol."

He came to code through that dialectic. *The Magic Hand of Chance* (1982 to 1985) improvised drawings, titles, and nonsense sayings in real time on a monitor. Then came **Hodos**, Greek for a path or a road, the program that drove a pen plotter with fourteen pen stalls. The plotter drew with technical pens filled with inks he mixed himself, on rag paper. On December 12, 1987, it made its first stroke with a Chinese brush that he had fitted to its drawing arm. In 1988 he read "Epigenetic Painting: Software as Genotype" at the first International Symposium on Electronic Art, in Utrecht, and *Leonardo* published it in 1990. In it, the code is the genotype, "the code for 'how to make the work'". The painting is its phenotype, and making the work is epigenesis, the way a living form grows from its seed. Every painting from one program is one of a family, each one unique. The paper also sets out his rules. A starting point is found "by tossing dice weighted for not more than a 25% deviation from the center of a preferred region." A brush stroke grows from about eight to sixteen control points. And the program "remembers the stroke and can improvise with the same stroke in a scalar fashion," drawing it again smaller with a pen. The series that followed included *Pathway*, *Gaia*, *Scarab*, *Apocalypse* and *Ezekiel*. Then came illuminated pages in the manner of medieval manuscripts, some touched with gold or silver leaf, laid by hand over shapes the code had drawn. He won the first prize of the Golden Plotter in Gladbeck, Germany, in 1994. In 1995 he founded the Algorists with Jean-Pierre Hébert, artists who make their work with algorithms of their own. From 2000 he plotted the *Cyberflowers*: a single curved line repeating itself, thousands of times. He died in Minneapolis on June 1, 2024, aged 94.

He belongs in this set because he said plainly what a sketch with a seed is. The code is the work's genotype, each run grows one member of its family, and the artist's part is to write the code and then choose. The two sketches here grow a family the same way, a sheet each time around.

Learn more:

- [*Pathway Series, Bird 2*](https://collections.vam.ac.uk/item/O499689/) (1990) at the Victoria and Albert Museum, one brush stroke with the same gesture in the pen lines behind it and three plotted rectangles, and [*Lung Shan I*](https://collections.vam.ac.uk/item/O1243131/) (1989), the strokes mirrored across a sheet six feet wide
- [*Cyberflower, Sunshine Version I*](https://collections.vam.ac.uk/item/O499690/) (2008) at the V&A, two flowers in orange and yellow over each other, and [*Meditation*](https://collections.vam.ac.uk/item/O239648/) (1989), one brown pen
- ["Epigenetic Painting: Software as Genotype"](https://www.isea-archives.org/symposia/fisea-1988/presenter/fisea-1988_paper_verostko/), the 1988 paper, at the ISEA archive, and his own look back at it, ["Epigenetic Art Revisited"](https://verostko.com/archive/writings/epigen-art-revisited.html) (2003)
- [*The Diamond Lake Apocalypse: Epigenetic Art*](https://verostko.com/archive/statements/gladbeck1994.html), his 1993 statement on the brushes, the inks, and the illuminated pages
- [*Cyberflower Duet: Red and Green*](https://history.siggraph.org/artwork/roman-verostko-cyberflower-duet-red-and-green/) (2003) in the SIGGRAPH archive, with his note on the initiator stroke, and the [2000 exhibition](https://verostko.com/shows/tempe/tempe.html) that hung three of the first Cyberflowers
- [verostko.com](https://verostko.com/), his own site and archive, and the Minneapolis College of Art and Design's [notice of his death](https://www.mcad.edu/news/professor-emeritus-roman-verostko-passed-away-june-1-2024) in June 2024

### Recreations here

- [**Pathway**](Pathway/): the pen and brush paintings, after *Pathway Series, Bird 2* and *Lung Shan I*. One gesture is cast from control points chained at random, each a step and a turn from the last. The plotter lays it down once as a brush stroke, a solid body with a dry brush over it that drags off on the paper's grain at its end. The same gesture, drawn again at a small scale and turned a little, makes the thousands of fine pen strokes behind it, each placed around a point of the brush stroke itself. The strokes go down a pen at a time, warm inks first and cool ones last. Three thin rectangles of opposing hues, kept near gray, are filled with close lines and stand apart from the brush. `mirror` repeats it all across the sheet as *Lung Shan* does. `pens` picks the classical inks, the earth inks, or the one brown pen of *Meditation*. Every rule has a control: `controlPoints`, `turn`, `stepJitter`, `brushSize`, `brushWeight`, `strokes`, `minScale`, `maxScale`, `rotation`, `spread`, `planes`, `seconds`. Each cycle plots one painting, holds it, and plots the next of the family with the next seed. An original Ollin interpretation written from the drawings and his account of the procedure; his software was never published, so there is no code to port.

  ```sh
  swift run Example-Recreations-RomanVerostko-Pathway
  ```

  The plot back as a plotter's file: every pen stroke the gesture under its own scale, turn, and place, every rectangle its fill lines, and the brush as the flat ribbons of its two coats:

  ```sh
  swift run Example-Recreations-RomanVerostko-Pathway --seed 1 --export-svg pathway.svg --frame 1500
  ```

- [**Cyberflower**](Cyberflower/): the flowers of one curved line, after *Cyberflower, Sunshine Version I* and the *Cyberflower Duet*. The initiator, a curve through a few control points cast at random, sits small in the lower left. A flower is that curve repeated along a larger copy of itself, hundreds of times at even steps, each copy turned with the path and twisted a little further, and narrower toward the ends. What reads as a colored surface is very closely drawn lines, and where a copy lines up with its own path the ribbon folds and the lines crowd into a dark seam. `look` picks *Sunshine*'s two flowers in orange and yellow or one flower in the red or the green of the *Duet*. `lines`, `ribbon`, `twist`, and `taper` shape the flower, `controlPoints`, `turn`, and `stepJitter` the curve, and `lineWeight` and `density` the pen. The plotter draws the initiator and then every line in order, holds the sheet, and plots the next. How each copy moves along the path is this sketch's reading of "a single curved line repeating itself"; his own routine was never published.

  ```sh
  swift run Example-Recreations-RomanVerostko-Cyberflower
  ```

  Every line back as a polyline through the same points as the initiator, moved, turned, and scaled:

  ```sh
  swift run Example-Recreations-RomanVerostko-Cyberflower --seed 1 --export-svg cyberflower.svg --frame 1080
  ```

This is a homage after Roman Verostko, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or his estate.

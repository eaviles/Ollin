#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Hassan Sharif</sup>

---

## Hassan Sharif

| [![AngularLines](https://media.ollin.art/examples/Recreations/HassanSharif/AngularLines/still-640.jpg?v=27b46338)](AngularLines/) | [![DotsLinesForms](https://media.ollin.art/examples/Recreations/HassanSharif/DotsLinesForms/still-640.jpg?v=eb6e9c6b)](DotsLinesForms/) |  |  |
|---|---|---|---|
| [AngularLines](AngularLines/) | [DotsLinesForms](DotsLinesForms/) |  |  |

**Hassan Sharif** (1951, Dubai; 2016, Dubai) is the artist the Gulf's conceptual art starts with. He drew cartoons for the Dubai papers in the 1970s, then went to England on a scholarship: a foundation year in Leamington Spa, and from 1980 to 1984 the Byam Shaw School of Art in London, in the abstract and experimental department that Tam Giles ran. There he read the British constructivists and took up Kenneth Martin's *Chance and Order*, a way of drawing Martin had used since the late 1960s and set out in a sentence: "The points of intersection on a grid of squares are numbered and the numbers are written on small cards and then picked at random. A line is made between each successive pair of numbers as they are picked out." Sharif kept the numbered grid and the picking, and put rules of his own over them, arbitrary and over-elaborate on purpose, worked out on a draft paper he kept with the finished drawing. He called them semi-systems. "I am not a systematic person," he said. "If somebody tells me this isn't a system, I'll say: this isn't a system, it's a semi-system." He did not correct a slip: "I believe that art is a result of errors."

He went home in 1984 and spent the next thirty years making the ground other artists would stand on. He was a founding member of the Emirates Fine Arts Society in 1980, opened the Al Marijah Art Atelier in Sharjah in 1984 as a place for young artists to meet, wrote about art in Arabic, and from 2008 worked out of The Flying House in Dubai, a house his brother had turned into a space for his generation the year before. The semi-systems ran from 1983 into his last years beside the *Objects*, the bundles of rope, cloth, cardboard and hardware he tied and wove by the hour. A retrospective, *Experiments & Objects 1979-2011*, filled Qasr Al Hosn in Abu Dhabi in 2011. *I Am The Single Work Artist*, the largest show of his work, opened across the Sharjah Art Foundation's spaces in 2017 and went on to Berlin. Its title is a line he wrote in 1989, and one of its chapters is another: "...so I created a semi-system."

*Dots, Lines and Forms* (1984, ink on paper with one draft paper) is a semi-system in its plainest form: one table of cells drawn three times across a sheet, once as the points a line touches, once as the line itself, once as the line inside its square. In his last years he returned to the sheets of small angular lines, *Lines No 2* (2012) and the *Six Points* and *Seven Points Angular Lines* (2013), each line a few straight pieces through numbered crossings of a fine grid, the numbers on draft papers that hang beside the work. From those sheets he picked lines, seemingly at random, and made them large: one painted black across a red canvas, one cut in wood.

He belongs in this set because the draft paper is the program and the drawing is its run. Both sketches here keep the draft paper on the wall, so the numbers that made the picture can be read beside it.

Learn more:

- [Hassan Sharif on Wikipedia](https://en.wikipedia.org/wiki/Hassan_Sharif)
- [*Semi-Systems* at Alexander Gray Associates](https://www.alexandergray.com/series/hassan-sharif/hassan-sharif-semi-systems/), the series page with *Dots, Lines and Forms*, *Lines No 2*, and the *Angular Lines*, and the [2018 exhibition](https://www.alexandergray.com/exhibitions/376-hassan-sharif-semi-systems/) of the same name
- [*Hassan Sharif: I Am The Single Work Artist*](https://universes.art/en/specials/hassan-sharif), the Sharjah Art Foundation retrospective, and [its Berlin showing at KW](https://sharjahart.org/sharjah-art-foundation/exhibitions/hassan-sharif-i-am-the-single-work-artist-at-kw-institute-for-contemporary)
- [Hassan Sharif at Mathaf](https://mathaf.org.qa/en/encyclopedia/artists-biographies/hassan-sharif/), a biography with the *White Files*
- [*Works 1980-2012*](https://www.bidoun.org/articles/little-human-feats) in Bidoun, and [*Hassan Sharif, early art practice*](https://universes.art/en/nafas/articles/2009/hassan-sharif) in Nafas, two essays on the semi-systems and the performances they led to
- [Kenneth Martin, *Chance, Order, Change Drawing*](https://sainsburycentre.ac.uk/art-and-objects/31609-chance-order-change-drawing/) at the Sainsbury Centre, with Martin's own account of the method

### Recreations here

- [**DotsLinesForms**](DotsLinesForms/): the 1984 sheet, made again from new numbers. A cell is a square of nine points numbered like a keypad. Chance picks a pair of them for every column, and that pair is the column's line; the rows add a second line from the middle out to each point around the square in turn, so the first row is empty, the second holds the column's line alone, and the rest hold both. The table is drawn three times, dots, then lines, then squares with the lines inside, at `pace` cells a second, with the picks, the walk, and the rule on a draft paper beside it. `columns` and `rows` are the table, a finished sheet holds for `hold` seconds, `firstSheet` picks the first, and a press starts the next. An original Ollin interpretation written from the drawing and its method. There is no code to port: the work is ink on paper.

  ```sh
  swift run Example-Recreations-HassanSharif-DotsLinesForms
  ```

  The table back as marks, from a frame after all three panels are drawn:

  ```sh
  swift run Example-Recreations-HassanSharif-DotsLinesForms --export-svg sheet.svg --frame 720
  ```

- [**AngularLines**](AngularLines/): a sheet of angular lines and the canvas one of them became. Every cell is a square of twenty-five crossings, and its line is `points` of them picked without repeating, joined in the order they came. The draft paper writes the numbers down as they are picked, the pen draws each line in pencil at `pace` a second, and when the sheet is full one line is chosen at random, boxed in red, and painted as a black band across the red canvas. `columns` and `rows` are the sheet, `hold` how long the wall stays up, `firstSheet` the first sheet's number, and a press starts the next. An original Ollin interpretation written from the works.

  ```sh
  swift run Example-Recreations-HassanSharif-AngularLines
  ```

  Every line back as a polyline, the chosen one twice, from a frame after the canvas is painted:

  ```sh
  swift run Example-Recreations-HassanSharif-AngularLines --export-svg wall.svg --frame 840
  ```

This is a homage after Hassan Sharif, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or his estate.

#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Hassan Sharif</sup>

---

## Hassan Sharif

| [![AngularLines](https://media.ollin.art/examples/Recreations/HassanSharif/AngularLines/still-640.jpg?v=27b46338)](AngularLines/) | [![DotsLinesForms](https://media.ollin.art/examples/Recreations/HassanSharif/DotsLinesForms/still-640.jpg?v=eb6e9c6b)](DotsLinesForms/) |  |  |
|---|---|---|---|
| [AngularLines](AngularLines/) | [DotsLinesForms](DotsLinesForms/) |  |  |

**Hassan Sharif** (1951, Dubai; 2016, Dubai) is the artist the Gulf's conceptual art starts with. He drew cartoons for the Dubai papers in the 1970s, then went to England on a scholarship: a foundation year in Leamington Spa, and from 1980 to 1984 the Byam Shaw School of Art in London, in the abstract and experimental department that Tam Giles ran. There he read the British constructivists and took up Kenneth Martin's *Chance and Order*, a way of drawing Martin had used since the late 1960s and set out in a sentence: "The points of intersection on a grid of squares are numbered and the numbers are written on small cards and then picked at random. A line is made between each successive pair of numbers as they are picked out." Sharif kept the numbered grid and the picking, and put rules of his own over them, arbitrary and over-elaborate on purpose, worked out on a draft paper he kept with the finished drawing. He called them semi-systems. "I am not a systematic person," he said. "If somebody tells me this isn't a system, I'll say: this isn't a system, it's a semi-system." He did not correct a slip: "I believe that art is a result of errors."

He went home in 1984 and spent the next thirty years making the ground other artists would stand on. He was a founding member of the Emirates Fine Arts Society in 1980, opened the Al Marijah Art Atelier in Sharjah in 1984 as a place for young artists to meet, wrote about art in Arabic, and from 2008 worked out of The Flying House in Dubai, a house his brother had turned into a space for his generation the year before. The semi-systems ran from 1983 into his last years beside the *Objects*, the bundles of rope, cloth, cardboard and hardware he tied and wove by the hour. A retrospective, *Experiments & Objects 1979-2011*, filled Qasr Al Hosn in Abu Dhabi in 2011. *I Am The Single Work Artist*, the largest show of his work, opened across the Sharjah Art Foundation's spaces in 2017 and went on to Berlin. Its title is a line he wrote in 1989, and one of its chapters is another: "...so I created a semi-system."

*Dots, Lines and Forms* (1984, ink on paper with one draft paper) is a semi-system in its plainest form: one table of cells drawn three times across a sheet, once as the points a line touches, once as the line itself, once as the line inside its square. In his last years he returned to the sheets of small angular lines, *Lines No 2* (2012) and the *Six Points* and *Seven Points Angular Lines* (2013), each line a few straight pieces through numbered crossings of a fine grid, the numbers on draft papers that hang beside the work. From those sheets he picked lines, seemingly at random, and made them large: one painted black across a red canvas, one cut in wood.

*10th to 13th October No. 1 & No. 2* (1984) is four days of the same work with the trials left in. The first sheet holds four pages of them, grids of digits, Latin squares, a red checker, a plan for fifteen drawings in five groups, most of it crossed out in red. The second, dated the 13th, holds the rule that survived: a table of two-digit numbers, a wavy line that cuts it, the numbers on the line's left taken in red, each turned into the sum of its digits, the repeated sums dropped, and, in his hand beside an arrow, the sums turned into lines, semi-straight or wavy, on paper or directly on the wall. The drawing under it is forty-one ruled lines in seven bands, straight and wavy in turn. A year earlier, home in Dubai for the summer, he had taken the semi-systems off the paper: for *Body and Squares* (1983) he drew a grid of twenty-five squares on the ground with a cube, the whole grid the size of his body, and lay down on it position after position while a camera on a tripod recorded which squares the body covered, the outcome of calculations by chance and order written on a long grid pinned above the prints.

He belongs in this set because the draft paper is the program and the drawing is its run. All four sketches here keep the numbers on the wall beside what they made, so the picture can be read back off them.

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

- [**OctoberLines**](OctoberLines/): the second sheet of the October work, cut again by chance. The table is his, a header 2 3 4 5 6 and the rows 22 to 56; for every row the cut passes between two columns, starting anywhere and stepping at most one column as it goes down. The numbers on its left turn red, each becomes the sum of its digits on the list, the repeats are dropped, and the sums go into the red box in the order they came. Then the pen rules one band per sum, as many lines as the sum, straight and wavy bands in turn, on the sheet in its red frame and at the same scale as a wall on the right, since the sheet says the wall will do. `pace` is lines a second, a finished sheet holds for `hold` seconds, `firstSheet` numbers the first, and a press starts the next. An original Ollin interpretation written from the two sheets. There is no code to port: the work is ink on paper.

  ```sh
  swift run Example-Recreations-HassanSharif-OctoberLines
  ```

  The rule back as marks, from a frame after the wall is painted: the cut's place in each row names the numbers taken, and every band holds its sum's worth of lines.

  ```sh
  swift run Example-Recreations-HassanSharif-OctoberLines --export-svg wall.svg --frame 1320 --param hold=40
  ```

- [**BodyAndSquares**](BodyAndSquares/): the ground and the record. A grid of five by five squares, its side one height, numbered 1 to 25. For every position chance picks five numbers without repeating, one each for the head, the two hands and the two feet, and the body lies down so that each lands in its square, the joints found by relaxing a chain of fixed bone lengths under the squares' pull; a pick the body cannot reach is struck through on the record, as he struck out what failed, and picked again. Once the body is down, every square it lies across is read off the ground and filled in on the record beside a small print of the position. `positions` is how many a sheet holds, `every` the seconds between them, `hold` how long a full sheet stays, `firstSheet` the first sheet's number, and a press starts the next. An original Ollin interpretation written from the documentation. There is no code to port: the work is a grid on the ground, a body, and a camera.

  ```sh
  swift run Example-Recreations-HassanSharif-BodyAndSquares
  ```

  The record back beside the bodies, from a frame after the sheet is full: for each print, the squares its limbs and head pass through are the squares filled in next to it.

  ```sh
  swift run Example-Recreations-HassanSharif-BodyAndSquares --export-svg record.svg --frame 1920 --param hold=40
  ```

This is a homage after Hassan Sharif, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or his estate.

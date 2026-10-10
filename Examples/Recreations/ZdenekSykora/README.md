#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Zdeněk Sýkora</sup>

---

## Zdeněk Sýkora

| [![Lines](https://media.ollin.art/examples/Recreations/ZdenekSykora/Lines/still-640.jpg?v=cc5a2028)](Lines/) | [![Structure](https://media.ollin.art/examples/Recreations/ZdenekSykora/Structure/still-640.jpg?v=66774c06)](Structure/) |  |  |
|---|---|---|---|
| [Lines](Lines/) | [Structure](Structure/) |  |  |

**Zdeněk Sýkora** (1920, Louny; 2011, Louny) was a Czech painter who came to the computer by way of landscape. He studied art education and descriptive geometry in Prague from 1945. From 1947 he taught at Charles University's Faculty of Education, where he stayed until 1980. Through the 1950s he painted the country around Louny in the open air. In 1959 he saw the Matisse collection at the Hermitage. The gardens he painted afterwards lost their detail, and by 1960 geometric shapes were all that was left. His first *Structures*, from 1962 and 1963, are grids of rectangles, each cut into five fields of black, white, and two grays. He placed them by hand under one rule of his own: where he could, two fields of the same color should not touch.

He wanted more rules than he could keep in his head. So he went to a friend from his home town, the mathematician Jaroslav Blažek (1925 to 2007), who taught at Charles University. Sýkora designed a set of elements made of half-circles in a square, and the rules for how an element may meet the ones beside it. Blažek put them into a program for an LGP-30, a small computer of the day. Sýkora drew a chart with a few elements placed and plus and minus signs where the picture should darken or lighten. The machine filled in the rest and typed it as a table of codes, and he painted the table in oil, using airbrushes and templates. The first computed *Structures* date from 1964, after years of working out a method together. He called the set of elements and the rules the two creative acts. One painting came to differ from the last, he said, by a change of the chart, the coefficient, and the rule. The two of them published the method in *Leonardo* in 1970. By then his work had been shown at Documenta 4 in Kassel, and the National Gallery in Prague had bought its first *Structures*.

In 1972 and 1973 he enlarged the half-circles in the *Macrostructures* until the borders between black and white became lines, and the lines took over. A line was built from tangents, each beginning where the one before it ended, with an arc at every angle. At first the tangents ran along a grid and its diagonals, which he found too stiff. Then they took the twelve directions of a clock face, and later any even number of degrees. From 1980 chance decided everything that mattered: how many lines, where each starts, its width, length, color, and course, and how the lines cross. The numbers came first from a canvas bag and later from a computer, which he called "a mechanical bag full of numbers". He married his former student Lenka in 1983, and from 1985 Lenka Sýkorová worked with him on the scores and the construction of the pictures. *Lines No. 24* (1983 to 1984), which he later called *The Last Judgement*, is three meters square and holds 227 lines. In 2001 *Lines No. 137* (1997) became the logo of the new MUMOK in Vienna. He died in Louny on July 12, 2011.

He belongs in this set because both of his methods are rules you can hold. One is a set of twenty elements and four questions, and the other is a score of numbers. The 1970 article printed a whole run of the program, its chart and the table the machine typed. So the reading of the rule in *Structure* was checked against the machine's own decisions. Replayed through that reading, the article's chart gives back the printed group for 182 of the 196 cells the machine decided. All but 8 of the printed elements pass the rule. Two details the descriptions leave open were settled that way: what "does not continue" means, and where a density halfway between two groups goes. For the *Lines* he described the score himself, and *Lines* keeps every number he named.

Learn more:

- The artist's [own site](http://www.zdeneksykora.cz/), kept by the estate, with his [biography](http://www.zdeneksykora.cz/?language=en&s=zivotopis). Interviews with him: [Josef Hlaváček, 1968](http://www.zdeneksykora.cz/?language=en&s=167), [Vítek Čapek, 1982 to 1985](http://www.zdeneksykora.cz/?language=en&s=156), [Vít Petrjanoš, 1991](http://www.zdeneksykora.cz/?language=en&s=170), and [Lenka Lindaurová, 1995](http://www.zdeneksykora.cz/?language=en&s=175)
- Zdeněk Sýkora and Jaroslav Blažek, ["Computer-Aided Multi-Element Geometrical Abstract Paintings"](https://doi.org/10.2307/1572257), *Leonardo* 3, no. 4 (1970)
- Martina Losová, [*Matematické aspekty výtvarného díla Zdeňka Sýkory*](https://theses.cz/id/omz3sw/78263-743598547.pdf) (Mathematical aspects of the art of Zdeněk Sýkora), diploma thesis, Palacký University Olomouc (2010). It rebuilds the article's method step by step and reproduces its figures
- [*Linie č. 39*](https://www.ghmp.cz/vystavy/zdenek-sykora-linie-c-39) and [*Černobílá struktura*](https://www.ghmp.cz/en/exhibitions/kopie-kzdenek-sykora-cernobila-struktura/) at the Prague City Gallery
- The obituary in [*The Guardian*](https://www.theguardian.com/artanddesign/2011/jul/19/zdenek-sykora-obituary)

### Recreations here

- [**Structure**](Structure/): the computer-assisted *Structures*, after the rule Sýkora and Blažek published in 1970. Each of the twenty elements is a square holding half-discs of half its width, white on black or black on white. They fall into four groups by how much of them is black. A chart of `columns` by `rows` begins with a share of cells placed by hand (`inputs`), half of them in pairs that close a circle. Plus and minus signs lie in patches (`marks`). The machine walks the chart row by row, left to right and then back right to left. At each empty cell it averages the groups of the placed cells around it. It adds `coefficient` under a plus, takes it away under a minus, and takes the nearest group. Then it keeps the elements of that group that answer the rule. The question is whether the color continues across a shared side, and whether the shape does, two half-discs meeting in a circle. `rule` is the answer it wants: both, the color only, the shape only, or neither, the article's rules 0 to 3. It draws among whatever is left. The left sheet shows the chart and the codes typed in the order the machine decided them. The canvas on the right is painted one template at a time, every cell of an element at once, then holds and fades back. A press deals the next chart. The charts are the sketch's own, and the agreement with the printout quoted above was measured on the article's chart. An original Ollin interpretation written from the published rule. There is no code to port.

  ```sh
  swift run Example-Recreations-ZdenekSykora-Structure
  ```

  The canvas comes back as a rectangle for each black ground and a polygon for each half-disc, starting at its center. The chart's signs and underlines come back as lines. Walking the chart again gives back every group and admits every element:

  ```sh
  swift run Example-Recreations-ZdenekSykora-Structure --seed 1 --export-svg structure.svg --frame 1530
  ```

- [**Lines**](Lines/): the *Lines*, from 1973, after Sýkora's own account of the score. Each of `lines` lines starts at whole centimeters on a canvas 150 centimeters square and takes a width from 0.2 to 4 centimeters. Its color is one to five of thirty oil paints, mixed one to one the way pigments mix. It runs along three to eight tangents of 8 to 60 whole centimeters, each beginning where the last one ended. `directions` is the stage of the rule: the grid's eight directions, the clock's twelve, or every even degree. At each angle an arc touches both tangents half the shorter one's length from where they meet. So its radius follows from the lengths and the angle, as he described. A sharp turn on short tangents makes a tight curl, and a line that turns straight back folds on itself. Where two lines cross, the next number of a series of ones and twos decides which one goes over. The crossings are walked line by line in the order of the score. Over one cycle the lines are drawn in pencil, painted one after another, and the crossings settled. Then the picture holds and fades back. A press writes the next score. The ranges, the thirty paints, and the reading of his radius formula are the sketch's own. An original Ollin interpretation written from what he said of the method.

  ```sh
  swift run Example-Recreations-ZdenekSykora-Lines
  ```

  The score comes back from the file. Every line is one polyline at its width, with the ends of every arc written twice. From it the start, every tangent's direction and length, and the reach of every arc can be read. Each settled crossing is drawn again inside a clip of the place where the two lines overlap, which shows the line on top:

  ```sh
  swift run Example-Recreations-ZdenekSykora-Lines --seed 1 --export-svg lines.svg --frame 1836
  ```

This is a homage after Zdeněk Sýkora, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or his estate.

#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Eduardo Terrazas</sup>

---

## Eduardo Terrazas

| [![Cosmos](https://media.ollin.art/examples/Recreations/EduardoTerrazas/Cosmos/still-640.jpg?v=a647e5d5)](Cosmos/) | [![Posibilidades](https://media.ollin.art/examples/Recreations/EduardoTerrazas/Posibilidades/still-640.jpg?v=db08f27a)](Posibilidades/) |  |  |
|---|---|---|---|
| [Cosmos](Cosmos/) | [Posibilidades](Posibilidades/) |  |  |

**Eduardo Terrazas** (Guadalajara, 1936) trained as an architect. He took his degree at the Universidad Nacional Autónoma de México in 1958 and a master's in architecture at Cornell University in 1960. He was one of the authors of the design and identity program of the 1968 Olympic Games in Mexico City, working for the architect Pedro Ramírez Vázquez; Lance Wyman and Beatrice Trueblood are among the others credited with it.

In 1970 he began the *Tablas*, made with Santos Motoaaopohua de la Torre de Santiago, a Huichol artisan who lived and worked with him for several years. They are made the Huichol way: a wooden board is covered with Campeche wax, and colored wool yarn is pressed into it a strand at a time. He has said that the idea was to bring modern art and craft together, and that a small Huichol piece set it off. The *Tablas* were his first solo exhibition, at the Palacio de Bellas Artes in Mexico City in 1972. His site's account of them says the yarn over the waxed board "triggers a movement of the image in concentric lines."

Early in the 1970s he looked for a way to work in series, and settled on one structure to be worked again and again: *Posibilidades de una estructura*, Possibilities of a Structure. It has five subseries, *Nueve círculos*, *Retícula*, *Diagonales*, *Código de barras*, and *Cosmos*, which is the largest. He numbers the works rather than titling them, by series, subseries, and work, so a *Cosmos* piece reads 1.1 and then its own number. Some are drawings in ink, and the Art Institute of Chicago holds one, *1.1.3.* of 1974.

The *Cosmos* structure is a diagram, and he says what each part stands for. The "two lines drawn horizontally and vertically are the X and Y coordinates." A circle around them stands for the universe, like the celestial dome of the Greeks, and a smaller circle inside it for planet Earth. A square turned 45 degrees inside the large circle is "a structural frame for the universe," where he places the four fundamental forces: gravity, electromagnetism, the strong nuclear force, and the weak one. And "the two diagonal lines that cross the image and intersect beyond the cosmic horizon, represent the infinite in the Cosmos." All of it sits in a square. "To make it more understandable for me and to transmit it to my fellow human beings," he has said, "I decided that a cosmos is a square."

Those lines wall the square into thirty-two fields, and a work is one way of treating them. The Museo del Palacio de Bellas Artes, which showed his work of 1968 to 2023 as *Equilibrio múltiple*, lists where the variation happens: in the lines ("multiplication, repetition, subtraction, expansion, blurring, cutting, widening, color change") or in the spaces between them ("shading, emptiness, segmentation, coloring, filling"). In the yarn pieces the rows run beside a field's own edges and work inward, as the photographs show. A gallery text describes the result: the yarn "is twisted and pressed into place as it changes direction to complete each area of color, giving the resulting work a series of architectural bevels." The Museo Amparo counted more than three hundred works in the series, and pieces dated 2024 and 2025 show it still growing. One of the early ones, *1.1.91* (1970 to 1972), hung in the 2024 Venice Biennale.

He belongs in this set because the series is a program in the plain sense: one structure, a short list of operations on its lines and its spaces, and a number for each result. The yarn follows a rule too. A strand runs beside the nearest edge of its field, so the whole tabla can be drawn by asking of every point which edge is closest and how many strands lie between. He joins [Manuel Felguérez](../ManuelFelguerez/), [Vicente Rojo](../VicenteRojo/), and [Kazuya Sakai](../KazuyaSakai/), the folder's other artists who worked in Mexico City.

Learn more:

- The artist's own pages on [*Possibilities of a Structure*](https://eduardoterrazas.com/index.php/possibilities-of-a-structure/), on [*Cosmos*](https://eduardoterrazas.com/index.php/cosmos/), with his diagram of the structure, and on the [*Tablas*](https://eduardoterrazas.com/index.php/tablas/)
- [*1.1.3.*](https://www.artic.edu/artworks/239806) (1974), an ink drawing of the *Cosmos* subseries at the Art Institute of Chicago
- [*Encounters*](https://www.timothytaylor.com/exhibitions/239-eduardo-terrazas-encounters/) (2024) and [*Cosmos within a cosmos*](https://www.timothytaylor.com/exhibitions/67-eduardo-terrazas-cosmos-within-a-cosmos/) (2018) at Timothy Taylor, the second with the account of how the yarn is laid
- [*1.1.117*](https://museoamparo.com/imprimir/4364/1-1-117-de-la-serie-posibilidades-de-una-estructura) at the Museo Amparo in Puebla (in Spanish), with his words on the square, its diagonals, and the celestial dome
- [*From Olympic logo to cosmic order*](https://www.theartnewspaper.com/2018/02/24/from-olympic-logo-to-cosmic-order-how-eduardo-terrazas-pushes-his-universal-vision-forward), Sarah P. Hanson's piece in *The Art Newspaper* (2018)
- [Eduardo Terrazas at the Museo Experimental El Eco](https://eleco.unam.mx/?p=2186), Mexico City, on how the work with Santos Motoaaopohua de la Torre de Santiago began

### Recreations here

- [**Cosmos**](Cosmos/): one tabla in yarn. The structure is drawn as he states it: the square, the circle that fills it, the two axes, the two diagonals, the square turned 45 degrees, and the small circle, whose radius is `earth` of the large one's (he gives no number; his diagram measures 0.41). The seed deals the possibility, `colors` wools over the thirty-two fields from the center out, each field taking a color none of its neighbors has or, with chance `sharing`, a neighbor's. The yarn is laid as the tablas are: every strand runs beside the nearest edge of its field, `pitch` pixels apart, counted in from the edge, so the rows turn where two edges' rows meet and leave a crease there. Neighbors of one color are one field, laid as one, which is where the long creases come from. `lines` lays the structure's own lines as bands of white or black yarn, `lineStrands` strands wide and running lengthwise, and then every field stands alone inside its bands. `wools` picks the dyed set or one built around the hue `keyHue`, and `relief` is how round the strands read. Over one cycle of `seconds` the finished tabla is taken back to the bare waxed board with the lines scored in it, and laid again one color after another.

  ```sh
  swift run Example-Recreations-EduardoTerrazas-Cosmos
  ```

  The thirty-two fields as closed outlines in their colors, cut from the structure's own lines, with the lines over them when they are bands:

  ```sh
  swift run Example-Recreations-EduardoTerrazas-Cosmos --seed 5 --param lines=white --export-svg cosmos.svg
  ```

- [**Posibilidades**](Posibilidades/): a sheet of `across` by `across` small drawings, each the same structure after one of the operations the museum's list names. **coloring** fills every field. **widening** draws the lines as white or black bands over the fields. **multiplication** repeats lines beside themselves, the circles as concentric rings or the straight lines as parallels, and colors the fields in turn so that no two sharing an edge match. **subtraction** leaves some lines out, and the fields they divided become one. **shading** rules every other field with stripes. **emptiness** leaves some fields as bare paper. **repetition** draws the structure four times in the square. `operation` holds the sheet to one of them or deals all seven across it, `colors` is how many colors a drawing uses, and the seed deals every drawing. The fields are never listed by hand: the lines that are left go to `regions(enclosedBy:)`, which hands back every field they wall off, so taking a line out or putting one in changes the fields with no other code. Over one cycle of `seconds` each drawing in turn is redrawn as another possibility, field by field, and then each is drawn back.

  ```sh
  swift run Example-Recreations-EduardoTerrazas-Posibilidades
  ```

  One drawing as a file, every field a closed outline in its color:

  ```sh
  swift run Example-Recreations-EduardoTerrazas-Posibilidades --seed 4 --param across=1 --param operation=multiplication --export-svg posibilidades.svg
  ```

These are homages after Eduardo Terrazas, made for learning. They are not reproductions of specific works, and they are not affiliated with or endorsed by the artist or by the galleries and museums that show and hold the works. The marks of the 1968 Olympic Games are not drawn here.

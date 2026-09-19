#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Gego</sup>

---

## Gego

| [![DrawingWithoutPaper](https://media.ollin.art/examples/Recreations/Gego/DrawingWithoutPaper/still-640.jpg?v=a8475e98)](DrawingWithoutPaper/) | [![Reticularea](https://media.ollin.art/examples/Recreations/Gego/Reticularea/still-640.jpg?v=3a9ba4cc)](Reticularea/) |  |  |
|---|---|---|---|
| [DrawingWithoutPaper](DrawingWithoutPaper/) | [Reticularea](Reticularea/) |  |  |

**Gego** (Hamburg, 1912 to Caracas, 1994) was born Gertrud Louise Goldschmidt and took her diploma in architecture and engineering at the Technische Hochschule in Stuttgart, where she studied under Paul Bonatz. She was Jewish, and in 1939 she left Germany for Venezuela with little more than that training. She worked for years in Caracas as an architect, a furniture maker and an industrial designer, became a Venezuelan citizen in 1952, and only then turned to art. Her first sculptures are from 1957, when she was in her middle forties. The name is the two halves of her own: **Ge**rtrud **Go**ldschmidt.

She arrived in the middle of a country that was building itself in a hurry and making a confident geometric art to match. Her friends and contemporaries were making kinetic art out of repeated modules, painted in series, engineered to be exact. Gego kept a certain distance from all of it, and refused every label anyone offered her, including the one for what she made: "Sculpture, three-dimensional forms of solid material. Never what I make."

What she made instead was line. In 1967 she took up stainless steel wire, which is thin, springy, and needs no foundry: it let her work alone, without welders or blacksmiths. To join it she worked out a system of ties, and of wires twisted at their ends so several could meet at one point, and from then on the joining was done by her own hands, one node after another.

That brought her, in June 1969, to the **Reticulárea** at the Museo de Bellas Artes in Caracas: modules of wire, most of them triangles, tied into a continuous net that spanned the ceiling and came down the walls until the room itself was inside it. It has no center, no row, and no repeated part, and it holds together by the intensity of its nodes rather than by a frame. Nothing about it is fixed, either: she took it down and tied it up again for one room after another between 1969 and 1982, and a permanent version lives at the Galería de Arte Nacional in Caracas. Visitors described walking into it as walking into weather. A reviewer at the time called her a web-fairy.

From about 1976 she made the **Dibujos sin papel**, drawings without paper, and the title is the argument. They are small pieces of bent wire and studio scrap, cork and thread and springs and nails and bits of tubing, hung a short distance off the wall. The wire is the line and the wall is the paper, and when the light falls on one the shadow it throws is the other half of the drawing. She went on making them until 1988.

She taught, too, at the School of Architecture of the Universidad Central de Venezuela and for years at the Instituto de Diseño of the Fundación Neumann, where she was a founding member and brought her own Bauhaus schooling to Venezuelan architects and designers. Her other series carry the same hand into different shapes: the Chorros that pour, the Troncos that stand, the Esferas, the woven Tejeduras.

She belongs in this set because she is the clearest case of an artist whose work is a structure and a drawing at the same time. A net of rods hanging under gravity is a thing a simulation is good at; a line that thins as it goes away from you is a thing a renderer is good at; and her work is exactly where those two meet.

Learn more:

- [*Gego: Measuring Infinity*](https://www.guggenheim.org/wp-content/uploads/2023/03/press-kit-gego-measuring-infinity-20230331.pdf), the retrospective organized with the Fundación Gego, at Museo Jumex in Mexico City (2022), the Guggenheim in New York (2023) and the Guggenheim in Bilbao (2023 to 2024)
- [*Dibujos sin papel (ca. 1976–88)*](https://www.guggenheim-bilbao.eus/en/exhibition/dibujos-sin-papel-ca-1976-88), on how the drawings without paper were made and how they hang
- [*Gego: An Unruly Artist in a Class of Her Own*](https://gagosian.com/quarterly/2023/04/05/essay-gego-an-unruly-artist-in-a-class-of-her-own/), on her training, her distance from the kinetic artists around her, and her refusal of the word sculpture
- [*Reticulárea*](https://www.macba.cat/en/obra/r4344-reticularea/) at MACBA, a drawing from the year of the installation, described as a network of centerless nodules
- [*Gego's Reticulárea: Transcending Space and Time*](https://yalebooks.yale.edu/2014/02/17/gegos-reticularea-transcending-space-and-time/), on the work as an environment rather than an object
- [*Gego: Measuring Infinity*](https://brooklynrail.org/2023/05/artseen/Gegos-Measuring-Infinity/) reviewed in the Brooklyn Rail, which notices the darkened junctions where the wires are reinforced
- Mónica Amor, *Another Geometry: Gego's Reticulárea, 1969–1982*, in October 113 (2005), the closest reading of what kind of geometry the net is

### Recreations here

- [**Reticularea**](Reticularea/): after the *Reticulárea* (1969 to 1982). A net tied out of irregular triangles, hung at eight points, six on the ceiling and two a meter below it out at the sides, and left to gravity. The points it is built on are scattered with a density that knots up in some places and opens out in others, joined to their neighbors, and any triangle too big for a hand to have tied is dropped, which is what leaves the edge frayed rather than cut. The triangles that remain are the net, and they are handed to the simulation exactly as they are drawn, so nothing invisible holds it up. There is a good deal more net than the ties are spread over, so it has to fall into folds and come down at the sides. The air in the room moves the ties, and the whole net moves with them. `nodes` is how fine the net is, `openings` how much of it was left out, `air` how much the room moves, and `orbit` how fast you walk around it. Drag a wire to take hold of it.

  ```sh
  swift run Example-Recreations-Gego-Reticularea
  ```

  Two frames of the same net from a fixed eye, which is what the net's laws are read from. Each node's dot is sized by how far off it is, so the drawing carries its own depth and the wires can be measured as wires:

  ```sh
  swift run Example-Recreations-Gego-Reticularea --export-svg a.svg --frame 600 --param orbit=0 --seed 4181
  swift run Example-Recreations-Gego-Reticularea --export-svg b.svg --frame 780 --param orbit=0 --seed 4181
  ```

- [**DrawingWithoutPaper**](DrawingWithoutPaper/): after the *Dibujos sin papel* (about 1976 to 1988). A lattice of wire that used to be a grid, bent out of true by hand, hanging a few centimeters off the wall while a lamp crosses in front of it. Every point of the wire carries how far off the wall it is, and its shadow is where the ray from the lamp through that point lands, so the frame, which stands off furthest, is thrown furthest, and the shadow is never a copy of the piece. Wires go in one at a time until the piece is made, and then it hangs. The air moves the wire by a millimeter and the shadow by rather more, which is the thing the work is about. `pace` is how fast it is made, `lampDistance` how far the lamp stands off the wall, `sweep` how long it takes to cross, and `air` how much the room moves.

  ```sh
  swift run Example-Recreations-Gego-DrawingWithoutPaper
  ```

  One frame as marks, which is what the shadow's laws are read from: every wire, its shadow, and the lamp lie on one line, so the drawing says where the lamp was:

  ```sh
  swift run Example-Recreations-Gego-DrawingWithoutPaper --export-svg piece.svg --frame 900
  ```

These are homages after Gego, made for learning. They are not reproductions of specific works, they are not affiliated with or endorsed by the artist's estate or the Fundación Gego, and none of her work was used to make them.

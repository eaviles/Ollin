#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Monir Shahroudy Farmanfarmaian</sup>

---

## Monir Shahroudy Farmanfarmaian

| [![BehindGlass](https://media.ollin.art/examples/Recreations/MonirFarmanfarmaian/BehindGlass/still-640.jpg?v=3cb6caa2)](BehindGlass/) | [![MirrorFamily](https://media.ollin.art/examples/Recreations/MonirFarmanfarmaian/MirrorFamily/still-640.jpg?v=199d7977)](MirrorFamily/) |  |  |
|---|---|---|---|
| [BehindGlass](BehindGlass/) | [MirrorFamily](MirrorFamily/) |  |  |

**Monir Shahroudy Farmanfarmaian** (Qazvin, 1922 to Tehran, 2019) made mirror mosaic into modern sculpture. She studied at the Faculty of Fine Arts in Tehran, sailed for New York in 1945, and studied at Cornell, at Parsons, and at the Art Students League while she worked as a fashion illustrator. In those years she knew the painters of the New York School. She went home to Iran in 1957, won a gold medal in Iran's pavilion at the 1958 Venice Biennale, and spent the next years traveling the country and collecting what it made by hand: Turkmen jewelry, coffeehouse paintings, and the flowers and birds of old paintings on the back of glass.

In 1966 she took two American artist friends to the Shah Cheragh shrine in Shiraz, whose walls and domes are lined with cut mirror. "The very space seemed on fire," she wrote later, with the lamps multiplied in every piece, and "I imagined myself standing inside a many-faceted diamond and looking out at the sun." Mirror mosaic, *āina-kāri*, was a craft of architectural decoration, passed from father to son and kept for men. She learned it with the master craftsman Hajj Ostad Mohammad Navid, who became her teacher and collaborator. In her studio, craftsmen cut the mirror into strips and small shapes and set them in plaster on wood beside pieces of reverse-painted glass, to designs she drew and calculated.

The 1979 revolution began while she was visiting New York, and it kept her there for most of the next twenty-five years. Without the thin mirror or the craftsmen, she drew, took commissions, and designed textiles. In 2004 she reopened her studio in Tehran, and her most ambitious work followed: the geometric *Families*, the *Convertibles* whose pieces can be hung in many arrangements, and the *Mazes*. The retrospective *Infinite Possibility. Mirror Works and Drawings 1974–2014* opened at the Serralves Museum in Porto in 2014 and at the Guggenheim in New York in 2015. The Monir Museum, which holds 51 works she gave to the University of Tehran, opened in the Negarestan Garden in 2017. It was the first museum in Iran given to a woman artist's work.

"Nothing is done spontaneously; it is all a calculation of geometry and design," she said. She described every polygon she used as a circle divided into equal arcs: three arcs give a triangle, four a square, and so on up to the twelve-sided dodecagon. She gave each number its meaning (the pentagon's five sides are the five senses, the hexagon's six the directions), and she came back most often to the hexagon: "All the mosques in Iran, with all the flowers and the leaves and curves and so on, are based on hexagons."

She belongs in this set because a rule decides every piece of her work: the circle, the number of arcs, and what that number means. A sketch works from the same kind of rule, and a renderer that traces reflections can show what a relief of tilted mirror does with the room around it.

Learn more:

- [*Infinite Possibility. Mirror Works and Drawings, 1974–2014*](https://www.guggenheim.org/exhibition/monir), the Guggenheim retrospective
- [*Variations on the Hexagon*](https://collections.vam.ac.uk/item/O129166/variations-on-the-hexagon-mosaic-panel-monir-shahroudy-farmanfarmaian/) (2006), a panel of the installation made for the opening of the V&A's Jameel Gallery, with a close description of how mirror mosaic is set
- [*Tir*](https://www.artmuseumgr.org/collection/tir) (2015) at the Grand Rapids Art Museum, one of the *Convertibles*, with a plain account of reverse-glass painting
- [*The First Family*](https://www.hainesgallery.com/exhibitions/63-monir-shahroudy-farmanfarmaian-the-first-family/) at Haines Gallery, with her statement on dividing the circle
- [*Mirror-works and Drawings (2004–2016)*](https://jamescohan.viewingrooms.com/viewing-room/24-monir-shahroudy-farmanfarmaian-mirror-works-and-drawings-20042016-gallery-exhibition-at-48-walker-st-291/), a gallery viewing room with the *Families*, the *Mazes*, the *Convertibles*, and her words on the meaning of each polygon
- [*A Mirror Garden*](https://high.org/exhibition/monir-farmanfarmaian-a-mirror-garden/) at the High Museum of Art (2022), which shares its title with her memoir, written with Zara Houshmand
- *Monir*, the documentary by Bahman Kiarostami

### Recreations here

- [**MirrorFamily**](MirrorFamily/): after the *Families* (2010 to 2016), with the facets after *Untitled Heptagon 11* (2016). Each member of a family is a polygon cut from the circle by her rule, and the family runs from the triangle to the decagon. Inside the outline, every side's triangle is cut into rows of small triangles, and each small triangle is a piece of mirror set in plaster. Every third point of that lattice is pressed up, so every piece tilts and each raised point becomes a six-sided star of mirror. Some stars are painted glass instead, arranged as a star with one point for each side. The pieces are set from the center out, and then a lamp moves in front of the finished relief. The reflections are traced against a real room: a pale ceiling hung with lamps, a dark floor, a doorway. `firstSides` picks the first member, `rings` how finely each side is cut, `pace` how many pieces go in a second, and `hold` how long the finished relief hangs. An original Ollin interpretation written from the works and from her own account of the geometry.

  ```sh
  swift run Example-Recreations-MonirFarmanfarmaian-MirrorFamily
  ```

  The relief back as meshes, one triangle per piece, from a frame after the setting is done:

  ```sh
  swift run Example-Recreations-MonirFarmanfarmaian-MirrorFamily --export-usdz relief.usda --frame 600
  ```

- [**BehindGlass**](BehindGlass/): after the *Mazes* (2014 and 2015), where channels of glass painted green on the back spiral in toward the middle between strips of mirror. Reverse-glass painting has to be done backwards: what is painted first ends up on top, so the lines go on first and the backing last, and everything is painted as its own mirror image. The sketch paints one pane that way, from behind. It lays the blue edges of every channel and the outline of a flower, then sponges the green into the channels and the red into the petals, then covers the whole back with silver, which hides everything. Then it turns the pane over. Each polygon is split into kites, one at each corner, and a kite always has a circle touching all four of its sides, so a spiral stepped in from every side meets in the middle. `firstSides` picks the first panel, `band` the distance from one lap to the next, `pace` the speed of the hand, and `hold` how long the finished pane hangs. An original Ollin interpretation. Her mazes are cut pieces of painted glass and mirror set side by side; the sketch paints all of it on one pane, so the order of the layers can be seen.

  ```sh
  swift run Example-Recreations-MonirFarmanfarmaian-BehindGlass
  ```

  The pane from behind, when the silver is on, and from the front, as marks in the order they were painted:

  ```sh
  swift run Example-Recreations-MonirFarmanfarmaian-BehindGlass --export-svg back.svg --frame 840
  swift run Example-Recreations-MonirFarmanfarmaian-BehindGlass --export-svg front.svg --frame 1100
  ```

This is a homage after Monir Shahroudy Farmanfarmaian, made for learning. It isn't a reproduction of a specific work, it isn't affiliated with or endorsed by the artist or her estate, and none of her work was used to make it.

#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Manuel Felguérez</sup>

---

## Manuel Felguérez

| [![EspacioMultiple](https://media.ollin.art/examples/Recreations/ManuelFelguerez/EspacioMultiple/still-640.jpg?v=53c3b13a)](EspacioMultiple/) | [![MaquinaEstetica](https://media.ollin.art/examples/Recreations/ManuelFelguerez/MaquinaEstetica/still-640.jpg?v=d66d2cfa)](MaquinaEstetica/) | [![RelieveLacado](https://media.ollin.art/examples/Recreations/ManuelFelguerez/RelieveLacado/still-640.jpg?v=c546d92f)](RelieveLacado/) |  |
|---|---|---|---|
| [EspacioMultiple](EspacioMultiple/) | [MaquinaEstetica](MaquinaEstetica/) | [RelieveLacado](RelieveLacado/) |  |

**Manuel Felguérez** (1928-2020) was a Mexican painter and sculptor, born in Valparaíso, Zacatecas. He was one of the leading figures of the *Generación de la Ruptura*, the generation that broke with muralism in the middle of the century. He worked in hard-edge geometric abstraction, in sober tones, on canvas and in metal. In 1998 he opened the country's first museum of abstract art in his home state.

**"El espacio múltiple" (1973)** came first. In December 1973 the Museo de Arte Moderno in Mexico City opened a show of that name: forty-odd small works in pairs, an ink drawing on paper and the acrylic on card painted from it, with titles like *Punto inicial*, *Combinación 144D* and *Estímulo B*, and beside them reliefs and small sculptures. Felguérez wrote the method down himself. Start from a few simple geometric concepts, the circle, the triangle, the square, and organize them into a form-idea. Draw it in pencil and give it an order. Think of silver and surround it with a few cold colors, or of gold and surround it with warm ones, give the color an order too, and paint the drawing as a design made of planes. Every plane holds infinitely many volumes: choose one and make a relief, and the color takes that dimension with it. Then take the volume out into space, and show that painting, relief and sculpture were never three things. Octavio Paz wrote the catalog text that November: from a form and a color in two dimensions, by successive combinations, to the relief, and from the relief to sculpture; not a space to look at, but a space for building other spaces. The series grew out of work he did that year at UNAM's computing center, which is where the machine below began.

**"La máquina estética" (1975-1977)** is the reason he belongs in this set. Felguérez held that the information in a picture sits in the balance between its forms, not in the forms themselves. He had tested that idea on his own work: he cut the shapes out of his paintings and weighed the pieces. With a Guggenheim Fellowship he went to Harvard, and with the systems engineer Mayer Sasson he turned that theory into a program. The program carried an alphabet of eight geometric elements, and the compositional rules his own paintings kept to. The design lay in a field of six by eight units. Each of the four invisible edges of that field had to be touched by at least one element. A random term made every design different, and the balance decided which ones passed. A plotter drew one design every eleven seconds, up to two hundred in a day.

The machine made drawings, not pictures. Felguérez kept the ones he wanted and painted them afterward, and by 1975 the designs he kept were also going into relief: lacquered cardboard, aluminum and metal, each element cut out and set a step above the last. He saw the choosing as putting the person back at the center of the work. He is a rare case, a Mexican geometrist who was also a computer artist. His way of working was to let a machine propose and a person choose.

Learn more:

- [Manuel Felguérez on Wikipedia](https://en.wikipedia.org/wiki/Manuel_Felgu%C3%A9rez)
- [*El espacio múltiple*](https://libros.uanl.mx/index.php/u/catalog/book/3), the 2012 UANL edition of the 1973 show, with Octavio Paz's text and the pairs of drawing and painting, open access
- [*Espacio múltiple: Manuel Felguérez (1928-2020)*](https://arquine.com/espacio-multiple-manuel-felguerez-1928-2020/), Arquine's note on the show, with his own account of the circle and the square
- [*Manuel Felguérez*](https://www.uam.mx/difusion/plasticas/felguerez/felguerez.pdf), the UAM's monograph, which quotes his reflection on the show in full
- [*Manuel Felguérez: una máquina estética*](https://cultura.uam.mx/manuel-felguerez-una-maquina-estetica/), the exhibition of the project at the UAM
- [*La máquina estética*](https://books.google.com/books/about/La_m%C3%A1quina_est%C3%A9tica.html?id=MbVPAAAAMAAJ), the book he and Mayer Sasson published on it (UNAM, 1983)
- ["La máquina estética de Manuel Felguérez"](https://casadeltiempo.uam.mx/index.php/36-ct-vi-21/681-ct-vi-21-la-maquina-estetica-de-manuel-felguerez-louise-noelle-gras), an account of the project by Louise Noelle Gras

### Recreations here

- [**EspacioMultiple**](EspacioMultiple/): one form-idea in its three states. A square with rounded corners (the circle and the square at once), a rectangle, a disk, a half disk and a right triangle are the whole vocabulary, and the form-idea is a large rounded square with a displaced twin under it, a band that crosses it and ends in a half disk, a disk, and triangles cut into the corners. The sketch paints it flat in a silver or a gold scheme, raises the planes into a relief under a light that rakes across the wall, takes the relief apart into a standing piece (the sheet becomes the floor, the band a shelf through the square, the displacement depth) and folds it back, with a new combination each cycle. `stage` holds one state still, `unlit` shows that the relief seen straight on is the painting again, and the painting exports as a plan. An original Ollin interpretation, written from the work and from his own account of the method.

  ```sh
  swift run Example-Recreations-ManuelFelguerez-EspacioMultiple
  swift run Example-Recreations-ManuelFelguerez-EspacioMultiple --param stage=painting --export-svg plan.svg
  ```

- [**MáquinaEstética**](MaquinaEstetica/): a machine that composes in an alphabet of eight elements. It weighs the ink it has laid down, and it throws the sheet away when the weight sits too far off center. This is an original Ollin interpretation, written from the work and from published accounts of how the machine was made. The seed is the design, a parameter sets how much imbalance may pass, and a pen-only mode shows the drawing before the paint.

  ```sh
  swift run Example-Recreations-ManuelFelguerez-MaquinaEstetica
  ```

  A day of the plotter's output, as one sheet:

  ```sh
  swift run Example-Recreations-ManuelFelguerez-MaquinaEstetica --export-grid sheet.png --seeds 36
  ```

- [**RelieveLacado**](RelieveLacado/): a design the machine accepted, raised into a lacquered relief. It composes and weighs exactly as `MaquinaEstetica` does, so the same seed is the same design in both, then cuts every element out as a slab, the largest on the board and each smaller one a step higher, all under lacquer, with the element the pen had left as an outline as the one plate of bare aluminum. A key light rakes across the board and circles slowly, and the shadows the layers throw turn with it. `view` walks round it, looks at it straight on from the gallery floor, or shows the plan the machine handed over; `unlit` shows that the wall seen straight on is the plan again.

  ```sh
  swift run Example-Recreations-ManuelFelguerez-RelieveLacado
  swift run Example-Recreations-ManuelFelguerez-RelieveLacado --param view=drawing --param showRule=true --export-svg plan.svg
  ```

This is a homage after Manuel Felguérez, made for learning. It is not a reproduction of a specific work, and it is not affiliated with or endorsed by the artist or his estate.

#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Manuel Felguérez</sup>

---

## Manuel Felguérez

**Manuel Felguérez** (1928-2020) was a Mexican painter and sculptor, born in Valparaíso, Zacatecas, and one of the leading figures of the *Generación de la Ruptura*, the generation that broke with muralism in the middle of the century. He worked in hard-edge geometric abstraction, in sober tones, on canvas and in metal, and in 1998 he opened the country's first museum of abstract art in his home state.

**"La máquina estética" (1975-1977)** is the reason he belongs in this set. Felguérez held that the information in a picture sits in the balance between its forms, not in the forms themselves, and he had tested that on his own work: he cut the shapes out of his paintings and weighed the pieces. With a Guggenheim Fellowship he went to Harvard, and with the systems engineer Mayer Sasson he turned that theory into a program. It carried an alphabet of eight geometric elements, and the compositional rules his own paintings kept to. The design lay in a field of six by eight units. Each of the four invisible edges of that field had to be touched by at least one element. A random term made every design different, and the balance decided which ones could stand. A plotter drew one design every eleven seconds, up to two hundred in a day.

The machine made drawings, not pictures. Felguérez kept the ones he wanted and painted them afterward, a step he saw as putting the person back at the center of the work. He is a rare case: a Mexican geometrist who was also a computer artist, and whose way of working was to let a machine propose and a person choose.

Learn more:

- [Manuel Felguérez on Wikipedia](https://en.wikipedia.org/wiki/Manuel_Felgu%C3%A9rez)
- [*Manuel Felguérez: una máquina estética*](https://cultura.uam.mx/manuel-felguerez-una-maquina-estetica/), the exhibition of the project at the UAM
- [*La máquina estética*](https://books.google.com/books/about/La_m%C3%A1quina_est%C3%A9tica.html?id=MbVPAAAAMAAJ), the book he and Mayer Sasson published on it (UNAM, 1983)
- ["La máquina estética de Manuel Felguérez"](https://casadeltiempo.uam.mx/index.php/36-ct-vi-21/681-ct-vi-21-la-maquina-estetica-de-manuel-felguerez-louise-noelle-gras), an account of the project by Louise Noelle Gras

### Recreations here

- [**MáquinaEstética**](MaquinaEstetica/): a machine that composes in an alphabet of eight elements, weighs the ink it has laid down, and throws the sheet away when the weight sits too far off center. An original Ollin interpretation written from the work and from published accounts of how the machine was made, with the seed as the design, a parameter for how much imbalance may pass, and a pen-only mode that shows the drawing before the paint.

  ```sh
  swift run Example-Recreations-ManuelFelguerez-MaquinaEstetica
  ```

  A day of the plotter's output, as one sheet:

  ```sh
  swift run Example-Recreations-ManuelFelguerez-MaquinaEstetica --export-grid sheet.png --seeds 36
  ```

This is a homage after Manuel Felguérez, made for learning. It is not a reproduction of a specific work, and it is not affiliated with or endorsed by the artist or his estate.

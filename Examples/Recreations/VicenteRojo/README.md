#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Vicente Rojo</sup>

---

## Vicente Rojo

| [![MexicoBajoLaLluvia](https://media.ollin.art/examples/Recreations/VicenteRojo/MexicoBajoLaLluvia/still-640.jpg?v=f1be86b3)](MexicoBajoLaLluvia/) | [![Negaciones](https://media.ollin.art/examples/Recreations/VicenteRojo/Negaciones/still-640.jpg?v=49392fc3)](Negaciones/) |  |  |
|---|---|---|---|
| [MexicoBajoLaLluvia](MexicoBajoLaLluvia/) | [Negaciones](Negaciones/) |  |  |

**Vicente Rojo** (1932, Barcelona; 2021, Mexico City) was a painter, sculptor, and graphic designer, and one of the artists who gave Mexican art its abstract turn. His father, an engineer on the Republican side of the Spanish Civil War, fled to France and then to Mexico, and Vicente followed in 1949, at seventeen and without a passport. He learned typography and design under Miguel Prieto, another exile, at the Instituto Nacional de Bellas Artes, and for the rest of his life he kept two practices going at once. As a designer he ran the art of Ediciones Era, the publishing house he co-founded in 1960, designed some seven hundred of its covers, drew the first-edition cover of *Cien años de soledad* (1967), and laid out the magazines *Artes de México*, *Plural*, and the newspaper *La Jornada*. As a painter he was part of the *Generación de la Ruptura*, the generation that broke with muralism, and worked in geometric abstraction for sixty years. Mexico gave him its National Prize for Arts and Sciences in 1991, and he joined El Colegio Nacional in 1994.

He painted in series, each one a single structure turned over and over. The letter T entered his work in 1964 and became the whole of it. *Señales* (1966-1972) set the T among signs and signals on rough grounds. *Negaciones* (1971-1974) put it alone on a strictly square canvas, painted not as a letter but as the shadow a T-shaped block would cast, stepped in a few flat tones with a forty-five degree cut wherever a side ends, the face of the block left the color of the ground. Rojo named the series for what he wanted: paintings that would deny each other, and deny him as their author. He thought of showing them as the work of forty invented painters. What stayed with him was the method, "starting from a very rigid structure, within a strictly square form, which paradoxically allowed me to work with great freedom."

The other series here took him thirty years. In 1953 he watched two rains fall at once over the valley of Cholula, from the observatory at Tonantzintla, and could not paint it. "It always seemed to me an impossible subject to paint, and that is what drew me to it." *México bajo la lluvia* (1981-1989) is the answer: a square canvas, a diagonal across it so the two triangles lean the way the rain had leaned, and over the whole surface closely spaced diagonal lines, made of dots, triangles, half-disks, steps, and blotches, in a cool palette with warm notes, no part of the canvas left empty. He painted well over a hundred of them.

He belongs in this set because his series are what a sketch does: one structure, fixed, and every canvas a different reading of it. A T that is only its shadow, and rain that is only a grid of small marks, are rules a program can carry out.

Learn more:

- [Vicente Rojo on Wikipedia](https://es.wikipedia.org/wiki/Vicente_Rojo_Almaz%C3%A1n) (in Spanish; the [English page](https://en.wikipedia.org/wiki/Vicente_Rojo_Almaz%C3%A1n) is short)
- [*Negación 13* at the Museo Reina Sofía](https://www.museoreinasofia.es/colecciones/obra/negacion-13/), a painting from the series, and [*Negación 23* at Galería Freijo](https://virtual.galeriafreijo.com/vicente-rojo-obras-hist%C3%B3ricas-programa-lz46/negaci%C3%B3n-23), with his account of why the series has its name
- [*México bajo la lluvia 106* at the MUAC](https://muac.unam.mx/objeto/mexico-bajo-la-lluvia-106) and [*México bajo la lluvia 115* at the SURA collection](https://www.sura.com/arteycultura/obra/mexico-bajo-la-lluvia-115/), two paintings from the series with their descriptions
- ["Legendary Signs: Remembering Vicente Rojo's Impact on Modern Mexico"](https://www.denverartmuseum.org/en/blog/legendary-signs-remembering-vicente-rojos-impact-modern-mexico), the Denver Art Museum on the T and the *Señales*
- [Vicente Rojo at the MUAC](https://muac.unam.mx/exposicion/vicente-rojo?lang=en), the 2015 retrospective *Escrito/Pintado* of the painter and the designer together

### Recreations here

- [**Negaciones**](Negaciones/): a wall of square panels, each one the letter T painted only as the shadow it casts. A T-shaped block stands off the canvas, light comes from one corner, and the sides of the block are painted in stepped tones while its face stays the color of the ground. Every few seconds one panel is painted over with a negation that matches no other on the wall: a different way up, a different corner for the light, different sides left out, different tones. `across` is the panels on a side, `stripes` the tones a shadow steps through, `depth` how far the block stands off the canvas, `pace` the seconds between paintings, and `variation` the whole wall. A press paints the next panel now. An original Ollin interpretation written from the paintings and from what Rojo said about them.

  ```sh
  swift run Example-Recreations-VicenteRojo-Negaciones
  ```

  The wall back as flat polygons, with the letter in the file in the ground's own color:

  ```sh
  swift run Example-Recreations-VicenteRojo-Negaciones --export-svg wall.svg --frame 120
  ```

- [**MexicoBajoLaLluvia**](MexicoBajoLaLluvia/): a square covered by a grid, every cell painted and one small mark set on it, with the rain falling. Above the diagonal from the top left corner the marks are the rain, half-disks and dots. Below it they are the ground, triangles and steps. Blotches land on both. The colors run in broken streaks along the diagonal and slide down it at `drift` cells a second. `cells` is the grid across the square, `wind` how ragged the streaks are, and `variation` the whole canvas. An original Ollin interpretation written from the paintings.

  ```sh
  swift run Example-Recreations-VicenteRojo-MexicoBajoLaLluvia
  ```

  One ground square and one mark for every cell, as vectors:

  ```sh
  swift run Example-Recreations-VicenteRojo-MexicoBajoLaLluvia --export-svg rain.svg --frame 300
  ```

This is a homage after Vicente Rojo, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or his estate.

#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Alma Thomas</sup>

---

## Alma Thomas

| [![Columns](https://media.ollin.art/examples/Recreations/AlmaThomas/Columns/still-640.jpg?v=8af7f837)](Columns/) | [![Rings](https://media.ollin.art/examples/Recreations/AlmaThomas/Rings/still-640.jpg?v=4b78273d)](Rings/) |  |  |
|---|---|---|---|
| [Columns](Columns/) | [Rings](Rings/) |  |  |

**Alma Woodsey Thomas** (1891, Columbus, Georgia; 1978, Washington) found her painting at seventy-four and made it in the twelve years she had left. Her family moved to Washington in 1907, and she stayed. In 1924 she was the first graduate of Howard University's art department, and from that year until 1960 she taught art at Shaw Junior High School, thirty-five years in one school, painting on the side, taking a master's degree from Columbia in 1934 and classes at American University in the 1950s. She retired in 1960 and painted seriously for the first time. When Howard offered her a retrospective in 1966 she looked for something new to show, and found it in the light through the holly tree outside her window and the flower beds along the streets of her neighborhood: the patches of color the eye takes in when it does not settle on one thing.

The mark she arrived at was one stroke of a flat brush, laid down and lifted, then the next one a little way on, the primed canvas left showing between them. She ruled the canvas first, in pencil, into the circles or the columns the strokes would follow, and laid one color down each row. In *Resurrection* (1966) the strokes go around a core in rings, green, blue, violet, red, orange and out into yellow. From 1969 the Apollo flights gave her titles and pictures: *Snoopy Sees Earth Wrapped in Sunset* (1970) fills a disc with columns of red and orange strokes and a seam of yellow, the earth seen from the lunar module, and *The Eclipse* (1970), the last of her Space series, sets a dark core up and to the right of the canvas with the rings running off its edges, after the total solar eclipse she saw over Washington on March 7, 1970. The vertical mosaics followed: *Earth Sermon: Beauty, Love and Peace* (1971), columns of one color after another the height of the canvas; *Red Roses Sonata* (1972), all reds; *Mars Dust* (1972), red strokes on a dark ground; *Starry Night and the Astronauts* (1972), blues with a patch of red, orange and yellow up at one corner. She said the color was the point. "Through color, I have sought to concentrate on beauty and happiness, rather than on man's inhumanity to man." And, of the streaks of color seen from an airplane she had never flown in: "Color is life, and light is the mother of color."

In 1972, at eighty, she was the first Black woman with a solo exhibition at the Whitney Museum of American Art, and the Corcoran Gallery of Art gave her a retrospective the same year. She died in Washington in 1978. In 2014 *Resurrection* entered the White House collection, the first work by an African American woman to do so, and was hung in the Old Family Dining Room in 2015. *Alma W. Thomas: Everything Is Beautiful*, the retrospective organized by the Chrysler Museum of Art and The Columbus Museum, traveled from Norfolk to the Phillips Collection in Washington, the Frist in Nashville, and Columbus, Georgia, in 2021 and 2022.

She belongs in this set because the rule is one mark repeated, and the brush that repeats a mark along a path is what the two sketches here are built on: a ring or a column is one path, the stroke is its stamp, and the ground between the strokes is the spacing.

Learn more:

- [Alma Thomas at the Smithsonian American Art Museum](https://americanart.si.edu/artist/alma-thomas-4778), the largest holding of her work, with [*The Eclipse*](https://americanart.si.edu/artwork/eclipse-24007) and [*Snoopy Sees Earth Wrapped in Sunset*](https://americanart.si.edu/artwork/snoopy-sees-earth-wrapped-sunset-24020), both gifts of the artist
- [*Starry Night and the Astronauts*](https://www.artic.edu/artworks/129884/starry-night-and-the-astronauts) at the Art Institute of Chicago, with the museum's reading of the strokes and the ground between them
- [*Red Roses Sonata*](https://www.metmuseum.org/art/collection/search/632918) at The Metropolitan Museum of Art
- [*Resurrection* at the White House](https://www.whitehousehistory.org/resurrection-by-alma-thomas), from the White House Historical Association
- [*Alma W. Thomas: Everything Is Beautiful*](https://chrysler.org/exhibition/alma-thomas/), the 2021 to 2022 retrospective, at the Chrysler Museum of Art, and [at the Phillips Collection](https://www.phillipscollection.org/event/2021-10-30-exhibition-alma-thomas)
- [Alma Thomas on Wikipedia](https://en.wikipedia.org/wiki/Alma_Thomas)

### Recreations here

- [**Rings**](Rings/): the concentric paintings, after *Resurrection* and *The Eclipse*. A core sits on the canvas, and around it every row of strokes is one circle stroked with a brush whose tip is a block of paint, stamped along the circle at even steps of one length and a gap and turned to follow it, with a thread of ground between one row and the next. The colors go around the spectrum from the core outward, each taking a dealt number of rows, and the last goes on in rings until it fills the corners. The picture is painted stroke by stroke from the core out over two thirds of the cycle, holds, and is taken back the way it came. `look` picks the painting; `dabLength`, `dabWidth`, `gap`, `channel`, `jitter`, `tilt` and `seconds` are the rest of the controls, and the seed deals the core's place, the rows, the tones and the hand. An original Ollin interpretation written from the paintings; there is no code to port, the work is acrylic on canvas.

  ```sh
  swift run Example-Recreations-AlmaThomas-Rings
  ```

  The painting back as the blocks of paint, every stroke its own closed outline centered on its circle:

  ```sh
  swift run Example-Recreations-AlmaThomas-Rings --seed 2 --param look=eclipse --export-svg eclipse.svg --frame 1350
  ```

- [**Columns**](Columns/): the vertical mosaics, after *Snoopy Sees Earth Wrapped in Sunset*, *Earth Sermon*, *Mars Dust* and *Starry Night and the Astronauts*. The canvas is ruled into columns, each one line stroked with the same brush down it, every column starting at its own height so the strokes of neighbors never line up. `sunset` fills a disc, red on one side and orange on the other with a seam of yellow between, on a field of orange; `sermon` runs bands of one color after another the height of the canvas; `marsDust` stands red strokes on a dark ground; `starryNight` fills the canvas with blues and a patch of warm strokes up at one corner. Painted column after column from the left, held, and taken back. The controls are the same as the rings', and the seed deals the bands, their colors and tones, each column's start and the hand. An original Ollin interpretation written from the paintings.

  ```sh
  swift run Example-Recreations-AlmaThomas-Columns
  ```

  The bands as blocks, every stroke centered on its column:

  ```sh
  swift run Example-Recreations-AlmaThomas-Columns --seed 2 --param look=sermon --export-svg sermon.svg --frame 1080
  ```

This is a homage after Alma Thomas, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or her estate.

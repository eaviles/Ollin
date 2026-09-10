#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Josef Albers</sup>

---

## Josef Albers

**Josef Albers** (1888, Bottrop, Germany; 1976, New Haven, Connecticut) taught color for fifty years and painted the same square for the last twenty-six of them. He came to the Bauhaus as a student in 1920, taught its preliminary course from 1923, and left Germany when the school closed in 1933. He taught at Black Mountain College in North Carolina until 1949, then at Yale, where he ran the design department until 1958. His course became the book *Interaction of Color* (1963), whose plates show that no color is seen as it is: what a color looks like depends on the colors beside it. In 1971 the Metropolitan Museum of Art gave him a retrospective, the first it had given a living artist.

He began **Homage to the Square** in 1950, at 62, and made more than a thousand of them before he died. Each one is three or four flat squares of color nested inside one another. The format never changes. On a grid of ten units the squares measure ten, eight, six, and four; each is centered across the panel and set low in it, so the band under an inner square is half the band at its sides and the band above is one and a half times it. He used four arrangements: all four squares, or three of them with one of the inner three left out. He said the downward shift *"gives additional weight, but also enhanced movement"* and that it keeps the picture from settling into a symmetry that would hold it still.

Everything else is color. He painted on the rough side of Masonite, primed white many times over, and laid each color on flat with a palette knife, unmixed, straight from the tube, working from the center square outward. He wrote the paints he had used on the back of every panel. The colors in a set were chosen so the squares would seem to come forward or fall back, glow or dissolve into one another, and a different set gave a different climate, though the squares never moved. He said he was not paying homage to a square; the square was only *"the dish I serve my craziness about color in."*

He belongs in this set because his work is one rule and a thousand answers to it. The format is small enough to state in a sentence and was never varied. What a computer can do with it is roll the answers.

Learn more:

- [Josef Albers on Wikipedia](https://en.wikipedia.org/wiki/Josef_Albers) and [Homage to the Square](https://en.wikipedia.org/wiki/Homage_to_the_Square)
- [The Josef and Anni Albers Foundation](https://albersfoundation.org)
- [*Homage to the Square: "Ascending"*, 1953 (Whitney Museum of American Art)](https://whitney.org/collection/works/4079)
- [James Mai, *Planes and Frames: Spatial Layering in Josef Albers' Homage to the Square Paintings*, Bridges 2016](https://archive.bridgesmathart.org/2016/bridges2016-233.pdf), which states the grid, the sizes, and the four arrangements

### Recreations here

- [**Homage**](Homage/): the format, and a new set of colors on it every few seconds. Each sheet rolls one of five palette rules, each a reading of one thing his sets do: a ramp of one hue stepping inward, a glow of one bright square inside three dark ones, four hues at one lightness so the edges dissolve, grays around one colored square, and warm against cool. The colors are built in OKLCH and crossfaded in OKLab, and `contrast` and `drift` scale the sheet's steps live. An original Ollin interpretation, written from the work and from the published account of its format. The palette rules are the sketch's own; he chose every color by eye.

  ```sh
  swift run Example-Recreations-JosefAlbers-Homage
  ```

  A wall of sheets, one per seed, the way a room of them hangs:

  ```sh
  swift run Example-Recreations-JosefAlbers-Homage --export-grid sheets.png --seeds 36
  ```

This is a homage after Josef Albers, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or the Josef and Anni Albers Foundation.

| [![Homage](https://media.ollin.art/examples/Recreations/JosefAlbers/Homage/still-640.jpg?v=bd118fab)](Homage/) |  |  |  |
|---|---|---|---|
| [Homage](Homage/) |  |  |  |

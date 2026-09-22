#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Nasreen Mohamedi</sup>

---

## Nasreen Mohamedi

| [![Diagonals](https://media.ollin.art/examples/Recreations/NasreenMohamedi/Diagonals/still-640.jpg?v=1f4c559f)](Diagonals/) | [![Registers](https://media.ollin.art/examples/Recreations/NasreenMohamedi/Registers/still-640.jpg?v=869a3c69)](Registers/) |  |  |
|---|---|---|---|
| [Diagonals](Diagonals/) | [Registers](Registers/) |  |  |

**Nasreen Mohamedi** (1937, Karachi; 1990, Kihim) is the artist India's abstraction is measured against. Her family moved to Bombay in 1944, and her father ran a photographic equipment shop in Bahrain, which is where the camera came from. She studied at St Martin's School of Art in London from 1954 to 1957 and at a printmaking atelier in Paris from 1961 to 1963, then came home to a Bombay where V. S. Gaitonde and Tyeb Mehta were the painters she looked to. In 1972 she settled in Baroda and taught at the Faculty of Fine Arts of the Maharaja Sayajirao University until she died. She traveled, to Kuwait, Turkey, Iran and Japan, and kept diaries, mostly in English, and photographed what she saw: the desert, the sea, weaving, the courtyards of Fatehpur Sikri and the concrete of Chandigarh, each picture pared to light and dark.

Her drawings are small, and they are made with the tools of an architect's office: a ruling pen and a fine technical pen for the ink, the ink often watered down to a grey, a hard pencil for the graphite, a drafting table she sat cross-legged in front of on a low stool. Through the 1970s the sheets are square, seven and a half inches or eighteen and three quarters, and ruled from edge to edge with horizontals. What changes across a sheet is the interval between the lines and their weight. The lines gather toward one line, drawn heavy, and open away from it, so a field of parallels reads as planes seen edge on. Some sheets double the horizontals in one quadrant, some send verticals up through them, some let diagonals cross. Faint pencil verticals rule the whole sheet underneath. Late in the decade the grid loosened, and the drawings of her last ten years are wide sheets left mostly empty, with one figure floating: a chevron drawn heavy in ink, a wake of hairlines laid off one of its arms, a fan of lines leaning toward a point past the edge of the paper. Huntington's disease was taking her hands through that decade. The drawings only got more exact. She wrote in her diary of getting "the maximum of the minimum".

Every work is untitled. She showed little in her lifetime, and the recognition came after: the Drawing Center in New York in 2005, documenta 12 in 2007 beside Agnes Martin, the Kiran Nadar Museum of Art in 2013, Tate Liverpool in 2014, the Reina Sofía in 2015, and in 2016 the Met Breuer opened with her retrospective, the first in the United States.

She belongs in this set because her sheets are what a plotter wants to draw. A line, an interval, a weight, and a rule for how they change: the whole of a drawing is in three numbers and a progression, and the two sketches here keep it that way and export as the lines they are.

Learn more:

- [Nasreen Mohamedi on Wikipedia](https://en.wikipedia.org/wiki/Nasreen_Mohamedi)
- [Nasreen Mohamedi at Talwar Gallery](https://www.talwargallery.com/artists/nasreen-mohamedi), the gallery that has shown her since 2003, with the drawings and photographs this folder was read from
- [*Nasreen Mohamedi*](https://www.metmuseum.org/exhibitions/listings/2016/nasreen-mohamedi), the 2016 retrospective at the Met Breuer, and [*Of Calligraphic Lines and Radiant Light*](https://metmuseum.org/articles/nasreen-mohamedi), the museum's essay on her sources
- [*Nasreen Mohamedi: Waiting Is a Part of Intense Living*](https://www.museoreinasofia.es/en/exhibitions/nasreen-mohamedi), the Reina Sofía's 2015 exhibition
- [*Nasreen Mohamedi*](https://www.tate.org.uk/whats-on/tate-liverpool/nasreen-mohamedi) at Tate Liverpool, 2014
- [Nasreen Mohamedi at the Met Breuer](https://brooklynrail.org/2016/05/artseen/nasreen-mohamedi/), a review in the Brooklyn Rail that reads the 1970s sheets closely

### Recreations here

- [**Registers**](Registers/): the ruled sheets of the 1970s. The field is cut into registers by heavy lines, and each register holds a run of fine lines whose intervals are a geometric progression, so the lines gather against one heavy line and open toward the other; the weight of a line follows its interval. In the upper half every line is doubled on the right, a few verticals rise from the bottom edge in graphite, and pencil guides stand under everything. The sheet breathes: over one cycle each register's ratio drifts about the value it was dealt, so the lines tighten and relax while the heavy lines hold still. `registers`, `breathing`, `seconds`, `doubled`, `risers` and `guides` are the controls, and the seed is the sheet. An original Ollin interpretation written from the drawings; there is no code to port, the work is a ruling pen on paper.

  ```sh
  swift run Example-Recreations-NasreenMohamedi-Registers
  ```

  The sheet back as lines for a pen, every horizontal at one angle and every interval in its progression:

  ```sh
  swift run Example-Recreations-NasreenMohamedi-Registers --seed 3 --export-svg sheet.svg
  ```

- [**Diagonals**](Diagonals/): the floating figures of about 1980. One axis crosses a wide sheet at a slant, and along it stand one to four chevrons, nested or strung out, each one stroke whose width is full at the corner and thins to the tip of each arm. A chevron may carry a wake, hairlines parallel to its long arm laid along the short one at intervals that grow by a ratio, and a fan, hairlines from stations along the short arm toward one point well off the sheet. Over one cycle the figure slides a little along its axis and back, the fans sweep and the wakes breathe. `chevrons`, `drift`, `seconds`, `wakes` and `fans` are the controls, and the seed is the sheet. An original Ollin interpretation written from the drawings.

  ```sh
  swift run Example-Recreations-NasreenMohamedi-Diagonals
  ```

  The figure back for a pen, every hairline a line and each chevron the outline of the region its stroke covers, so the thinning survives on paper:

  ```sh
  swift run Example-Recreations-NasreenMohamedi-Diagonals --seed 5 --export-svg figure.svg
  ```

This is a homage after Nasreen Mohamedi, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or her estate.

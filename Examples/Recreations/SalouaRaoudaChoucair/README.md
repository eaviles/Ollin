#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Saloua Raouda Choucair</sup>

---

## Saloua Raouda Choucair

| [![Duals](https://media.ollin.art/examples/Recreations/SalouaRaoudaChoucair/Duals/still-640.jpg?v=8e53c25f)](Duals/) | [![Poem](https://media.ollin.art/examples/Recreations/SalouaRaoudaChoucair/Poem/still-640.jpg?v=350555ec)](Poem/) |  |  |
|---|---|---|---|
| [Duals](Duals/) | [Poem](Poem/) |  |  |

**Saloua Raouda Choucair** (1916, Beirut; 2017, Beirut) was a Lebanese painter and sculptor, and one of the first artists in the Arab world to work in a wholly abstract, geometric language. She studied natural sciences at the American Junior College for Women in Beirut, graduating in 1938. She learned painting from Omar Onsi and Moustafa Farroukh. A visit to Cairo in 1943, to its mosques and streets, turned her to Islamic art and its geometry. From 1948 to 1951 she lived in Paris. She studied at the École Nationale des Beaux-Arts and spent three months in Fernand Léger's studio. She showed at the Salon des Réalités Nouvelles in 1950 and had her first Paris exhibition at the Galerie Colette Allendy in 1951. Then she went home to Beirut. Science, mathematics, Islamic art and Arabic poetry fed her work for the rest of her long life. She taught sculpture at the Lebanese University from 1977 to 1984.

From the end of the 1950s she worked mostly in sculpture: wood, stone, terracotta, fiberglass, brass and aluminum. The sculptures are made of parts. The **Poems** (*qasa'id*) are units stacked one on another, each shaped to fit the one below it, each able to stand alone. In the classical Arabic ode each verse is complete in itself, and the poem is their sequence. Tate's *Poem* (1963-65) is five wooden units with windows cut through them. The six tufa verses of the Centre Pompidou's *Poem* (1963-65) stand 125 centimeters tall. *Poem of Nine Verses* (1966-68) is nine slabs of aluminum keyed together, the joints stepping and notching across them. *Infinite Structure* (1963-65) is a tower of hollowed tufa blocks, a pattern that could go on growing. From 1975 she made the **Duals** (*thana'ia*), sculptures in two parts. The parts close on each other so exactly that the join is a line, and they can also be set side by side as two. In the *Repetitive Dual* series, conceived in 1988 to 1990, a cut steps from side to side down the height of a block, so the halves interlock tooth by tooth.

She thought of much of this work as never finished: structures for the viewer, the weather or the artist to change by adding and taking away. In 1974 the Lebanese Artists Association held a retrospective of her work in Beirut. The first major museum exhibition of her work anywhere was Tate Modern's, from April to October 2013, with more than 120 works from six decades. Her daughter Hala Schoukair leads the Saloua Raouda Choucair Foundation. Its museum opened in Ras El Metn on June 24, 2024, which would have been her 108th birthday.

She belongs in this set because her rule is a cut. A line crosses a block once, and the parts are what lies on either side, so the parts make the block again and share only the line. Two shape operations and a grid can state that exactly, and a lit solid can show it.

Learn more:

- [*Saloua Raouda Choucair*](https://www.tate.org.uk/whats-on/tate-modern/exhibition/saloua-raouda-choucair), the 2013 retrospective at Tate Modern, and [the exhibition's press release](https://www.tate.org.uk/press/press-releases/saloua-raouda-choucair)
- At Tate: [*Poem*](https://www.tate.org.uk/art/artworks/choucair-poem-t13278), [*Poem Wall*](https://www.tate.org.uk/art/artworks/choucair-poem-wall-t13279), [*Poem of Nine Verses*](https://www.tate.org.uk/art/artworks/choucair-poem-of-nine-verses-t13647) and [*Infinite Structure*](https://www.tate.org.uk/art/artworks/choucair-infinite-structure-t13262)
- [*Poem*](https://www.centrepompidou.fr/en/ressources/oeuvre/cEpdeG), the six stone verses at the Centre Pompidou
- [*Dual*](https://scma.smith.edu/blog/new-acquisition-saloua-raouda-choucair) (1975-77), fiberglass over clay, at the Smith College Museum of Art, with its note on the series
- [Saloua Raouda Choucair at the Lebanese American University](https://100.lau.edu.lb/alumni/saloua-raouda-choucair.php), her college, with the dates of her studies and teaching
- [Saloua Raouda Choucair on Wikipedia](https://en.wikipedia.org/wiki/Saloua_Raouda_Choucair)

### Recreations here

- [**Poem**](Poem/): a block cut into verses by a rule, lifted apart and set back, lit in the round. The block is ruled into a grid of cells, and each cut runs across it with every corner on a grid point. A cut is level but for keys one row up or down, square or slanted at their sides, and a key that reaches the edge is a step. Each verse is the block between two cuts, so the verses fill the block exactly. Some verses have windows cut through them, kept a cell clear of every edge. The verses rise apart, each clearing the one below by more than any key is deep. Then they turn about their own uprights and slide, hold while the light moves over them, and are set back into the block. `look` picks `wood` (five verses with windows, after Tate's *Poem*), `stone` (six tall tufa verses, after the Pompidou's *Poem* and *Infinite Structure*) or `aluminum` (nine thin slabs keyed together, after *Poem of Nine Verses*). `rise`, `turn`, `seam` and `seconds` are the rest of the controls, and the seed deals the keys, the windows and each cycle's reading. An original Ollin interpretation written from the sculptures; there is no code to port.

  ```sh
  swift run Example-Recreations-SalouaRaoudaChoucair-Poem
  ```

  The verses as separate solids at rest, fitted exactly with no seam between them:

  ```sh
  swift run Example-Recreations-SalouaRaoudaChoucair-Poem --param seam=0 --export-usdz poem.usdz --frame 0
  ```

- [**Duals**](Duals/): a block cut once into two parts that slide apart and lock. The cut runs from edge to edge with every corner on a grid point. It crosses every line running one way exactly once, which is what lets the parts come apart at all. The two parts are the block cut by the region past the line and the block minus it. They slide apart until a straight line separates them, lean away about their outer corners, hold, and close again. `look` picks `comb` (the stepped teeth of the *Repetitive Dual*, in aluminum), `key` (a softened slab of wood cut along its length with keys in the joint) or `stair` (a square of painted wood cut by a staircase). `view` shows it lit in the round or flat as a plan. An original Ollin interpretation written from the sculptures.

  ```sh
  swift run Example-Recreations-SalouaRaoudaChoucair-Duals
  ```

  The plan with the grid over it, the two outlines meeting along the cut:

  ```sh
  swift run Example-Recreations-SalouaRaoudaChoucair-Duals --param view=plan --param showGrid=true --export-svg dual.svg --frame 0
  ```

This is a homage after Saloua Raouda Choucair, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or her estate.

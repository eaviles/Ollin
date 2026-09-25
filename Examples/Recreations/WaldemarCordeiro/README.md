#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Waldemar Cordeiro</sup>

---

## Waldemar Cordeiro

| [![Derivadas](https://media.ollin.art/examples/Recreations/WaldemarCordeiro/Derivadas/still-640.jpg?v=f5a0cbe2)](Derivadas/) | [![Gente](https://media.ollin.art/examples/Recreations/WaldemarCordeiro/Gente/still-640.jpg?v=c720d5ae)](Gente/) |  |  |
|---|---|---|---|
| [Derivadas](Derivadas/) | [Gente](Gente/) |  |  |

**Waldemar Cordeiro** (1925, Rome; 1973, São Paulo) made the first computer art in Brazil, and came to it from the front of a movement that had already treated art as a matter of numbers. He was born in Rome to a Brazilian father and an Italian mother, studied at the Accademia di Belle Arti there, and settled in São Paulo in 1948. In 1952 he handed out the manifesto of the Ruptura group at its first exhibition: art was to be made from its own elements, ordered by rule, and not copied from nature. That was Brazilian Concrete art, and he was its theorist and its polemicist. From 1950 until his death he also worked as a landscape architect, on more than 150 gardens, parks and plans.

In the 1960s he let the world back in. The Popcretos of 1964 joined the order of Concrete painting to things taken from everyday life. In 1968 the physicist and critic Mário Schenberg introduced him to Giorgio Moscati, a physicist at the University of São Paulo, and Cordeiro told him at once what he wanted: to use the computer to make art. They began by trading books and papers and visiting laboratories, and only then wrote a program. The first was *Beabá*, a generator of six-letter words that sound like Portuguese. The second was *Derivadas de uma imagem* (1969). Cordeiro insisted, Moscati remembered, on a picture with strong human content for "a cold, calculating machine" to transform. He chose a Valentine's Day poster of a young couple and read it by hand into 10,976 numbers from 0 to 6. Moscati asked which transformation a scientist uses most and answered himself: the derivative. The IBM 360/44 of the Physics Department printed the picture as characters on its line printer, then its derivative, then the derivative of that, and the third. The critic Jonathan Benthall saw the sheets in 1970 and wrote that they seemed interested in the line between legibility and illegibility.

He called the field *arteônica*, electronic art, and in 1971 organized an international exhibition of it at the Fundação Armando Alvares Penteado in São Paulo. He argued that electronic means could carry art to a country of vast distances before the roads did. At the Universidade Estadual de Campinas he set up a center for processing images, and there, with Raul Fernando Dada and J. Soares Sobrinho, he made *Gente* (1972-1973), a crowd in the Praça da Sé printed on continuous-form paper at several degrees of contrast. *A mulher que não é B.B.* (1971) set a photograph of a Vietnamese girl, a victim of the war, against the name of Brigitte Bardot, whose visit had been a sensation in Brazil, and printed it with the machine choosing a share of the points at random. He died in São Paulo in June 1973, at 48. His daughter Analivia Cordeiro carried the work on: her *M3x3* of 1973 is one of the first dances choreographed with a computer.

He belongs in this set because his two procedures are exact and still open. A picture read into a grid of levels, a difference taken between neighbors, a multiplier held at the darkest level: each is a line or two of arithmetic, and each turns a photograph into something between a picture and a text.

Learn more:

- [Waldemar Cordeiro on Wikipedia](https://en.wikipedia.org/wiki/Waldemar_Cordeiro)
- [*A Arteônica de Waldemar Cordeiro*](https://www.visgraf.impa.br/Gallery/waldemar/), the online edition of the 1993 exhibition in Recife, with the sheets of *Derivadas*, *Gente*, *Retrato de Fabiana* and *Pirambu*, and Cordeiro's own texts
- [Giorgio Moscati's account of *Derivadas de uma imagem*](https://www.visgraf.impa.br/Gallery/waldemar/moscati/derivad_.htm), the grid, the seven levels, the overprinted lines, and the derivative, from the man who wrote the program (in Portuguese)
- [*Derivadas de uma Imagem: Transformação em Grau 1*](https://collections.vam.ac.uk/item/O1426285/derivadas-de-uma-imagem-transformacao-print-waldemar-cordeiro/) at the V&A
- [Waldemar Cordeiro's pioneering computer art at Luciana Brito Galeria](https://www.newcitybrazil.com/2025/11/28/waldemar-cordeiros-pioneering-computer-art-at-luciana-brito-galeria/), Newcity Brazil on the 2025 exhibition, with *Gente Grau 2* reproduced
- [Pioneers of Brazilian computer art](https://www.acervosdigitais.fau.usp.br/pioneiros-na-arte-computacional-brasileira/), FAU-USP's page on Waldemar and Analivia Cordeiro (in Portuguese)

### Recreations here

- [**Derivadas**](Derivadas/): after *Derivadas de uma imagem* (1969, with Giorgio Moscati). A bundled photograph is cut into 98 by 112 blocks, each block's mean tone becomes a level from 0 to 6, and the levels are printed as characters whose ink rises with the level, the darkest struck two and three times on one place. The derivative is taken point by point, the larger of the differences from the left and from above, and taken again: four sheets, degree zero to three, printed a line at a time and fed out of the printer one after another. The cells keep the printer's proportion, so the picture stretches as theirs did. `picture`, `sheets`, `linesPerSecond` and `hold` are the controls. An original Ollin interpretation written from the sheets and from Moscati's description; the 1969 program is known here only through that description.

  ```sh
  swift run Example-Recreations-WaldemarCordeiro-Derivadas
  ```

  One sheet back as the glyphs the printer struck, one outline per strike:

  ```sh
  swift run Example-Recreations-WaldemarCordeiro-Derivadas --param sheets=one --frame 420 --export-svg grau-um.svg
  ```

- [**Gente**](Gente/): after *Gente* (1972-1973). A crowd before a wrestler at an arena in Querétaro, read into 100 by 160 levels and printed four times on continuous-form paper, sprocket holes down the edges and a colophon typed under it, at degrees of contrast 1, 2, 4 and 6: every level multiplied by the degree and held at the darkest, so the lightest points stay white and the rest sinks into struck black. The view steps in toward one place until the characters read, and back out until the picture does, one sheet at a time. `picture`, `seconds`, `closest`, `focusX` and `focusY` are the controls. An original Ollin interpretation written from the sheets.

  ```sh
  swift run Example-Recreations-WaldemarCordeiro-Gente
  ```

  The four sheets back as outlines, taken while the view is out:

  ```sh
  swift run Example-Recreations-WaldemarCordeiro-Gente --frame 30 --export-svg gente.svg
  ```

Neither sketch uses the photographs Cordeiro used. They read the bundled sample photographs instead, and the credit for each is in [`OllinSamplePhotos`](../../../Docs/Drawing/SamplePhotos.md).

This is a homage after Waldemar Cordeiro, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist's estate or by Giorgio Moscati.

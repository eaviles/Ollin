#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Ryszard Winiarski</sup>

---

## Ryszard Winiarski

| [![LosowanieDwiemaKostkami](https://media.ollin.art/examples/Recreations/RyszardWiniarski/LosowanieDwiemaKostkami/still-640.jpg?v=3ec0655a)](LosowanieDwiemaKostkami/) | [![Obszar](https://media.ollin.art/examples/Recreations/RyszardWiniarski/Obszar/still-640.jpg?v=c16d4630)](Obszar/) |  |  |
|---|---|---|---|
| [LosowanieDwiemaKostkami](LosowanieDwiemaKostkami/) | [Obszar](Obszar/) |  |  |

**Ryszard Winiarski** (1936, Lwów; 2006, Warsaw) was an engineer before he was a painter. He took a degree in precision mechanics at the Warsaw University of Technology in 1959. He then studied painting at the Academy of Fine Arts in Warsaw under Aleksander Kobzdej, from 1958 to his diploma in 1966, and worked through those years as the technical director of a gasket factory. A seminar on the relations between art and science, given at the Academy by Mieczysław Porębski in 1965, settled his direction. That year he wrote out a program he would keep to for the rest of his life. The first works made under it belong to a series he called *Próby wizualnej prezentacji rozkładów statystycznych*, attempts at the visual representation of statistical distributions. His 1966 diploma, *Zdarzenie, informacja, obraz* (Event, Information, Image), set out the theory behind them. The same year the series took the main prize at the Symposium of Artists and Scientists in Puławy, the meeting where Polish art of the sixties tried to join hands with science and industry. He designed for the stage from 1967 to 1977 and taught at the Academy from 1981. He was its vice-rector from 1985 to 1990, and received the Jan Cybis Prize in 1995.

The program is simple to state, and he never abandoned it. A work is a square ruled into a grid of small squares. Each square is black or white, the two colors standing for the 0 and 1 of probability, and which one a square gets is not his decision. He set the rules first and then, in his words, "invited chance to take part in carrying it out". The source might be a coin, a die, a roulette wheel, a table of random numbers, or a programmed computer. The critic Bożena Kowalska described one such program. It offered two sizes of square for the canvas to be ruled into, and a coin chose between them. The corner from which the filling would start was drawn the same way. Then, field after field, a coin toss decided whether a square turned black or stayed white. He refused to call the results paintings. They were *obszary*, areas. He numbered them, wrote the rule on the back of the canvas or hung it on a board beside the work, and put the random variable in the title: *Obszar 135. Penetration of illusory space with a vanishing point at the center of the area. Random variable: a die* (1973). He wanted the viewer to see the record of a process rather than a composition to have feelings about. He said later that he had raised chance so high "because I wanted to respect the rules of life."

The rule held while the areas grew more complex. From 1968 a third color and a third dimension entered them. The *Penetrations* pushed the grid into relief, with blocks standing off the board and, from 1971, mirrors set into it. In 1972 he turned a room of the Galeria Współczesna in Warsaw into a game parlour, and the visitors threw the dice for the works on the walls. From 1976 that idea became the *Games*, where the program is at its plainest. *Od 0 do 100% czerni* (From 0 to 100% of Black, 1975) runs the probability of black from nothing to everything across twenty-six panels. The *Przejście* (Transition) triptych of 1975 moves it down a single canvas. *Sto zdarzeń* (A Hundred Incidents, 1977) drops a hundred squares where the throws say. *Losowanie dwiema kostkami* (Drawing Lots with Two Dice, 1977) lays black and white runs along the rows, each as long as the sum of two dice, with the first throws written under the field in his hand. In the eighties he let emotion back in, as he put it in 1985, with cut and reassembled geometry. From 1987 came installations of burning candles under the title *Geometria czyli szansa medytacji* (Geometry, or a Chance for Meditation).

He belongs in this set because a program plus a random variable is what a sketch is. His rule on a board beside the work is a doc comment, and his numbered areas are seeds. He insisted that the record of the process was the work, not the picture, and that is the framework's own habit of exporting a frame as the calls that made it.

Learn more:

- [Ryszard Winiarski on Wikipedia](https://en.wikipedia.org/wiki/Ryszard_Winiarski) (the [Polish page](https://pl.wikipedia.org/wiki/Ryszard_Winiarski) has the dates)
- [Ryszard Winiarski at Culture.pl](https://culture.pl/en/artist/ryszard-winiarski), a biography with Kowalska's account of the program
- [The Zachęta collection](https://zacheta.art.pl/pl/kolekcja/artysci/ryszard-winiarski) (in Polish), with *Losowanie dwiema kostkami*, *Od 0 do 100% czerni*, the *Przejście* triptych, the *Sto zdarzeń* series, and [*Obszar 144*](https://zacheta.art.pl/en/kolekcja/katalog/winiarski-ryszard-obszar-144-2), the relief
- [*Przejście VI* at the Starak Family Foundation](https://starakfoundation.org/en/kolekcja/transition_vi_attempts_of_visual_presentation_of_statistical_lay_outs_mutable_lot_dice_1975), one of the areas whose title carries its random variable
- [Ryszard Winiarski at the Museum of Modern Art in Warsaw](https://transatlantic.artmuseum.pl/en/artist/ryszard-winiarski), on *A Hundred Incidents* and the rules he wrote on the back of the canvas
- ["Ryszard Winiarski: Infinite Creative Possibilities"](https://contemporarylynx.co.uk/ryszard-winiarski-infinite-creative-possibilities), Contemporary Lynx on the 2017 Venice showing, with his own words about the rules of the game
- [Ryszard Winiarski on Monoskop](https://monoskop.org/Ryszard_Winiarski), a bibliography

### Recreations here

- [**Obszar**](Obszar/): the program behind the areas, with the throwing left to the machine. A square is ruled into a grid, and a coin picks which of two grids. Two more throws pick the corner. Then every field is painted in turn from that corner, black or white as the random variable says, at `pace` fields a second. The rule is written under the area, with the count of black so far against what the distribution promised. `variable` is the source of chance: a coin, black on heads; a die, black on the faces up to `blackFaces`; or the transition, where the share of black rises from nothing at the first field to everything at the last. A finished area holds for `hold` seconds, and the next one begins under the same rule with new throws, numbered on from `firstArea`. A press starts the next area now. An original Ollin interpretation written from the works and from what Winiarski and Kowalska wrote about how they were made.

  ```sh
  swift run Example-Recreations-RyszardWiniarski-Obszar
  ```

  One finished area back as squares, one per black field, so counting them is counting the throws:

  ```sh
  swift run Example-Recreations-RyszardWiniarski-Obszar --export-svg area.svg --frame 700
  ```

- [**LosowanieDwiemaKostkami**](LosowanieDwiemaKostkami/): drawing lots with two dice. Along the rows of a fine grid inside a black frame, black runs and white runs take turns, and each is as long as the sum of two dice. The dice are thrown at `pace` throws a second from the top left, and a run that reaches the right edge carries on at the left of the next row. The two dice under the field show the throw being laid. The caption under it grows throw by throw until the line is full, the way he wrote the first throws under the painting. A finished sheet holds for `hold` seconds, and the next begins with new throws. `cells` is the grid across the field and `firstSheet` the number of the first sheet. A press starts the next sheet now. An original Ollin interpretation written from the painting.

  ```sh
  swift run Example-Recreations-RyszardWiniarski-LosowanieDwiemaKostkami
  ```

  One finished sheet back as squares, so reading the runs off the file gives the throws back:

  ```sh
  swift run Example-Recreations-RyszardWiniarski-LosowanieDwiemaKostkami --export-svg sheet.svg --frame 1000
  ```

This is a homage after Ryszard Winiarski, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist or his estate.

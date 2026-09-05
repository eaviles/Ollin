#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `De Bruijn sequences`</sup>

---

## De Bruijn sequences

**`deBruijnSequence`** builds a cyclic run of symbols. Every possible window of a given length appears in that run, and each window appears exactly once.

```swift
deBruijnSequence(symbols: 2, window: 3)   // 0,0,0,1,0,1,1,1
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/06-GridsAndRepetition/EveryWindowOnce-dark.jpg">
  <img src="../../Guide/Images/06-GridsAndRepetition/EveryWindowOnce.jpg" alt="On the left an eight-bead strip of two colors with the eight windows of three it holds listed underneath, all different. On the right a ring of sixty-four beads in four tones with one window of three picked out and labeled bead 11" width="680">
</picture>

That run is as short as it can be. There are `symbols` to the power of `window` possible windows. Each one needs its own position in the run, so the run is exactly that long.

**The useful property is local uniqueness.** Any few symbols in a row identify their own position in the run. A rotary encoder uses that property to find its angle, and a camera reads it off a printed ruler. The same property keeps a strip of tiles from repeating itself close up. You get that reading from [`DeBruijnCode`](#code), which builds its table once, so each lookup is cheap.

### Contents

- [deBruijnSequence](#sequence)
- [DeBruijnCode](#code)
- [lyndonWords](#lyndon)
- [Practical notes](#notes)

<a name="sequence"></a>

#### deBruijnSequence

```swift
deBruijnSequence(symbols: Int, window: Int) -> [Int]
```

The result is the run, as symbols numbered from zero. The run is cyclic, so the last window wraps around to the front. To read it, take each index modulo its length.

The run that comes back is the **smallest in dictionary order**, which is why it always opens with a row of zeros. So you always get that one run, not just any run that would satisfy the rule. The same arguments always give the same run, which means a sketch built on it reproduces exactly.

An alphabet of zero symbols, or a window of zero, gives back an empty run. One symbol gives back a single zero, because there is only one possible window and it is all zeros.

<a name="code"></a>

#### DeBruijnCode

```swift
struct DeBruijnCode {
    init(symbols: Int, window: Int)
    let symbols: Int, window: Int
    let sequence: [Int]
    func position(of run: [Int]) -> Int?     // where those symbols sit
    func window(at position: Int) -> [Int]   // the symbols starting there
}
```

`DeBruijnCode` holds the sequence and reads it in the other direction. Give it a window, and it tells you where in the run that window sits, which is what the type is for.

```swift
let code = DeBruijnCode(symbols: 4, window: 3)   // 64 beads
code.position(of: [2, 0, 1])                     // where that triple sits
code.window(at: 17)                              // the triple starting there
```

`window(at:)` wraps, so any position is valid, including a negative one. `position(of:)` returns nil for a run of the wrong length, or for a run that holds a symbol the alphabet does not have. A run like that appears nowhere in the sequence, so there is no position to return.

The lookup table is built once, with one entry per window, so it holds `symbols` to the power of `window` entries. That is fine for thousands of entries, but not for millions.

<a name="lyndon"></a>

#### lyndonWords

```swift
lyndonWords(symbols: Int, maxLength: Int) -> [[Int]]
```

The result is every Lyndon word up to `maxLength`, in dictionary order. A Lyndon word is a run that is strictly smaller than every rotation of itself. So it is the one representative of a necklace that has no repeat in it.

```swift
lyndonWords(symbols: 2, maxLength: 3)   // 0, 001, 011, 1
```

Lyndon words are the pieces the de Bruijn sequence is made of. Take the words whose length divides the window, keep them in order, and lay them end to end. The result is the de Bruijn sequence. On their own, the words list the patterns of a given length that differ from each other, rather than the same pattern rotated. That makes them a ready set of motifs.

<a name="notes"></a>

#### Practical notes

- **The run is a ring, not a line.** If you draw it as a strip, the last few windows look broken. That is because they wrap around to the front. Draw it around a circle instead, or repeat the first `window - 1` symbols at the end.
- **Symbols are numbers, so you can map them onto anything**, such as colors, tile shapes, rotations, or note names. Four symbols with a window of three gives 64 beads, which is a comfortable size for a picture.
- **The length grows fast.** Five symbols with a window of five gives 3,125 beads, and six symbols with a window of six gives 46,656. Choose the window by how many symbols a reader can see at once, not by how long you want the run to be.
- Nothing here touches `random`, so a sketch built on the sequence reproduces exactly.

Example: `Patterns/DeBruijn`. Guide: [Chapter 6](../../Guide/06-GridsAndRepetition.md).

---

#### Where this comes from

The sequences are named for Nicolaas Govert de Bruijn, who counted the binary case in 1946. Camille Flye Sainte-Marie had already counted it in 1894. Scholars of Sanskrit meter knew the two-symbol, three-window case as the *yamātārājabhānasalagām* mnemonic long before either of them. The construction is the Lyndon-word concatenation of Harold Fredricksen, James Maiorana, and Irving Kessler. See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Wave Function Collapse](./WaveFunctionCollapse.md): the other way to build a pattern under local rules, by picking instead of counting
- [Polyominoes](./Polyominoes.md): pieces that have to fit exactly, the other generator built on exhaustive search
- [Randomness](./Random.md): the seeded generators, and how a random sequence differs from this one

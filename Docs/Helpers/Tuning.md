#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Tuning`</sup>

---

## Tuning toward a look

`import OllinAssist`

A `@Param` can be moved by a phrase. Type "warmer, and fewer rings", and the parameters those words concern move, inside the ranges you declared, on this Mac's own language model. Nothing leaves the machine, and no account or key is needed. The model never sees your code. It sees the parameters, each with its label, its range, and what it holds now, and it answers with values.

```swift
import OllinAssist

let tuning = try await tuneParameters(toward: "warmer, and fewer rings")
print(tuning.summary)   // Moved Tint from #8000FF to #FF4500 and Rings from 5 to 3.
tuning.revert()         // puts them back
```

### Contents

- [The field in the inspector](#field)
- [In a sketch](#sketch)
- [What the model is told](#told)
- [How well it works](#works)
- [When it is not there](#availability)
- [A model of your own](#model)
- [Where the line is](#line)

<a name="field"></a>

### The field in the inspector

The live host, the performance host, and the examples gallery all show a field above the Save button that reads **Describe a look**. Type a few words and press Return, or the arrow beside the field. About two seconds later the parameters the words concern have moved, and the line under the field says which:

```
Moved Radius from 120 to 180 and Tint from #8000FF to #FF4500.   Undo
```

**Undo** puts every one of them back. A parameter the ask moved counts as one you turned, so the Save button writes it into its `@Param` line the way it writes a dragged value, and a reload keeps it.

The field appears only on a Mac whose model is there. See [When it is not there](#availability).

<a name="sketch"></a>

### In a sketch

`tuneParameters(toward:)` is the same ask from code. It returns a `Tuning`, which names what moved:

```swift
let tuning = try await tuneParameters(toward: "as big as it goes")
for move in tuning.moves {
    print(move.label, move.before, move.after)   // Radius number(120.0) number(200.0)
}
tuning.summary      // the one line the inspector shows
tuning.leftOut      // labels of the parameters words cannot set
tuning.unreadable   // labels the model answered for with a value that could not be read
tuning.revert()     // back to before
```

The typed form is `ParameterTuner`. It takes the handles from `parameters()`, so a sketch can hand it a subset:

```swift
let tuner = ParameterTuner()
let tuning = try await tuner.tune(parameters().filter { $0.group == "Ink" },
                                  toward: "dusk", sketchName: "Rings")
```

An ask throws a `TuningError` when the phrase is empty, when the sketch has no parameter of a kind words can set, when the phrase is in a language the model does not read, when the model declines it, or when there are more parameters than it can read at once. Each case carries the sentence the inspector would show. The [DescribedLook example](../../Examples/Live/DescribedLook/Sketch.swift) types a phrase over the picture and asks on Return.

<a name="told"></a>

### What the model is told

Every ask is one request, and you can read it. `TuningRequest(parameters(), look:)` builds it, `promptText` is the prompt, and `TuningRequest.instructions` is the standing instruction that goes with every ask. A parameter is one line:

```
- rings: Rings, in the Layout group. a whole number from 1 to 12, now 5.
- tint: Tint, in the Ink group. a color as #RRGGBB, now #8000FF (purple).
```

The model reads the labels, so a well-named parameter is a parameter that answers to its name. `@Param("Paper")` will take "a darker background" where `bg` may not.

The kinds words can set are a number, a whole number, a toggle, a menu, a color, and a text. A point, a rectangle, an inset, a range, and a swatch strip are left out, and `leftOut` names them. A parameter whose [show-rule](./Parameters.md#show-rules) hides it is left out silently, as the inspector leaves it out.

The answer comes back under a schema built from those lines, one optional slot per parameter typed by its kind, so a number is a number and a menu choice is one of the menu's names. Each value is then read against the parameter itself: a number is held to its range and snapped to its step, a whole number is rounded, a menu choice is matched by name whatever its spacing or case, and a color is read as `#RRGGBB`. A value the kind cannot read (a color given as a word, a choice not on the menu) is named in `unreadable` rather than guessed. Every write goes through the control's own path, so a [smoothed](./Parameters.md#smoothing) parameter glides there.

<a name="works"></a>

### How well it works

The model is small and fast, and it is best at a phrase that names what it means. On a sketch with eight parameters, "fewer rings", "outlines only", "a bit more texture", and "as big as it goes" each moved the right parameter the right way. A relative word moves from the current value, so "much bigger" goes well past where it was and "slightly" takes a small step. A color word lands on the nearest color parameter: "a deep blue background" reaches a parameter labeled Paper.

Two things to know. The model sometimes moves a parameter the words never mentioned, alongside the one they did. And a vague phrase gets a guess. That is why every move is named in the line under the field and why Undo is one click: read the line, keep what is right, put back what is not. A phrase that fits no parameter can still move something, since the model prefers to answer; the line will say so.

<a name="availability"></a>

### When it is not there

The model is Apple's on-device language model, so it needs Apple Intelligence turned on in System Settings, on a Mac that can run it. `ParameterTuner.availability` says which it is:

```swift
switch ParameterTuner.availability {
case .available: break
case .unavailable(let reason): print(reason)   // "Apple Intelligence is off. Turn it on in System Settings to describe a look."
}
```

The inspector's field is simply absent on a machine without the model. Under the live host, `swift run OllinLive` on a Mac with the model on shows it; on another Mac the same sketch shows the same inspector without the field, and nothing else changes. An export never asks the model anything.

<a name="model"></a>

### A model of your own

`OnDeviceModel` is the one that ships. Anything that can turn a request into values by name can stand in for it:

```swift
struct Louder: TuningModel {
    func propose(_ request: TuningRequest) async throws -> TuningReply {
        request.look.contains("louder") ? ["gain": .number(1)] : [:]
    }
}

let tuning = try await ParameterTuner(model: Louder()).tune(parameters(), toward: "louder")
```

A reply is `[String: TunedValue]`, where a value is a `.number`, a `.bool`, or `.text` (a menu choice, a color, or a text). This is the seam the tests use, and the place a different model would go.

<a name="line"></a>

### Where the line is

Ollin's stance on AI is that it operates the framework and never authors the work, and this is that stance in one feature. The tuner moves the parameters you declared, inside the ranges you set, and writes values. It never writes code, never makes a picture, and never sees the sketch's source. The words are yours, the parameters are yours, and the Save button is still the only thing that reaches the file. The README's [Built with AI](../../README.md#built-with-ai) section says the rest.

---

<sup>[`Parameters`](./Parameters.md) - the `@Param` family, the inspector, and saving what you turned · [`Formula`](./Formula.md) - a parameter set from a rule read as text · [`Automation`](../Core/Automation.md) - a parameter directed over time · [Live coding](../Tools/LiveCoding.md) - the performance host</sup>

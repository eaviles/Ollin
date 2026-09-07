import Ollin
import Testing

/// A `ParamValue` conformance written outside the framework, wrapped through the
/// public initializers, and driven the way the hosts drive every parameter.
///
/// This file imports `Ollin` plainly, never `@testable`, on purpose: the defect it
/// pins was invisible from inside the module. The reference said a full
/// conformance works, and it did for the framework's own kinds, because they
/// reach the designated initializer that a sketch cannot. Everything here is
/// what a sketch in another module can write.
@Suite
@MainActor
struct ParamOwnTypeTests {

    /// A wrapped scalar that maps onto the slider: an opacity held as a fraction.
    /// The numeric constraints are the framework's own, so the clamp is `Double`'s.
    struct Opacity: ParamValue {
        var fraction: Double
        init(_ fraction: Double) { self.fraction = fraction }

        typealias Constraints = ParamNumericConstraints<Double>

        static func clamped(_ value: Opacity, by constraints: Constraints) -> Opacity {
            Opacity(Double.clamped(value.fraction, by: constraints))
        }
        static func stored(_ value: Opacity) -> ParamStored { .number(value.fraction) }
        static func restored(_ stored: ParamStored) -> Opacity? {
            guard case .number(let fraction) = stored else { return nil }
            return Opacity(fraction)
        }
        static func control(for param: Param<Opacity>) -> ParamControl {
            .slider(.init(range: param.constraints.range, step: param.constraints.step,
                          style: param.constraints.style,
                          read: { param.wrappedValue.fraction },
                          write: { param.wrappedValue = Opacity($0) }))
        }
    }

    /// A kind that needs no constraints: a caption held as text.
    struct Caption: ParamValue {
        var text: String
        init(_ text: String) { self.text = text }

        typealias Constraints = Void

        static func clamped(_ value: Caption, by _: Void) -> Caption { value }
        static func stored(_ value: Caption) -> ParamStored { .text(value.text) }
        static func restored(_ stored: ParamStored) -> Caption? {
            guard case .text(let text) = stored else { return nil }
            return Caption(text)
        }
        static func control(for param: Param<Caption>) -> ParamControl {
            .text(.init(read: { param.wrappedValue.text },
                        write: { param.wrappedValue = Caption($0) }))
        }
    }

    /// One of each, in the forms a sketch writes: bare, labeled, and decorated.
    final class OwnKinds: Sketch {
        @Param(constraints: .init(range: 0...1)) var veil = Opacity(0.5)
        @Param("Fade", constraints: .init(range: 0...1, step: 0.25)) var fade = Opacity(2)
        @Param var caption = Caption("hello")
        @Param("Heading", icon: "textformat", group: "Words") var heading = Caption("")
    }

    @Test func aWrappedScalarClampsThroughItsOwnConstraints() {
        let sketch = OwnKinds()
        #expect(sketch.veil.fraction == 0.5)
        #expect(sketch.fade.fraction == 1)          // 2 clamped into 0...1 at init
        sketch.veil = Opacity(3)
        #expect(sketch.veil.fraction == 1)
        sketch.veil = Opacity(-1)
        #expect(sketch.veil.fraction == 0)
        sketch.fade = Opacity(0.6)
        #expect(sketch.fade.fraction == 0.5)        // snapped to the step
    }

    @Test func theInspectorFindsThemAndTheirDecorations() {
        let sketch = OwnKinds()
        let handles = Dictionary(uniqueKeysWithValues: sketch.parameters().map { ($0.name, $0) })
        #expect(Set(handles.keys) == ["veil", "fade", "caption", "heading"])
        #expect(handles["veil"]?.label == "Veil")           // derived from the property
        #expect(handles["fade"]?.label == "Fade")           // given
        #expect(handles["heading"]?.icon == "textformat")
        #expect(handles["heading"]?.group == "Words")
        #expect(handles["caption"]?.group == nil)
    }

    @Test func theControlIsTheKindTheConformanceChose() {
        let sketch = OwnKinds()
        let handles = Dictionary(uniqueKeysWithValues: sketch.parameters().map { ($0.name, $0) })
        guard case .slider(let slider) = handles["fade"]?.control else {
            Issue.record("the opacity should edit as a slider"); return
        }
        #expect(slider.range == 0...1)
        #expect(slider.step == 0.25)
        #expect(slider.read() == 1)
        slider.write(0.25)
        #expect(sketch.fade.fraction == 0.25)
        guard case .text(let box) = handles["caption"]?.control else {
            Issue.record("the caption should edit as a text box"); return
        }
        #expect(box.read() == "hello")
        box.write("goodbye")
        #expect(sketch.caption.text == "goodbye")
    }

    /// The hosts persist and restore through the erased parameter, so a type of
    /// your own round-trips the same way the built-in kinds do, and a payload of
    /// the wrong kind is ignored rather than crashing or clearing the value.
    @Test func itPersistsAndRestoresLikeAnyOtherKind() {
        let sketch = OwnKinds()
        let handles = Dictionary(uniqueKeysWithValues: sketch.parameters().map { ($0.name, $0) })
        #expect(handles["veil"]?.param.stored == .number(0.5))
        handles["veil"]?.param.restore(.number(0.75))
        #expect(sketch.veil.fraction == 0.75)
        handles["veil"]?.param.restore(.number(9))
        #expect(sketch.veil.fraction == 1)               // a restore still clamps
        handles["veil"]?.param.restore(.boolean(true))
        #expect(sketch.veil.fraction == 1)               // the wrong kind is ignored
        #expect(handles["caption"]?.param.stored == .text("hello"))
        handles["caption"]?.param.restore(.text("later"))
        #expect(sketch.caption.text == "later")
    }

    /// The `constraints:` form is the primitive. A type can put its own shorter
    /// spelling over it, the way the built-in kinds do, so a sketch reads
    /// `@Param(0...1)` for an opacity too.
    @Test func aShorterSpellingOfYourOwnSitsOverThePrimitive() {
        final class Sugared: Sketch {
            @Param(0...1) var glow = Opacity(0.2)
            @Param("Haze", 0...0.5, icon: "cloud") var haze = Opacity(0.9)
        }
        let sketch = Sugared()
        #expect(sketch.glow.fraction == 0.2)
        #expect(sketch.haze.fraction == 0.5)
        let handles = Dictionary(uniqueKeysWithValues: sketch.parameters().map { ($0.name, $0) })
        #expect(handles["haze"]?.label == "Haze")
        #expect(handles["haze"]?.icon == "cloud")
    }
}

extension Param where Value == ParamOwnTypeTests.Opacity {
    convenience init(wrappedValue: Value, _ range: ClosedRange<Double>,
                     icon: String? = nil, group: ParamGroup? = nil) {
        self.init(wrappedValue: wrappedValue, constraints: .init(range: range), icon: icon, group: group)
    }

    convenience init(wrappedValue: Value, _ label: String, _ range: ClosedRange<Double>,
                     icon: String? = nil, group: ParamGroup? = nil) {
        self.init(wrappedValue: wrappedValue, label, constraints: .init(range: range), icon: icon, group: group)
    }
}

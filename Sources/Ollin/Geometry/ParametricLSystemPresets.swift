import Foundation

// The published parametric grammars, transcribed with their own constants. Each
// carries the book's spelling of its rules in a comment, since this reader takes
// the reference implementation's spellings (`^`, `==`, `&&`) where the book
// writes them with single characters, and the lineage should stay checkable
// against the page.
//
// Two of these need a turn angle the sources never state. Where that happens the
// value is named as Ollin's own rather than passed off as the book's; see the
// note on each.

public extension ParametricLSystem {

    /// One unbroken line that packs itself into a triangle. The single rule cuts
    /// every segment into four unequal pieces, at ratios the grammar carries as
    /// numbers, and it is the smallest demonstration of what that buys: no plain
    /// grammar can draw a segment three tenths as long as its parent.
    ///
    /// Try 5 to 8 passes; each one multiplies the line by four.
    static var triangleCurve: ParametricLSystem {
        // p1 : F(x) -> F(x*p) + F(x*h) - - F(x*h) + F(x*q)
        let p = 0.3, q = 1 - 0.3
        return ParametricLSystem(
            axiom: "F(1)",
            rules: ["F(x) -> F(x*p)+F(x*h)--F(x*h)+F(x*q)"],
            angle: 86,
            constants: ["p": p, "q": q, "h": (p * q).squareRoot()])
    }

    /// The same triangle, with a second parameter that counts down before a
    /// segment is allowed to divide. The turtle never reads that counter, which
    /// is the point: a module can carry state the drawing knows nothing about,
    /// and here it holds the short pieces back so the triangle fills evenly
    /// instead of in patches.
    ///
    /// Try 8 to 12 passes. It needs more of them than ``triangleCurve`` for the
    /// same depth, since the counter costs each segment a pass or two.
    static var delayedTriangleCurve: ParametricLSystem {
        // p1 : F(x,t) : t=0 -> F(x*p,2) + F(x*h,1) - - F(x*h,1) + F(x*q,0)
        // p2 : F(x,t) : t>0 -> F(x,t-1)
        let p = 0.3, q = 1 - 0.3
        return ParametricLSystem(
            axiom: "F(1, 0)",
            rules: ["F(x,t) : t == 0 -> F(x*p,2)+F(x*h,1)--F(x*h,1)+F(x*q,0)",
                    "F(x,t) : t > 0  -> F(x,t-1)"],
            angle: 86,
            constants: ["p": p, "q": q, "h": (p * q).squareRoot()])
    }

    /// A branch that forks in two, each child shorter than its parent by a fixed
    /// ratio. The ratio sits just above the square root of two, which is what
    /// keeps the form from ever growing into itself.
    ///
    /// Try 8 to 10 passes.
    static var selfSimilarBranch: ParametricLSystem {
        // p1 : A(s) -> F(s)[+A(s/R)][-A(s/R)]
        ParametricLSystem(
            axiom: "A(1)",
            rules: ["A(s) -> F(s)[+A(s/R)][-A(s/R)]"],
            angle: 85,
            constants: ["R": 1.456])
    }

    /// The same proportions reached the other way round: instead of adding ever
    /// shorter segments, it adds segments of one length and lengthens every
    /// segment already drawn. The finished forms agree, but this one grows the
    /// way a tree grows rather than the way a fractal subdivides.
    ///
    /// Try 8 to 10 passes.
    static var growingBranch: ParametricLSystem {
        // p1 : A -> F(1)[+A][-A]        p2 : F(s) -> F(s*R)
        ParametricLSystem(
            axiom: "A",
            rules: ["A -> F(1)[+A][-A]", "F(s) -> F(s*R)"],
            angle: 85,
            constants: ["R": 1.456])
    }

    /// A compound leaf: a stalk that keeps making leaflets while every part of
    /// it goes on lengthening. The bud waits `D` passes before it opens, and
    /// that delay against the lengthening rate is the whole shape.
    ///
    /// Try 16 passes. The published form is delicate: the source warns that
    /// moving the lengthening rate by 0.01 visibly alters the proportions.
    ///
    /// - Note: The turn angle is the one number the source never prints for this
    ///   figure. 45 degrees is Ollin's reading of the published drawing, where a
    ///   branch leaving on the diagonal carries sub-branches that are exactly
    ///   horizontal and exactly vertical, which fixes twice the angle at a right
    ///   angle.
    static var compoundLeaf: ParametricLSystem {
        // p1 : A(d) : d>0 -> A(d-1)
        // p2 : A(d) : d=0 -> F(1)[+A(D)][-A(D)]F(1)A(0)
        // p3 : F(a) : *   -> F(a*R)
        ParametricLSystem(
            axiom: "A(0)",
            rules: ["A(d) : d > 0  -> A(d-1)",
                    "A(d) : d == 0 -> F(1)[+A(D)][-A(D)]F(1)A(0)",
                    "F(a) -> F(a*R)"],
            angle: 45,
            constants: ["D": 1, "R": 1.5])
    }

    /// A compound leaf whose leaflets come off alternate sides rather than in
    /// facing pairs, which two modules taking turns is enough to express.
    ///
    /// Try 20 passes. The angle is Ollin's, on the same reading as
    /// ``compoundLeaf``.
    static var alternatingLeaf: ParametricLSystem {
        // p1/p2 : A(d) ...   p3/p4 : B(d) ...   p5 : F(a) -> F(a*R)
        ParametricLSystem(
            axiom: "A(0)",
            rules: ["A(d) : d > 0  -> A(d-1)",
                    "A(d) : d == 0 -> F(1)[+A(D)]F(1)B(0)",
                    "B(d) : d > 0  -> B(d-1)",
                    "B(d) : d == 0 -> F(1)[-B(D)]F(1)A(0)",
                    "F(a) -> F(a*R)"],
            angle: 45,
            constants: ["D": 1, "R": 1.36])
    }

    /// The snowflake curve written parametrically: each segment becomes four,
    /// each a third as long. A plain grammar cannot say "a third", so it has to
    /// be built the other way about, out of whole steps.
    ///
    /// Try 4 to 6 passes.
    static var snowflake: ParametricLSystem {
        ParametricLSystem(
            axiom: "F(1) - (120) F(1) - (120) F(1)",
            rules: ["F(s) -> F(s/3) + (60) F(s/3) - (120) F(s/3) + (60) F(s/3)"],
            angle: 60)
    }

    /// A branching form whose widest point sits partway up rather than at the
    /// bottom or the top. Each new bud is told how long it is allowed to grow,
    /// and later buds are told a larger number, so the branches lengthen up the
    /// stem and then run out of passes to grow in. This is the pattern the
    /// literature gives as one a plain grammar provably cannot make.
    ///
    /// Needs about 12 passes or more before the bulge is legible, since the
    /// widest branch lands halfway along and there must be branches either side
    /// of it to read as a bulge.
    ///
    /// - Note: The turn angle is Ollin's. The source states the grammar but
    ///   never an angle, and its illustration is a hand-drawn diagram rather
    ///   than a drawing of these rules.
    static var mesotonicBranch: ParametricLSystem {
        // p1 : A(v)         -> [-FB(v)][+FB(v)] F A(v+1)
        // p2 : B(v) : v > 0 -> F B(v-1)
        ParametricLSystem(
            axiom: "F A(0)",
            rules: ["A(v) -> [-FB(v)][+FB(v)]FA(v+1)",
                    "B(v) : v > 0 -> FB(v-1)"],
            angle: 60)
    }

    /// A tree that tapers: every branch is told its own length *and* its own
    /// width, so the trunk is thick and the twigs are fine. Draw it with
    /// ``Sketch/lSystemMarks(_:iterations:in:padding:)``, or
    /// ``Sketch/drawLSystem(_:iterations:in:padding:tapered:)`` asking for
    /// `tapered`, and the widths come through.
    ///
    /// The defaults are the first row of the published table of nine trees. The
    /// others are worth typing out; a few of them are in the reference page.
    /// Try 10 passes.
    ///
    /// - Parameters:
    ///   - contraction1: How much of its parent's length the first child takes.
    ///   - contraction2: The same for the second child.
    ///   - angle1: How far the first child leans, in degrees. May be negative.
    ///   - angle2: The same for the second child.
    ///   - roll1: A half turn (180) swaps left and right for the first child's
    ///     whole subtree; 0 leaves it alone. Other values need a turtle that
    ///     leaves the plane, and say so.
    ///   - roll2: The same for the second child.
    ///   - width: The width of the trunk, in the same units as the length, which
    ///     starts at 100.
    ///   - split: How the width is shared between the two children, 0 to 1.
    ///   - exponent: How sharply width falls off. At 0.5 the two children carry
    ///     as much cross-section as their parent.
    ///   - minimumLength: Growth stops in a branch once it would be shorter than
    ///     this, so a form can settle before it runs out of passes.
    static func taperedTree(contraction1: Double = 0.75, contraction2: Double = 0.77,
                            angle1: Double = 35, angle2: Double = -35,
                            roll1: Double = 0, roll2: Double = 0,
                            width: Double = 30, split: Double = 0.5,
                            exponent: Double = 0.4,
                            minimumLength: Double = 0) -> ParametricLSystem {
        // p1 : A(s,w) : s >= min -> !(w)F(s)
        //                           [+(a1)/(f1)A(s*r1, w*q^e)]
        //                           [+(a2)/(f2)A(s*r2, w*(1-q)^e)]
        ParametricLSystem(
            axiom: "A(100, w0)",
            rules: ["A(s,w) : s >= min -> !(w)F(s)[+(a1)/(f1)A(s*r1, w*q^e)][+(a2)/(f2)A(s*r2, w*(1-q)^e)]"],
            angle: 45,
            constants: ["r1": contraction1, "r2": contraction2,
                        "a1": angle1, "a2": angle2,
                        "f1": roll1, "f2": roll2,
                        "w0": width, "q": split, "e": exponent,
                        "min": minimumLength])
    }

    /// A branch that leans a different way each time it forks, so every seed
    /// grows a tree of its own while the proportions stay the same. This one is
    /// Ollin's, built by giving the published self-similar branch a pair of
    /// weighted rules.
    ///
    /// Try 8 to 10 passes, and `seed(_:)` to fix the form.
    static var randomBranch: ParametricLSystem {
        ParametricLSystem(
            axiom: "A(1)",
            rules: ["A(s) -> F(s)[+(a)A(s/R)][-(b)A(s/R)] : 2",
                    "A(s) -> F(s)[+(b)A(s/R)][-(a)A(s/R)] : 2",
                    "A(s) -> F(s)[+(a)A(s/R)]              : 1"],
            angle: 85,
            constants: ["R": 1.42, "a": 22, "b": 38])
    }
}

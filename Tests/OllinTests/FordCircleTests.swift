import Foundation
import Ollin
import Testing

/// Laws for the Farey sequence and the Ford circles built on it. Both are defined
/// by exact statements about whole numbers, so the tests are those statements and
/// not a look at the picture.
@Suite
struct FordCircleTests {
    // MARK: - Fractions

    /// A fraction reduces, keeps its sign on top, and knows what it is worth.
    @Test func aFractionReducesAndKeepsItsSignOnTop() {
        #expect(Fraction(2, 4) == Fraction(1, 2))
        #expect(Fraction(-3, 9) == Fraction(-1, 3))
        #expect(Fraction(3, -9) == Fraction(-1, 3))
        #expect(Fraction(0, 7) == Fraction(0, 1))
        #expect(Fraction(5).denominator == 1)
        // Nothing over nothing is not a number, so the bottom reads as one.
        #expect(Fraction(3, 0) == Fraction(3, 1))
        #expect(abs(Fraction(3, 8).value - 0.375) < 1e-12)
        #expect(Fraction(1, 3) < Fraction(1, 2))
        #expect("\(Fraction(4, 6))" == "2/3")
    }

    /// The mediant lands strictly between the two fractions it came from. This is
    /// the whole reason the sequence grows the way it does.
    @Test func theMediantLandsBetween() {
        for a in 1 ... 12 {
            for b in 1 ... 12 {
                for c in 1 ... 12 {
                    for d in 1 ... 12 {
                        let left = Fraction(a, b), right = Fraction(c, d)
                        guard left < right else { continue }
                        let between = left.mediant(with: right)
                        #expect(left < between && between < right,
                                "\(left), \(between), \(right)")
                    }
                }
            }
        }
    }

    // MARK: - The Farey sequence

    /// Against the definition: every fraction from 0 to 1 in lowest terms with a
    /// denominator inside the order, sorted. Built here by brute force, which is
    /// what the walk is being checked against.
    @Test func theWalkFindsExactlyTheFractionsTheDefinitionNames() {
        for order in 1 ... 20 {
            var wanted: [Fraction] = []
            for denominator in 1 ... order {
                for numerator in 0 ... denominator where gcd(numerator, denominator) == 1 {
                    wanted.append(Fraction(numerator, denominator))
                }
            }
            wanted = Array(Set(wanted)).sorted()
            #expect(fareySequence(order: order) == wanted, "order \(order)")
        }
        #expect(fareySequence(order: 0).isEmpty)
        #expect(fareySequence(order: 1) == [Fraction(0, 1), Fraction(1, 1)])
        #expect(fareySequence(order: 4).map(\.description)
            == ["0/1", "1/4", "1/3", "1/2", "2/3", "3/4", "1/1"])
    }

    /// The count is one more than the totient sum, which is the standard formula
    /// for how long the sequence is. Euler's function is counted here from its own
    /// definition rather than taken from anywhere.
    @Test func theSequenceIsAsLongAsTheTotientSumSaysItIs() {
        for order in 1 ... 40 {
            var total = 1
            for k in 1 ... order {
                total += (1 ... k).filter { gcd($0, k) == 1 }.count
            }
            #expect(fareySequence(order: order).count == total, "order \(order)")
        }
    }

    /// Any two terms next to each other are neighbors: `ps - qr` is exactly `-1`.
    /// Nothing about the picture rests on more than this.
    @Test func neighborsInTheSequenceAreUnimodular() {
        for order in 1 ... 30 {
            let terms = fareySequence(order: order)
            for i in 1 ..< terms.count {
                #expect(terms[i - 1].determinant(with: terms[i]) == -1,
                        "order \(order) at \(terms[i - 1]) and \(terms[i])")
                #expect(terms[i - 1].isNeighbor(of: terms[i]))
            }
        }
    }

    /// The first fraction ever to appear between two neighbors is their mediant,
    /// and it appears exactly at the order its denominator names.
    @Test func theMediantIsTheNextFractionBetweenTwoNeighbors() {
        for order in 1 ... 14 {
            let terms = fareySequence(order: order)
            for i in 1 ..< terms.count {
                let left = terms[i - 1], right = terms[i]
                let between = left.mediant(with: right)
                #expect(between.denominator > order,
                        "\(between) should not have fitted in order \(order)")
                let later = fareySequence(order: between.denominator)
                guard let place = later.firstIndex(of: between) else {
                    Issue.record("\(between) never appeared")
                    continue
                }
                // And when it appears, it appears exactly between the two.
                #expect(later[place - 1] == left)
                #expect(later[place + 1] == right)
            }
        }
    }

    // MARK: - The circles

    /// The law the whole picture rests on, measured on every pair at once: two Ford
    /// circles touch when their fractions are neighbors, and are strictly apart
    /// otherwise. Never overlapping is the half that a picture cannot show.
    @Test func circlesTouchExactlyWhenTheirFractionsAreNeighbors() {
        let box = Rectangle(x: 0, y: 0, width: 1000, height: 500)
        let circles = fordCircles(order: 14, in: box)
        #expect(circles.count == fareySequence(order: 14).count)

        var touching = 0
        for i in circles.indices {
            for j in (i + 1) ..< circles.count {
                let a = circles[i].circle, b = circles[j].circle
                let gap = a.center.distance(to: b.center) - (a.radius + b.radius)
                let neighbors = circles[i].fraction.isNeighbor(of: circles[j].fraction)
                #expect(neighbors == circles[i].touches(circles[j]))
                if neighbors {
                    touching += 1
                    // Touching, to the last place a Double can hold at this size.
                    #expect(abs(gap) < 1e-9, "\(circles[i].fraction) and \(circles[j].fraction) gap \(gap)")
                } else {
                    #expect(gap > 1e-9,
                            "\(circles[i].fraction) and \(circles[j].fraction) overlap by \(-gap)")
                }
            }
        }
        // Every term but the first touches the one before it, and the pairs found
        // by geometry have to be more than that (a circle touches others besides
        // its neighbors in the list).
        #expect(touching > circles.count)
    }

    /// Every circle sits on the line, on its own fraction, at the size the rule
    /// gives it.
    @Test func everyCircleSitsOnTheLineAtItsOwnFraction() {
        let box = Rectangle(x: 40, y: 10, width: 800, height: 300)
        for ford in fordCircles(order: 9, in: box) {
            let q = Double(ford.fraction.denominator)
            #expect(abs(ford.circle.radius - 800 / (2 * q * q)) < 1e-12)
            #expect(abs(ford.circle.center.x - (40 + ford.fraction.value * 800)) < 1e-12)
            // Tangent to the bottom edge: the circle's low point is on it.
            #expect(abs(ford.circle.center.y + ford.circle.radius - 310) < 1e-12)
        }
    }

    /// The interval narrows the run of fractions and touches nothing else.
    @Test func anIntervalOnlyLeavesFractionsOut() {
        let box = Rectangle(x: 0, y: 0, width: 600, height: 300)
        let all = fordCircles(order: 8, in: box)
        let middle = fordCircles(order: 8, in: box, interval: 0.25 ... 0.75)
        #expect(middle.count < all.count)
        #expect(middle.allSatisfy { $0.fraction.value >= 0.25 && $0.fraction.value <= 0.75 })
        for ford in middle {
            #expect(all.contains(ford), "\(ford.fraction) moved when the interval narrowed")
        }
        #expect(fordCircles(order: 0, in: box).isEmpty)
        #expect(fordCircles(order: 8, in: Rectangle(x: 0, y: 0, width: 0, height: 10)).isEmpty)
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var a = abs(a), b = abs(b)
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}

import Foundation
import OllinExpander
import Testing
@testable import Ollin

/// The fill tessellator never ends the process. Its sweep keeps its order by
/// comparing vertices, and a folded ring crossing itself hundreds of times within a
/// few pixels, with points on top of each other, put that order out in single
/// precision: the vendored tessellator's asserts fired and took a live window down
/// (2026-10-26, three times in one session, from `withClip` and `drawShape` over a
/// `curveThrough` ring that had collapsed to under 1% of its area). Two such rings,
/// generated to the report's numbers and each of which asserted under the old
/// build (a third asserted with the cleaning in and the precision still single),
/// go through the fill here; the statement is only that the call returns,
/// with triangles inside the ring's own box. Beside them, the cleaning the expander
/// applies before the tessellator: points on top of each other merge, a ring along a
/// line is nothing, and a ring that crosses itself is kept whole.
@Suite
@MainActor
struct TessellationRobustnessTests {

    /// A ring of beads sitting on two hubs five pixels apart, in runs, so its edges are
    /// a bundle of nearly coincident lines with cusps at each end: the sweep's winding
    /// assertion (`AddRightEdges`) under the single-precision build.
    nonisolated static let bundledRing: [Vector2] = [
        Vector2(607.4795418842474, 801.264843292262), Vector2(607.4794627060309, 801.2651248345067), Vector2(607.4802066816052, 801.2650948145072),
        Vector2(607.4785240362265, 801.2635442829104), Vector2(607.4804847554158, 801.2642404626462), Vector2(607.4808161906898, 801.2629207178176),
        Vector2(612.5201119771484, 798.7367066937652), Vector2(612.5195574575946, 798.7351969218033), Vector2(610.7009946948041, 799.7015759873988),
        Vector2(607.4795763310283, 801.2650706927511), Vector2(612.5192035058016, 798.7370407538045), Vector2(612.518972732626, 798.7365414007555),
        Vector2(612.5201857589436, 798.7355139638797), Vector2(612.5193805317743, 798.7363151938639), Vector2(612.5197874251727, 798.7364328042984),
        Vector2(610.3612052515324, 799.6552759103764), Vector2(607.4798155610281, 801.2644636036696), Vector2(607.4808184777471, 801.2632136419988),
        Vector2(607.4796101779084, 801.2629250543106), Vector2(607.4790410649593, 801.2629125258462), Vector2(607.4787346843852, 801.2628806734494),
        Vector2(607.480185416083, 801.2643197298945), Vector2(612.5203424900958, 798.7351193007893), Vector2(612.5190569013484, 798.7366426964601),
        Vector2(612.521602999429, 798.7364542311209), Vector2(612.5208611815389, 798.7347263634585), Vector2(612.5215617532734, 798.7360970888448),
        Vector2(612.5198212644216, 798.7347859029626), Vector2(607.4797884959103, 801.2640937572863), Vector2(607.4791359191005, 801.2638302692045),
        Vector2(607.479299648643, 801.2631888569863), Vector2(612.5209445821222, 798.7361815024294), Vector2(607.4792590092022, 801.2626400468541),
        Vector2(607.478724935607, 801.262594354713), Vector2(610.9666055774451, 799.4238622911174), Vector2(612.5200595376565, 798.7356627374911),
        Vector2(612.5202488871544, 798.7369901912741), Vector2(612.5211073726873, 798.7371881494562), Vector2(612.5205863532279, 798.7351030628868),
        Vector2(612.5211180794097, 798.7372711071664), Vector2(607.4807998447875, 801.262600860099), Vector2(607.4801154703956, 801.2651426825408),
        Vector2(607.4808851310606, 801.2645240946368), Vector2(607.4802440637771, 801.2637399795492), Vector2(607.4786237301764, 801.2627798926354),
        Vector2(607.4785700980759, 801.2647020898899), Vector2(607.48064452531, 801.2647555864676), Vector2(612.521180719967, 798.735129557008),
        Vector2(612.5207908299782, 798.7372889812588), Vector2(607.4783242756934, 801.2650803692933), Vector2(612.5190880519822, 798.7365759859739),
        Vector2(612.5213354130416, 798.7362329746934), Vector2(612.5214321441995, 798.7363361303051), Vector2(612.5209204440706, 798.7373346752416),
        Vector2(612.5195992698935, 798.7365802363375), Vector2(612.520754861349, 798.7361659703143), Vector2(607.4792956202953, 801.2643737081975),
        Vector2(607.4791890267783, 801.2650071355823), Vector2(607.4809911394859, 801.263156979717), Vector2(607.4801893049574, 801.2627169268486),
        Vector2(607.4791347996965, 801.2631034757036), Vector2(607.4783197379288, 801.2631004005411), Vector2(612.5215065207931, 798.7352440331765),
        Vector2(612.5211930094872, 798.7372286558572), Vector2(612.5212680463885, 798.737144838944), Vector2(612.5194961572386, 798.7351840081442),
        Vector2(608.9994951825131, 800.6014801422456), Vector2(607.479237279346, 801.2643560598314), Vector2(609.6869318867073, 800.2421953124854),
        Vector2(612.51897460383, 798.7371326318605), Vector2(612.5195145465992, 798.7363057563905), Vector2(612.5195795659223, 798.7363021955018),
        Vector2(612.5197843322757, 798.7374069017484), Vector2(612.5208932981791, 798.7356112533469), Vector2(612.5197775623875, 798.7353599134221),
        Vector2(607.4784888001054, 801.262580288624), Vector2(607.4785052018511, 801.2641684871247), Vector2(607.4787349486747, 801.2646598729176),
        Vector2(607.4786538306611, 801.2636545019939), Vector2(607.4790600899562, 801.2633955574839), Vector2(607.4798855407721, 801.2652688959063),
        Vector2(607.4806676143165, 801.2636625833372), Vector2(611.3839000097757, 799.301898362479)
    ]

    /// A ring collapsed within a few pixels of one point, exact duplicates included:
    /// the vertex-order assertion (`tesedgeEval`) under the single-precision build, the
    /// one the live window reported.
    nonisolated static let collapsedRing: [Vector2] = [
        Vector2(591.2531320138863, 810.9769792027632), Vector2(591.999733568558, 812.2966065353846), Vector2(590.8161540041431, 808.2149266244535),
        Vector2(590.095223241146, 812.8409186434994), Vector2(592.8646033059105, 809.1675289247808), Vector2(592.8600230510962, 809.1768992422714),
        Vector2(592.3631162398431, 809.8528621644334), Vector2(592.3657421968741, 809.8545691820698), Vector2(592.364438461706, 809.8555479176173),
        Vector2(591.4106570029388, 813.5868964728613), Vector2(590.4767860695616, 808.8767986756944), Vector2(593.0270946581119, 809.0024708696671),
        Vector2(593.0270946581119, 809.0024708696671), Vector2(593.0211798629741, 809.0027830377467), Vector2(591.5675058964384, 811.9751009810583),
        Vector2(591.5675058964384, 811.9751009810583), Vector2(591.5675058964384, 811.9751009810583), Vector2(591.5689706242982, 811.9844689782411),
        Vector2(588.7731695932321, 808.0687732550831), Vector2(591.590708312981, 809.1510064880812), Vector2(591.590708312981, 809.1510064880812),
        Vector2(593.6088793060027, 810.5434917642882), Vector2(593.4320546029647, 813.4926467891934), Vector2(593.4320546029647, 813.4926467891934),
        Vector2(593.4246005576239, 813.4976048337229), Vector2(592.6181726975334, 808.4615806651897), Vector2(592.6102853836422, 808.4680476115086),
        Vector2(593.4461065607903, 808.8628611994146), Vector2(593.4461065607903, 808.8628611994146), Vector2(592.1089090668613, 811.0055294024916),
        Vector2(594.1133511976434, 813.7342993379334), Vector2(594.1062578726008, 813.7264360556275), Vector2(592.417196515533, 810.748513640975),
        Vector2(592.8055618822648, 811.4112514059633), Vector2(591.8319844940698, 808.4395009962266), Vector2(591.8342418006397, 808.4435397036962),
        Vector2(589.8502416182424, 813.372614033866), Vector2(589.8502416182424, 813.372614033866), Vector2(589.110839307875, 810.6332432538334),
        Vector2(588.8335859246657, 811.9510686086589), Vector2(588.8335859246657, 811.9510686086589), Vector2(590.4096855067547, 809.4709760640834),
        Vector2(590.4096855067547, 809.4709760640834), Vector2(593.7744422341868, 812.3124561629177), Vector2(593.7744422341868, 812.3124561629177),
        Vector2(593.7744422341868, 812.3124561629177), Vector2(593.76741167602, 812.3077162903512), Vector2(593.76741167602, 812.3077162903512),
        Vector2(591.0309611355234, 813.0457734001072), Vector2(591.0401902744609, 813.0471929027475), Vector2(591.2872960541087, 812.4508040288889),
        Vector2(591.2872960541087, 812.4508040288889), Vector2(591.6105293456471, 809.5124813397433), Vector2(591.7835689451853, 813.0474820921959),
        Vector2(591.7808539938252, 813.0470634111856), Vector2(591.7895852849417, 813.0428572202677), Vector2(591.6262103301488, 813.0644305315938),
        Vector2(591.6346727603722, 813.0679157202211), Vector2(591.6325638590888, 813.0679416149986), Vector2(593.6122633496282, 809.3396998845595),
        Vector2(593.541012502296, 813.84997093238), Vector2(593.5471408832715, 813.8561934540575), Vector2(593.5471408832715, 813.8561934540575),
        Vector2(593.5471408832715, 813.8561934540575), Vector2(593.539956137962, 813.8482553094569), Vector2(592.891115190087, 809.06672204719),
        Vector2(590.6083963492553, 811.6165480302116), Vector2(590.6083963492553, 811.6165480302116), Vector2(590.4017533612649, 811.1606994484076),
        Vector2(592.3543418111939, 810.0660462043263), Vector2(592.3477453339837, 810.0692554617298), Vector2(590.2293544897393, 810.9196849485833),
        Vector2(590.2266668222494, 810.9262651317893), Vector2(589.0026399036022, 810.3443487132745), Vector2(588.9995465844261, 810.3344736125626),
        Vector2(588.9995465844261, 810.3344736125626), Vector2(589.0032151648352, 810.3330915888122), Vector2(591.2035120242085, 812.7639201383358),
        Vector2(593.5430829854773, 810.3574866445082), Vector2(593.5355704040445, 810.3593053646855), Vector2(592.2622500819948, 809.5677703858341),
        Vector2(592.2622500819948, 809.5677703858341), Vector2(592.2622500819948, 809.5677703858341)
    ]

    /// A second bundle, the one that still asserted in single precision after the
    /// cleaning had gone in (the cleaning rescued the other two by luck, moving the
    /// sweep's order rather than settling it; seven of a hundred thousand such rings
    /// did the same), and the one that proves the double.
    nonisolated static let bundledRing2: [Vector2] = [
        Vector2(613.4958015493678, 807.2618766590576), Vector2(613.4959468779741, 807.262787532178), Vector2(613.4963863845027, 807.2611949971746),
        Vector2(613.4957966459565, 807.2613975773899), Vector2(606.5051087656213, 792.7374446152901), Vector2(606.5049073048751, 792.7387445493356),
        Vector2(606.5052792784211, 792.7377546380975), Vector2(606.5039813999045, 792.7372163444214), Vector2(606.5038215615598, 792.737315405873),
        Vector2(611.1527731810642, 800.1930029888804), Vector2(613.4964206160705, 807.2629017577582), Vector2(613.4947949147554, 807.2626600403019),
        Vector2(613.495900894089, 807.2628523090524), Vector2(613.494791115115, 807.2624708455736), Vector2(613.4955542072543, 807.2620620474338),
        Vector2(613.4959678790925, 807.262177798676), Vector2(605.8238463474481, 793.0036364286224), Vector2(606.5038059073887, 792.737631786114),
        Vector2(606.505252294199, 792.7387006097158), Vector2(606.5048014283877, 792.7386628831899), Vector2(613.4962049369392, 807.2613280012307),
        Vector2(613.495318183842, 807.2615240188701), Vector2(613.4953873779855, 807.261907035868), Vector2(613.4952813901107, 807.262341738882),
        Vector2(608.518922510017, 795.3734283616534), Vector2(606.503971934671, 792.7380137150685), Vector2(606.5037771184998, 792.7376063591923),
        Vector2(606.5047297841016, 792.7380554400817), Vector2(606.5041630649965, 792.7385610220548), Vector2(606.5050620110885, 792.7375509941712),
        Vector2(606.5040012188682, 792.7375301505725), Vector2(606.5043459825895, 792.7374378971119), Vector2(613.4959192621689, 807.2619490041983),
        Vector2(613.4950897645376, 807.262473889374), Vector2(613.4956801506524, 807.2620263620743), Vector2(606.5037522169903, 792.7387093539733),
        Vector2(606.5045402233993, 792.7377375545617), Vector2(606.504285165855, 792.7370998698797), Vector2(606.5051555038275, 792.7372008658548),
        Vector2(606.5048944209866, 792.7387206094443), Vector2(606.5051577552387, 792.7372200921924), Vector2(606.5039524897135, 792.7385372853753),
        Vector2(613.4952479597462, 807.2616734931066), Vector2(613.4951621763694, 807.2612376425888), Vector2(613.494983961336, 807.2624137688911),
        Vector2(613.4963641442916, 807.2629233851957), Vector2(613.4964058161545, 807.2625182141486), Vector2(613.4957598810782, 807.262896416069),
        Vector2(613.4958725238944, 807.2615100497312), Vector2(606.5040673963958, 792.7381255622741), Vector2(606.503697902929, 792.7377946075542),
        Vector2(606.504573447222, 792.7381959466446), Vector2(606.5048241626639, 792.7383668033834), Vector2(610.6745643427682, 801.7896230838393),
        Vector2(613.4957696111006, 807.2614129778829), Vector2(613.4958165751577, 807.2619343673357), Vector2(613.4954810902755, 807.2612525184977),
        Vector2(606.5051548445208, 792.737581568062), Vector2(606.5051438422623, 792.7384363750631), Vector2(606.5044608382923, 792.7376117267671),
        Vector2(606.5042950728428, 792.7377910082316), Vector2(606.503733769514, 792.7381697992796), Vector2(613.4954598508106, 807.2620320349555),
        Vector2(613.4955849001964, 807.2626062053373), Vector2(606.5050916405972, 792.7384142647152), Vector2(606.5049027692165, 792.7379805142853),
        Vector2(606.504547767215, 792.737461688126), Vector2(606.5051902812024, 792.7381957481808), Vector2(613.4964405102321, 807.2614474654272),
        Vector2(613.4950362478527, 807.2624701328517), Vector2(613.4949112674261, 807.2623272648862), Vector2(613.4957850697537, 807.2626807217612),
        Vector2(613.4951649876688, 807.2623161995084), Vector2(613.4963940038143, 807.2626339292182), Vector2(606.5050685442992, 792.737253933967),
        Vector2(606.5038376589816, 792.738649941952), Vector2(606.5049786358106, 792.7377804787125), Vector2(606.5041470579133, 792.7375925002735),
        Vector2(613.4951974742957, 807.2616403352), Vector2(606.5049909418486, 792.7383738095568), Vector2(606.5039565487496, 792.7377198101154),
        Vector2(606.5036490419326, 792.7380664242401), Vector2(606.5048942601933, 792.7384907476819)
    ]

    @Test(arguments: [("bundled", bundledRing), ("collapsed", collapsedRing), ("bundled again", bundledRing2)])
    func aFoldedRingNeverEndsTheProcess(name: String, ring: [Vector2]) {
        let shape = Shape(curveThrough: ring, closed: true)
        let sampled = shape.contours[0].points.count
        #expect(sampled > ring.count, "the \(name) ring sampled to \(sampled) points")
        let triangles = shape.triangulatedFill()
        #expect(triangles.count % 3 == 0)
        // Whatever the sweep made of it, it stays inside the ring's own box (padded by
        // a pixel for the curve's overshoot past its anchors).
        guard let bounds = shape.bounds else { Issue.record("the \(name) ring has no bounds"); return }
        let padded = Rectangle(x: bounds.x - 1, y: bounds.y - 1, width: bounds.width + 2, height: bounds.height + 2)
        let outside = triangles.filter { !padded.contains($0) }
        #expect(outside.isEmpty, "the \(name) ring's fill put \(outside.count) vertices outside its box")
    }

    /// The same rings through the two calls the window took them through, a clip and a
    /// fill, in a headless frame: the frame renders.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFoldedRingDrawsAndClips() throws {
        let image = try OllinApp.image(of: FoldedRingProbe(), frame: 1)
        #expect(image.width == 256 && image.height == 256)
    }

    // MARK: The cleaning

    @Test
    func pointsOnTopOfEachOtherMerge() {
        // Every corner three times: exact twice, then a hair off, and the ring closed
        // back onto its first point.
        let corners = [Point2D(0, 0), Point2D(100, 0), Point2D(100, 100), Point2D(0, 100)]
        var ring: [Point2D] = []
        for c in corners { ring += [c, c, Point2D(c.x + 1e-9, c.y - 1e-9)] }
        ring.append(corners[0])
        ring.append(Point2D(1e-9, 1e-9))
        let cleaned = FillExpander.cleaned([ring], epsilon: FillExpander.cleaningEpsilon(for: [ring]))
        #expect(cleaned.count == 1)
        #expect(cleaned.first?.count == 4, "the square cleaned to \(cleaned.first?.count ?? 0) points")
        #expect(cleaned.first?.first == corners[0])
    }

    @Test
    func anOrdinaryRingIsUntouched() {
        let square = [Point2D(10, 10), Point2D(90, 10), Point2D(90, 90), Point2D(10, 90)]
        let cleaned = FillExpander.cleaned([square], epsilon: FillExpander.cleaningEpsilon(for: [square]))
        #expect(cleaned == [square])
        let fill = FillExpander.triangulate([square], nonZero: false)
        #expect(fill.count == 6)
        #expect(abs(Self.area(fill) - 6400) < 1e-6)
    }

    @Test
    func aRingAlongALineIsNothing() {
        let line = (0..<12).map { Point2D(Double($0) * 7, Double($0) * 3) } + [Point2D(40, 17.142857142857142)]
        let cleaned = FillExpander.cleaned([line], epsilon: FillExpander.cleaningEpsilon(for: [line]))
        #expect(cleaned.isEmpty, "a ring along a line cleaned to \(cleaned.count) rings")
        #expect(FillExpander.triangulate([line], nonZero: false).isEmpty)
        let twoPoints = [Point2D(0, 0), Point2D(5, 5), Point2D(0, 0), Point2D(5, 5)]
        #expect(FillExpander.cleaned([twoPoints], epsilon: 1e-6).isEmpty)
    }

    @Test
    func aFigureEightIsKeptWhole() {
        // A bow tie: signed area zero, two lobes of 2,500 each under the even-odd rule.
        let bow = [Point2D(0, 0), Point2D(100, 100), Point2D(100, 0), Point2D(0, 100)]
        let cleaned = FillExpander.cleaned([bow], epsilon: FillExpander.cleaningEpsilon(for: [bow]))
        #expect(cleaned == [bow])
        let fill = FillExpander.triangulate([bow], nonZero: false)
        #expect(abs(Self.area(fill) - 5000) < 1e-6, "the bow tie filled \(Self.area(fill))")
    }

    @Test
    func theMergingDistanceFollowsTheCoordinatesScale() {
        // A millionth of the largest coordinate: at a thousand, points a ten-millionth
        // apart are one point; at one, points a hundred-thousandth apart are two.
        let far = [Point2D(1000, 1000), Point2D(1000.0000001, 1000), Point2D(1100, 1000), Point2D(1100, 1100)]
        #expect(FillExpander.cleaned([far], epsilon: FillExpander.cleaningEpsilon(for: [far])).first?.count == 3)
        let near = [Point2D(0, 0), Point2D(0.00001, 0), Point2D(1, 0), Point2D(1, 1)]
        #expect(FillExpander.cleaned([near], epsilon: FillExpander.cleaningEpsilon(for: [near])).first?.count == 4)
    }

    private static func area(_ triangles: [Point2D]) -> Double {
        var area = 0.0
        var i = 0
        while i + 2 < triangles.count {
            let a = triangles[i], b = triangles[i + 1], c = triangles[i + 2]
            let abx = b.x - a.x, aby = b.y - a.y
            let acx = c.x - a.x, acy = c.y - a.y
            area += abs(abx * acy - acx * aby) / 2
            i += 3
        }
        return area
    }
}

/// Both folded rings, clipped through and filled, as the live window drew them.
private final class FoldedRingProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        noStroke()
        fill(.black)
        let scale = 256.0 / 1080.0
        for ring in [TessellationRobustnessTests.bundledRing, TessellationRobustnessTests.collapsedRing,
                     TessellationRobustnessTests.bundledRing2] {
            let shape = Shape(curveThrough: ring.map { Vector2($0.x * scale, $0.y * scale) }, closed: true)
            withClip(shape) { drawRect(0, 0, 256, 256) }
            drawShape(shape)
        }
    }
}

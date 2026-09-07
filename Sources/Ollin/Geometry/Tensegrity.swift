import Foundation

/// A tensegrity: a structure of rigid struts that never touch, held in place
/// by a net of cables. The struts push, the cables pull, and the whole thing
/// stands up because every push is balanced by pulls. Kenneth Snelson's
/// sculptures and Buckminster Fuller's masts are the well-known shape.
///
/// A `Tensegrity` is geometry: nodes in space, and two lists of members, each
/// naming two nodes. It knows nothing about weight. Draw one as it is, or hand
/// it to a `World3D` (`addTensegrity`) to let it fall, land, and stand.
///
/// ```swift
/// let prism = Tensegrity.prism(struts: 3, radius: 1, height: 1.6)
/// for strut in prism.struts {
///     let (a, b) = prism.endpoints(of: strut)
///     drawCapsule(from: a, to: b, radius: 0.05)
/// }
/// for cable in prism.cables {
///     let (a, b) = prism.endpoints(of: cable)
///     drawCapsule(from: a, to: b, radius: 0.008)
/// }
/// ```
///
/// Three classic forms come ready-made, each in its balanced shape:
///
/// - `prism(struts:radius:height:)`: the simplest tensegrity, `n` struts between
///   two polygons twisted against each other by the one angle that balances.
/// - `icosahedron(strutLength:)`: the six-strut form, three pairs of parallel
///   struts and twenty-four cables, the shape most people picture.
/// - `tower(levels:struts:radius:levelHeight:)`: prisms stacked into a mast,
///   every level twisting the other way.
///
/// `imbalance` says how far any arrangement is from balance, so a form of your
/// own can be checked before it is built.
public struct Tensegrity: Equatable, Sendable {

    /// A member of the structure: a strut or a cable running between two
    /// nodes, named by their indices into `nodes`.
    public struct Member: Hashable, Sendable {
        /// The index of the node at one end.
        public let a: Int
        /// The index of the node at the other end.
        public let b: Int

        public init(_ a: Int, _ b: Int) {
            self.a = a
            self.b = b
        }
    }

    /// Where the nodes are. A node is the end of one strut (or, in a stacked
    /// form, the meeting point of two) and the anchor of several cables.
    public var nodes: [Vector3]

    /// The rigid members, in compression. In the classic forms no two struts
    /// share a node; a `tower` shares them where its levels meet.
    public var struts: [Member]

    /// The tension members. A cable holds its two nodes no farther apart than
    /// its length and does nothing when they come closer.
    public var cables: [Member]

    /// A structure from its parts. Nothing is checked here; read `imbalance`
    /// to learn whether the arrangement can hold.
    public init(nodes: [Vector3], struts: [Member], cables: [Member]) {
        self.nodes = nodes
        self.struts = struts
        self.cables = cables
    }

    // MARK: Reading it

    /// The two node positions a member runs between.
    public func endpoints(of member: Member) -> (start: Vector3, end: Vector3) {
        (nodes[member.a], nodes[member.b])
    }

    /// How long a member is right now.
    public func length(of member: Member) -> Double {
        nodes[member.a].distance(to: nodes[member.b])
    }

    /// The mean of the node positions.
    public var center: Vector3 {
        guard !nodes.isEmpty else { return .zero }
        var sum = Vector3.zero
        for node in nodes { sum += node }
        return sum * (1 / Double(nodes.count))
    }

    /// The lowest node's height, which is where the structure would stand.
    public var bottom: Double {
        nodes.map(\.y).min() ?? 0
    }

    /// The same structure moved by `offset`.
    public func translated(by offset: Vector3) -> Tensegrity {
        Tensegrity(nodes: nodes.map { $0 + offset }, struts: struts, cables: cables)
    }

    /// The same structure scaled about the origin.
    public func scaled(by factor: Double) -> Tensegrity {
        Tensegrity(nodes: nodes.map { $0 * factor }, struts: struts, cables: cables)
    }

    /// The same structure turned about the origin.
    public func rotated(by rotation: Rotation3D) -> Tensegrity {
        Tensegrity(nodes: nodes.map { $0.rotated(by: rotation) }, struts: struts, cables: cables)
    }

    // MARK: The classic forms

    /// The twist that balances a regular prism of `n` struts: a quarter turn
    /// less the half angle of the polygon, `π/2 − π/n`. Thirty degrees for
    /// three struts, forty-five for four, sixty for six. It does not depend on
    /// the prism's height or radius.
    public static func prismTwist(struts n: Int) -> Double {
        .pi / 2 - .pi / Double(max(n, 3))
    }

    /// The simplest tensegrity: `n` struts standing between two regular
    /// polygons of `radius`, the top one raised by `height` and turned against
    /// the bottom by `twist`. Each strut runs from a bottom node to the top
    /// node one step around, and three cables hold each node: two along its
    /// polygon and one to the top node straight above it.
    ///
    /// The default twist is the balanced one, `prismTwist(struts:)`. Any other
    /// twist is a shape that cannot hold its cables taut, which `imbalance`
    /// reports and a `World3D` shows by letting it fold.
    public static func prism(struts n: Int = 3, radius: Double = 1, height: Double = 1.5,
                             twist: Double? = nil) -> Tensegrity {
        let n = max(n, 3)
        let twist = twist ?? prismTwist(struts: n)
        var nodes: [Vector3] = []
        nodes.reserveCapacity(2 * n)
        for i in 0 ..< n {
            let angle = Double(i) / Double(n) * .tau
            nodes.append(Vector3(radius * cos(angle), 0, radius * sin(angle)))
        }
        for i in 0 ..< n {
            let angle = Double(i) / Double(n) * .tau + twist
            nodes.append(Vector3(radius * cos(angle), height, radius * sin(angle)))
        }
        var struts: [Member] = []
        var cables: [Member] = []
        for i in 0 ..< n {
            let next = (i + 1) % n
            struts.append(Member(i, n + next))          // bottom i to top i+1
            cables.append(Member(i, next))              // the bottom polygon
            cables.append(Member(n + i, n + next))      // the top polygon
            cables.append(Member(i, n + i))             // the riser
        }
        return Tensegrity(nodes: nodes, struts: struts, cables: cables)
    }

    /// The six-strut tensegrity: three pairs of parallel struts, one pair
    /// along each axis, held by twenty-four cables that form eight triangles.
    /// Its balanced shape puts each pair half a strut's length apart, which
    /// places the twelve nodes on Jessen's icosahedron. Centered on the origin.
    public static func icosahedron(strutLength: Double = 2) -> Tensegrity {
        // Jessen's icosahedron at strut length 4: every cyclic permutation of
        // (±2, ±1, 0). The struts are the six edges of length 4, the cables the
        // twenty-four of length √6.
        var nodes: [Vector3] = []
        for axis in 0 ..< 3 {
            for along in [-1.0, 1.0] {
                for across in [-1.0, 1.0] {
                    var c = [0.0, 0.0, 0.0]
                    c[axis] = 2 * along
                    c[(axis + 1) % 3] = across
                    nodes.append(Vector3(c[0], c[1], c[2]))
                }
            }
        }
        var struts: [Member] = []
        var cables: [Member] = []
        for i in 0 ..< nodes.count {
            for j in (i + 1) ..< nodes.count {
                let d2 = nodes[i].distanceSquared(to: nodes[j])
                if abs(d2 - 16) < 1e-9 {
                    struts.append(Member(i, j))
                } else if abs(d2 - 6) < 1e-9 {
                    cables.append(Member(i, j))
                }
            }
        }
        let scale = strutLength / 4
        return Tensegrity(nodes: nodes.map { $0 * scale }, struts: struts, cables: cables)
    }

    /// A mast: `levels` prisms stacked on shared polygons, each level twisted
    /// the opposite way from the one below so the mast does not wind up. Two
    /// struts meet at every shared node, so unlike the other forms this one is
    /// not strut-free at its joints; each shared polygon's cables carry the
    /// load of both levels. The bottom polygon sits at height zero.
    public static func tower(levels: Int = 3, struts n: Int = 3, radius: Double = 1,
                             levelHeight: Double = 1.4) -> Tensegrity {
        let n = max(n, 3)
        let levels = max(levels, 1)
        let twist = prismTwist(struts: n)
        var nodes: [Vector3] = []
        var struts: [Member] = []
        var cables: [Member] = []

        // Polygon k sits at height k * levelHeight; its turn accumulates the
        // alternating twists below it.
        var turn = 0.0
        for level in 0 ... levels {
            for i in 0 ..< n {
                let angle = Double(i) / Double(n) * .tau + turn
                nodes.append(Vector3(radius * cos(angle), Double(level) * levelHeight,
                                     radius * sin(angle)))
            }
            if level < levels {
                turn += level.isMultiple(of: 2) ? twist : -twist
            }
        }
        for level in 0 ... levels {
            let base = level * n
            for i in 0 ..< n {
                cables.append(Member(base + i, base + (i + 1) % n))
            }
        }
        for level in 0 ..< levels {
            let lower = level * n
            let upper = (level + 1) * n
            let clockwise = level.isMultiple(of: 2)
            for i in 0 ..< n {
                // A level twisted one way sends its struts one step around;
                // the level above, twisted back, sends them the other way.
                let step = clockwise ? (i + 1) % n : (i + n - 1) % n
                struts.append(Member(lower + i, upper + step))
                cables.append(Member(lower + i, upper + i))
            }
        }
        return Tensegrity(nodes: nodes, struts: struts, cables: cables)
    }

    // MARK: Balance

    /// How far from balance the structure is: the largest leftover force at
    /// any node, as a fraction of the mean cable pull, after the cable and
    /// strut forces that fit the geometry best are found. Zero means every
    /// node is in equilibrium; a `prism` at its `prismTwist` reads near zero
    /// and one at the wrong twist does not.
    ///
    /// The fit gives every strut the same compression and finds the cable
    /// tensions (least squares, tensions free to differ) that cancel it best.
    /// It is a diagnostic; the built-in forms are balanced by construction.
    public var imbalance: Double {
        guard !cables.isEmpty, !struts.isEmpty else { return 0 }
        // Unknowns: one tension per cable. Each node gives three equations:
        // Σ t_c û_c(toward the other end) + Σ (−1) û_s(toward the other end) = 0,
        // with the strut force density fixed at 1 in compression (pushing the
        // node away from the strut's other end).
        let m = cables.count
        var ata = [Double](repeating: 0, count: m * m)
        var atb = [Double](repeating: 0, count: m)
        var pushes = [Vector3](repeating: .zero, count: nodes.count)
        for strut in struts {
            let span = nodes[strut.b] - nodes[strut.a]
            // Compression pushes each end away from the other.
            pushes[strut.a] -= span
            pushes[strut.b] += span
        }
        // Rows are (node, axis); columns are cables. Build AᵀA and Aᵀb node
        // by node, since each node touches only its own cables.
        var incident = [[Int]](repeating: [], count: nodes.count)
        for (index, cable) in cables.enumerated() {
            incident[cable.a].append(index)
            incident[cable.b].append(index)
        }
        func pullDirection(_ cable: Member, at node: Int) -> Vector3 {
            let other = cable.a == node ? cable.b : cable.a
            return nodes[other] - nodes[node]
        }
        for node in nodes.indices {
            let list = incident[node]
            let target = pushes[node] * -1   // cables must cancel the push
            for (p, ci) in list.enumerated() {
                let ui = pullDirection(cables[ci], at: node)
                atb[ci] += ui.dot(target)
                for cj in list[p...] {
                    let uj = pullDirection(cables[cj], at: node)
                    let value = ui.dot(uj)
                    ata[ci * m + cj] += value
                    if ci != cj { ata[cj * m + ci] += value }
                }
            }
        }
        // Solve the normal equations, ridge-regularized so a slack or
        // redundant cable does not make the system singular.
        let ridge = 1e-9 * (ata.max() ?? 1)
        for i in 0 ..< m { ata[i * m + i] += ridge }
        let tensions = Tensegrity.solve(ata, atb, size: m)
        // Residual per node, against the mean cable pull.
        var meanPull = 0.0
        var worst = 0.0
        var residuals = [Vector3](repeating: .zero, count: nodes.count)
        for (index, cable) in cables.enumerated() {
            let pull = (nodes[cable.b] - nodes[cable.a]) * tensions[index]
            residuals[cable.a] += pull
            residuals[cable.b] -= pull
            meanPull += pull.length
        }
        meanPull /= Double(m)
        for node in nodes.indices {
            worst = max(worst, (residuals[node] + pushes[node]).length)
        }
        return meanPull > 0 ? worst / meanPull : worst
    }

    /// Gaussian elimination with partial pivoting on a dense `size × size`
    /// system stored row-major.
    static func solve(_ matrix: [Double], _ rhs: [Double], size n: Int) -> [Double] {
        var a = matrix
        var b = rhs
        for col in 0 ..< n {
            var pivot = col
            for row in (col + 1) ..< n where abs(a[row * n + col]) > abs(a[pivot * n + col]) {
                pivot = row
            }
            if pivot != col {
                for k in 0 ..< n { a.swapAt(col * n + k, pivot * n + k) }
                b.swapAt(col, pivot)
            }
            let diagonal = a[col * n + col]
            guard abs(diagonal) > 1e-300 else { continue }
            for row in (col + 1) ..< n {
                let factor = a[row * n + col] / diagonal
                guard factor != 0 else { continue }
                for k in col ..< n { a[row * n + k] -= factor * a[col * n + k] }
                b[row] -= factor * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1) ..< n { sum -= a[row * n + k] * x[k] }
            let diagonal = a[row * n + row]
            x[row] = abs(diagonal) > 1e-300 ? sum / diagonal : 0
        }
        return x
    }
}

public extension Sketch {

    /// Draw a tensegrity where its nodes are: every strut as a capsule of
    /// `strutRadius` and every cable as a thin capsule of `cableRadius`, all in
    /// the current fill and material. A sketch that wants the two in different
    /// colors loops `struts` and `cables` itself with `endpoints(of:)`.
    ///
    /// ```swift
    /// fill(.white)
    /// drawTensegrity(Tensegrity.icosahedron(strutLength: 2))
    /// ```
    func drawTensegrity(_ structure: Tensegrity, strutRadius: Double = 0.04,
                        cableRadius: Double = 0.008) {
        for strut in structure.struts {
            let (a, b) = structure.endpoints(of: strut)
            drawCapsule(from: a, to: b, radius: strutRadius)
        }
        for cable in structure.cables {
            let (a, b) = structure.endpoints(of: cable)
            drawCapsule(from: a, to: b, radius: cableRadius, segments: 8, rings: 3)
        }
    }
}

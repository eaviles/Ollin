import Foundation

/// The order a frame's layers are filled in.
///
/// A layer is filled after every layer it reads: a drawn layer after the layers
/// whose pictures its block draws, a filter after its input, a combine after
/// both of its layers. The order a sketch opened its blocks in decides nothing
/// but ties, so a layer opened first can draw the image of one opened after it
/// and show this frame's picture.
///
/// Among layers free to go, the order is by kind (generated patterns, ocean
/// fields, plain layers, feedback layers, accumulators, simulation fields,
/// then filters and combines) and, within a kind, the order the frame recorded
/// them in. A frame in which no layer reads a later one is filled in exactly
/// that order.
///
/// Layers that read each other have no order that satisfies both. The one that
/// comes first by the rule above is then filled before what it reads is ready
/// (`early`), and shows that layer as it stood before this frame: a frame late
/// for a layer the sketch keeps, empty for one made this frame. A loop is what
/// `Feedback.previous` is for, and reading it waits on nothing.
struct LayerSchedule {
    /// Every layer the renderer fills this frame, each after the layers it reads.
    var order: [RenderTarget] = []
    /// The layers filled before a layer they read was ready, in fill order.
    var early: [RenderTarget] = []
    /// The plain layers the frame reads and never opened a block on. They are in
    /// `order` too, and are filled empty: a layer holds what this frame drew
    /// into it, and this frame drew nothing.
    var unopened: [RenderTarget] = []

    var isEmpty: Bool { order.isEmpty }

    /// One sentence for the sketch's author about the first layer filled early.
    var earlyNote: String? {
        guard let first = early.first else { return nil }
        return "Two layers draw each other's picture in one frame, so one of them is drawn before the other is ready: \(first.fillDescription) is drawn first here, and shows the other as it stood before this frame (a frame late for a layer the sketch keeps, empty for one made this frame). To carry a picture from one frame to the next on purpose, read a feedback layer's `previous`."
    }
}

extension RenderTarget {
    /// Where this layer's kind falls among layers that are free to be filled.
    var fillRank: Int {
        switch origin {
        case .generator: return 0
        case .ocean: return 1
        case .geometry: return 2
        case .feedback: return 3
        case .accumulate: return 4
        case .simField: return 5
        case .filter, .combine: return 6
        }
    }

    /// What a note calls this layer.
    var fillDescription: String {
        let size = "\(width) by \(height)"
        switch origin {
        case .generator: return "a generated pattern (\(size))"
        case .ocean: return "an ocean field"
        case .geometry: return "a plain layer (\(size))"
        case .feedback: return "a feedback layer (\(size))"
        case .accumulate: return "an accumulator (\(size))"
        case .simField: return "a simulation field (\(size))"
        case .filter: return "a filter's result (\(size))"
        case .combine: return "a combine's result (\(size))"
        }
    }
}

extension MeshMaterial {
    /// Adds the layers this material reads as maps to `found`.
    func appendLayerPictures(to found: inout [RenderTarget]) {
        if let layer = texture?.layerTarget { found.append(layer) }
        if let layer = normalTexture?.layerTarget { found.append(layer) }
        if let layer = metallicRoughnessTexture?.layerTarget { found.append(layer) }
        if let layer = occlusionTexture?.layerTarget { found.append(layer) }
        if let layer = emissiveTexture?.layerTarget { found.append(layer) }
        if let layer = heightTexture?.layerTarget { found.append(layer) }
        if let layer = detailTexture?.layerTarget { found.append(layer) }
        if let layer = detailNormalTexture?.layerTarget { found.append(layer) }
    }

    /// Whether any of this material's maps is a layer's picture.
    var readsLayerPictures: Bool {
        var found: [RenderTarget] = []
        appendLayerPictures(to: &found)
        return !found.isEmpty
    }
}

extension GeometryBatch {
    /// The layers this run reads as pictures: the image it draws, the depth it
    /// is placed by, a mesh's picture, matcap, and maps.
    var layerPictures: [RenderTarget] {
        var found: [RenderTarget] = []
        if let layer = image?.layerTarget { found.append(layer) }
        if let layer = depthImage?.layerTarget { found.append(layer) }
        if let layer = matcap?.layerTarget { found.append(layer) }
        if let layer = picture?.layerTarget { found.append(layer) }
        material?.appendLayerPictures(to: &found)
        return found
    }
}

extension Drawer {
    /// Whether the frame has any layer to fill or to read, which is what there
    /// has to be before a fill order means anything. False for a frame that
    /// only draws on the canvas, which then never walks its runs.
    var hasLayerWork: Bool {
        !renderTargets.isEmpty || !filterOps.isEmpty || readsLayerPictures
    }

    /// The order this frame's layers are filled in (see `LayerSchedule`).
    func layerSchedule() -> LayerSchedule {
        guard hasLayerWork else { return LayerSchedule() }
        var nodes = renderTargets + filterOps
        var index: [ObjectIdentifier: Int] = [:]
        for (i, node) in nodes.enumerated() { index[ObjectIdentifier(node)] = i }

        // What each surface's runs read. A run handed to no surface by a wipe
        // reads nothing; the canvas's runs matter only for the layers they read
        // that the frame never opened. Every read is also kept in the order the
        // frame recorded it, which is the order unopened layers join in: a
        // dictionary's own order changes from one run of the program to the next.
        var pictures: [ObjectIdentifier: [RenderTarget]] = [:]
        var readsAsRecorded: [RenderTarget] = []
        for batch in batches where batch.target !== wipedRuns {
            let read = batch.layerPictures
            guard !read.isEmpty else { continue }
            readsAsRecorded.append(contentsOf: read)
            if let target = batch.target {
                pictures[ObjectIdentifier(target), default: []].append(contentsOf: read)
            }
        }
        func fieldInputs(of node: RenderTarget) -> [RenderTarget] {
            guard case let .simField(owner) = node.origin, let field = owner.layer else { return [] }
            return (field.modulation.map { [$0] } ?? []) + field.inputs
        }

        // A plain layer something reads and no block opened is filled empty.
        // Its clear color is a frame before's, since no block reset it.
        var unopened: [RenderTarget] = []
        func noteUnopened(_ read: RenderTarget) {
            // A layer's depth is read through its carrier, and stands for the layer.
            let layer = read.carrierOf ?? read
            guard layer.isPlainLayer, index[ObjectIdentifier(layer)] == nil else { return }
            layer.clearColor = .clear
            index[ObjectIdentifier(layer)] = nodes.count
            nodes.append(layer)
            unopened.append(layer)
        }
        for read in readsAsRecorded { noteUnopened(read) }
        for node in renderTargets + filterOps { for read in node.opInputs { noteUnopened(read) } }

        // The layer that fills what a read names: the layer itself, or the one
        // a carrier belongs to. A feedback layer's last frame has none, since it
        // is ready before the frame starts.
        var filler = index
        for (i, node) in nodes.enumerated() {
            if let depth = node.depthLayer { filler[ObjectIdentifier(depth)] = i }
            if let normals = node.normalLayer { filler[ObjectIdentifier(normals)] = i }
            if case let .accumulate(owner) = node.origin, let accumulator = owner.layer {
                filler[ObjectIdentifier(accumulator.meanLayer)] = i
                filler[ObjectIdentifier(accumulator.sumLayer)] = i
            }
        }

        var waitsOn = [[Int]](repeating: [], count: nodes.count)
        for (i, node) in nodes.enumerated() {
            var reads = node.opInputs + (pictures[ObjectIdentifier(node)] ?? [])
            // A field reads its modulation map and its kernel's extra layers
            // this frame when they are drawn layers; a filter's result among
            // them is read as the frame before left it, by the field's own
            // rule, so it is nothing to wait on.
            reads += fieldInputs(of: node).filter { read in
                filler[ObjectIdentifier(read)].map { nodes[$0].fillRank < 6 } ?? false
            }
            for read in reads {
                guard let from = filler[ObjectIdentifier(read)], from != i,
                      !waitsOn[i].contains(from) else { continue }
                waitsOn[i].append(from)
            }
        }

        // Lowest rank first among the layers with nothing left to wait on, the
        // recorded order within a rank; when every layer left waits on another,
        // the lowest of them goes early.
        let ranked = nodes.indices.sorted {
            (nodes[$0].fillRank, $0) < (nodes[$1].fillRank, $1)
        }
        var filled = [Bool](repeating: false, count: nodes.count)
        var schedule = LayerSchedule(unopened: unopened)
        schedule.order.reserveCapacity(nodes.count)
        while schedule.order.count < nodes.count {
            let ready = ranked.first { i in !filled[i] && waitsOn[i].allSatisfy { filled[$0] } }
            let next = ready ?? ranked.first { !filled[$0] }!
            if ready == nil { schedule.early.append(nodes[next]) }
            filled[next] = true
            schedule.order.append(nodes[next])
        }
        return schedule
    }
}

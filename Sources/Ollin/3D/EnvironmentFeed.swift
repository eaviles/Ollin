import Foundation

extension Environment {

    /// An environment lit by a live picture: the camera, a playing video, a screen
    /// capture, any `VideoFeed`. The feed's latest frame is wrapped around the
    /// scene and baked into the image-based lighting, so a chrome sphere reflects
    /// the room and a white one picks up its color, refreshing as new frames arrive:
    ///
    /// ```swift
    /// let camera = Camera()
    ///
    /// func draw() {
    ///     environment(.feed(camera))
    ///     material(.polishedMetal)
    ///     drawSphere(radius: 1)
    /// }
    /// ```
    ///
    /// The frame covers the half of the surroundings the camera sees; the unseen
    /// half is its mirror image, so the wrap is seamless and every direction has
    /// plausible light. A feed frame carries no highlights brighter than white,
    /// so the look is the soft, believable kind, not a sun-lit one.
    ///
    /// The feed lights the scene but does not draw as the backdrop (the wrap is
    /// made for lighting and reflections, not for viewing): draw the frame
    /// yourself (`drawFrame(camera)`) and place the lit objects over it. Until
    /// the first frame arrives, a neutral sky lights the scene. `intensity(_:)`
    /// and `rotated(_:)` apply as on any environment.
    @MainActor
    public static func feed(_ feed: some VideoFeed) -> Environment {
        Environment(source: .feed(id: FeedEnvironments.register(feed)),
                    showsBackground: false)
    }
}

/// The live feeds behind `.feed` environments. `Environment` is a value
/// (Equatable / Hashable / Sendable), so its source carries only a number; this
/// registry maps that number back to the `VideoFeed` object when the renderer
/// resolves the frame's environment. Held weakly, so an environment value never
/// keeps a camera running by itself.
@MainActor
enum FeedEnvironments {

    private struct WeakFeed { weak var feed: (any VideoFeed)? }

    private static var feeds: [Int: WeakFeed] = [:]
    private static var ids: [ObjectIdentifier: Int] = [:]
    private static var nextID = 1

    /// The stable id for a feed, assigning one on first sight. Called every frame
    /// (environments are built inside `draw()`), so the repeat path is two lookups.
    static func register(_ feed: any VideoFeed) -> Int {
        let oid = ObjectIdentifier(feed)
        if let id = ids[oid], let held = feeds[id]?.feed, ObjectIdentifier(held) == oid {
            return id
        }
        // Reap rows whose feed has deallocated before assigning: a freed object's
        // identity can be reused by a new one, and a stale row would then hand the
        // new feed the old id.
        for (id, box) in feeds where box.feed == nil { feeds[id] = nil }
        ids = ids.filter { key, id in
            feeds[id]?.feed.map { ObjectIdentifier($0) == key } ?? false
        }
        let id = nextID
        nextID += 1
        feeds[id] = WeakFeed(feed: feed)
        ids[oid] = id
        return id
    }

    /// The feed registered under `id`, or nil once it has deallocated.
    static func feed(for id: Int) -> (any VideoFeed)? { feeds[id]?.feed }
}

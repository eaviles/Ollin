import Ollin

/// A dozen jelly blobs tumble into a pile. Each blob is a cloud of particles that
/// remembers its rest shape: every frame it finds the rotation that best maps that
/// shape onto wherever its particles are now, and each particle steers back toward its
/// spot in it. That one pull is the whole elasticity model, so the blobs squash on
/// impact, wobble, and recover, and nothing can make them explode.
///
/// Drag to grab a blob and knead the pile. `squish` is the single stiffness dial (low
/// is jelly, high is rubber); each `variation` scatters a fresh pile.
@main
final class SoftBodies_Example: Sketch {
    var blobs: SoftBodies!

    @Param(0.05 ... 0.95, icon: "circle.grid.cross") var squish = 0.3
    @Param(0.0 ... 0.9, icon: "arrow.uturn.down") var bounce = 0.35

    override func setup() {
        blobs = makeSoftBodies(bodies: 12, radius: 84)
    }

    override func draw() {
        blobs.squish = squish
        blobs.bounce = bounce

        background(Color(white: 0.04))
        if mouseIsPressed { blobs.pull(at: mouse) }
        updateSoftBodies(blobs)
        drawParticles(blobs)

        drawCaption("Soft bodies · shape-matched jelly · drag to knead the pile")
    }
}

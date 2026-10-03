/// How a line drawn through the 3D camera measures its `strokeWeight`. It is
/// stated with the weight, `strokeWeight(0.05, in: .world)`, and every weight set
/// without one is in `.screen` units, so a unit never outlives the number it was
/// set with: a weight a few points wide never turns into one a few world units
/// wide on the next frame. Saved by `withState` with the weight.
///
/// The default, `.screen`, reads the weight in canvas points, the unit a 2D
/// stroke uses: a line two points wide is two points wide near the camera and
/// far from it, the way a pen line on a drawing of a scene would be. `.world`
/// reads it in the scene's own units instead, so a line a tenth of a unit wide
/// thins as it recedes and thickens as it comes closer, like a thin rod would,
/// and a 3D `scale` widens it with everything else.
///
/// It applies only to lines drawn with 3D points (`drawLine` and `drawPolyline`
/// over `Vector3`, and the helpers built on them). A 2D stroke reads the weight
/// in the drawing's own units, which `scale` widens, whichever unit is named.
public enum StrokeUnits: Sendable, CaseIterable {
    /// Canvas points on the picture, the same at every distance. The default.
    case screen
    /// Units of the scene, so the line shrinks with distance.
    case world
}

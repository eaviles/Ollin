/// How `drawImage` reads a picture's pixels when it draws the picture larger
/// than it is.
///
/// A picture drawn bigger than its own pixels has to say what lies between two
/// of them. `.linear`, the default, blends neighbors, so a photograph enlarged
/// a little stays smooth. `.nearest` keeps every pixel a hard square, which is
/// what pixel art, a low-resolution canvas, and a photo dithered to two levels
/// want when drawn at several canvas pixels a cell: the cells read as cells,
/// and no enlarged copy is made on the CPU. Set it with `imageSampling(_:)`,
/// drawing state beside `tint` that `withState { }` saves and restores.
public enum ImageSampling: Hashable, Sendable, CaseIterable {
    /// Blend the neighboring pixels (the default): a picture drawn larger than
    /// its pixels is smooth, each cell fading into the next.
    case linear
    /// Keep each pixel a hard square where the picture is drawn larger than
    /// its pixels. A picture drawn *smaller* than its pixels is still blended,
    /// since reading one pixel of many under reduction aliases into sparkle;
    /// the choice applies only where the picture is enlarged.
    case nearest
}

// What `import Ollin` brings into a sketch's scope beyond Ollin's own API.
//
// CoreGraphics is re-exported so a sketch that writes only `import Ollin` can
// call the standard math functions (`sin`, `cos`, `sqrt`, …) and name Core
// Graphics value types (`CGFloat`/`CGPoint`/`CGRect`/`CGSize`) without a second
// import — the bare-call "just write `sin(time)`" ergonomic. The canvas size is
// its own `CanvasSize` type now, so it's the math functions (not `CGSize`) that
// make this load-bearing: drop it and the examples stop compiling on `sin`.
@_exported import CoreGraphics

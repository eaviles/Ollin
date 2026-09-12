// The names Chapter 16's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

// The layers the filter tour keeps reaching for. Each is a render target the
// prose has already drawn into, which is why the fragments only filter it.
// They are declared rather than made, because `makeRenderTarget()` is an
// instance method and a property initializer runs before `self` exists.
var art: RenderTarget!
var marks: RenderTarget!
var plate: RenderTarget!
var scene: RenderTarget!
var page: RenderTarget!
var wall: RenderTarget!
var horizon: RenderTarget!
var field: RenderTarget!
// `layer` is the chapter's stand-in for "a layer you have". It is also
// `Sketch.layer { }`, the compose DSL, so it has to be declared here or the
// fragments resolve to the function.
var layer: RenderTarget!
var trail: Feedback!
let lamps: [Vector2] = [.zero, Vector2(40, 40)]
var mask: RenderTarget!
let ink = Color.black
let outline = Shape([Vector2(0, 0), Vector2(40, 0), Vector2(20, 40)])
var myShader: Shader!

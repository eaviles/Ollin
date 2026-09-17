// The names Chapter 19's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

// Each grid the chapter holds and steps. They are made in `setup()`, so the
// chapter declares them optional and so does this.
var life: SimField!
var dish: SimField!
var land: SimField!
var medium: SimField!
var field: SimField!
var plate: SimField!

// The two kernels the section on a rule of one's own names around its fragment.
let heatStep = Shader("float4 shade(float2 uv, ShaderInfo info) { return cell(info); }")
let addHeat = Shader("float4 shade(float2 uv, ShaderInfo info) { return cell(info) + mark(info).a; }")

#ifndef COLLINSHADERS_H
#define COLLINSHADERS_H

// Bridge target: exposes the shared CPU/GPU shader-type header to Swift as an
// importable C module.
//
// The canonical header lives beside the shader segments (in the Ollin target's
// Renderer/ directory) so it ships as a runtime resource the renderer can
// splice into the shader source. SwiftPM won't let a resource live outside its
// target, and won't let two targets' directories overlap, so this thin module
// reaches the single source-of-truth file by relative path rather than keeping
// a second copy. See Sources/Ollin/Renderer/OllinShaderTypes.h.
#include "../../Ollin/Renderer/OllinShaderTypes.h"

#endif /* COLLINSHADERS_H */

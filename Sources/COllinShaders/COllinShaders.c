// SwiftPM needs at least one compiled source for the target; the module's
// contents are entirely in COllinShaders.h (which re-includes the shared
// shader-type header). Including it here also validates that it compiles as C.
#include "COllinShaders.h"

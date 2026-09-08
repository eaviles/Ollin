# The public surface, written down

One file per library product, one line per public declaration: the types with their conformances, then every member with its modifiers, labels, types, defaults, and deprecation, nested as the source nests them and sorted within each level. `Scripts/api-surface.sh` writes them from the build through the toolchain's `swift-api-digester` and, run without `--record`, fails when a listing and the build disagree. `Scripts/preflight.sh` runs that check whenever the framework changed.

The listings exist so that a change to the public API is a deliberate one. Add, rename, or remove something public and the check fails until `Scripts/api-surface.sh --record` rewrites the listing, at which point the diff under `API/` says exactly what changed, in review, beside the change that made it. Before 1.0 that is all the check asks. From 1.0 on, every public rename ships a deprecation shim, and a removed line here with no `@available(deprecated)` line beside it is the failure the shim rule exists to catch. The last naming sweep before that tag reads these files rather than the tree.

The listings are generated. Do not edit them by hand; change the source and record. Their spelling follows the compiler that built the module, so they are recorded and checked on the development toolchain rather than on CI, whose Swift may lag.

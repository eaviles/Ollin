#!/bin/zsh
#
# Scripts/guide-figures.sh: render every Guide figure to Guide/Images.
#
#   Scripts/guide-figures.sh                  # all figures, fail on any error
#   Scripts/guide-figures.sh --only Swarm     # just figures matching "Swarm"
#
# Compiles each Guide/Figures/**/*.swift through the sketch loader and renders
# its committed image (PNG, or GIF via a `// figure: gif` directive). This is
# the Guide's verification gate: run it before committing anything under
# Guide/. Exits nonzero if any figure fails to compile or render. Conventions
# live in Guide/AUTHORING.md.

cd "$(dirname "$0")/.." || exit 1
exec swift run OllinGuideFigures "$@"

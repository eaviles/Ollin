#!/bin/zsh
#
# Scripts/guide-figures.sh: render every figure to its committed image.
#
#   Scripts/guide-figures.sh                  # all figures, fail on any error
#   Scripts/guide-figures.sh --only Swarm     # just figures matching "Swarm"
#
# Compiles each figure sketch through the sketch loader and renders its
# committed image (PNG, or GIF via a `// figure: gif` directive). The chapter
# figures live in Guide/Figures/, rendered to Guide/Images/; the reference
# pages' own set lives in Docs/Figures/, rendered to Docs/Images/ and keyed
# with a Docs/ prefix. This is the verification gate for both trees: run it
# before committing anything under Guide/ or the Docs figures. Exits nonzero
# if any figure fails to compile or render. Conventions live in
# Guide/AUTHORING.md.

cd "$(dirname "$0")/.." || exit 1
exec swift run OllinGuideFigures "$@"

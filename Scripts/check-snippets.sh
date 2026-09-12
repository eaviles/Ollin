#!/bin/zsh
#
# Scripts/check-snippets.sh: compile the code in the Guide's prose, and resolve
# the names it points at.
#
#   Scripts/check-snippets.sh                       # every Guide page
#   Scripts/check-snippets.sh --only 02-Color       # one chapter
#   Scripts/check-snippets.sh Guide/05-Noise.md     # named pages
#   Scripts/check-snippets.sh --record              # rewrite the known-gaps list
#   Scripts/check-snippets.sh --skips               # what is passed over, and why
#
# The other gates verify that a page can be reached and reads well. None of them
# opens a code block, which is how chapter 1 shipped with a radius wrong by a
# factor of a thousand and chapter 2 with an example folder that does not exist.
#
# Every Swift block is wrapped by shape (a whole file compiles as written, a
# fragment gets a sketch built around it, members and statements are separated)
# and typechecked against the framework through the sketch loader. Most
# fragments cannot compile alone, correctly so, and those are recorded in
# Guide/Snippets/known-gaps.txt with the error each gives; the gate fails on a
# *change*, which is what turns a public rename into a failure here. It also
# resolves `ollin docs Page#section` commands and the example names written as
# prose beside an Examples/ link.
#
# About 35 seconds for the whole Guide on the M2, across the cores.
# Conventions live in Guide/AUTHORING.md, "The code in the prose".

cd "$(dirname "$0")/.." || exit 1
exec swift run OllinGuideSnippets "$@"

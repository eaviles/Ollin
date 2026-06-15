#!/bin/sh
# Apply SwiftFormat's safe-hygiene rules (see .swiftformat) across the repo.
#
# Only the allowlisted rules in .swiftformat run — trailing whitespace, final
# newline, consecutive blank lines, redundant parens/return, and inside-bracket
# spacing — so this never reformats Ollin's hand-tuned layout. Run it to fix what
# the pre-commit hook flags.
set -e
cd "$(git rev-parse --show-toplevel)"

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "SwiftFormat not installed. Install it with: brew install swiftformat"
  exit 1
fi

swiftformat .

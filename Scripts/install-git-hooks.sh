#!/bin/sh
# Install Ollin's git hooks. Symlinks Scripts/pre-commit into .git/hooks so the
# committed script stays the single source of truth (edits propagate). Run once
# after cloning. Needs SwiftFormat + SwiftLint for the checks to do anything:
#   brew install swiftformat swiftlint
set -e
root=$(git rev-parse --show-toplevel)
chmod +x "$root/Scripts/pre-commit"
ln -sf ../../Scripts/pre-commit "$root/.git/hooks/pre-commit"
echo "Installed pre-commit hook (-> Scripts/pre-commit)."

#!/bin/zsh
#
# Scripts/prose-lint.sh: lint the reader-facing prose (Guide + Docs) with Vale.
#
#   Scripts/prose-lint.sh                    # the Guide chapters and every Docs page
#   Scripts/prose-lint.sh Guide/05-Noise.md  # specific files (vale args pass through)
#
# Errors exit nonzero and block a commit; warnings are judgment prompts: fix
# them, or keep them on purpose. The rules are the checkable subset of
# Guide/AUTHORING.md's voice rules (.vale.ini + .vale/styles/OllinGuide), plus
# the Google developer-docs word list. First run: brew install vale; the
# Google package is fetched on demand.

cd "$(dirname "$0")/.." || exit 1
command -v vale >/dev/null 2>&1 || { echo "vale is not installed (brew install vale)" >&2; exit 1; }
[ -d .vale/styles/Google ] || vale sync
if [ $# -gt 0 ]; then
    exec vale "$@"
fi
exec vale Guide/README.md Guide/[0-9]*.md Guide/[A-D]-*.md Docs

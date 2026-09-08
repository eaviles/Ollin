#!/bin/zsh
#
# Scripts/logo.sh: the logo's files, from the masters.
#
#   Scripts/logo.sh    # clean both masters in place, then write the dark twin
#
# The masters are Logo/ollin-mark.svg (the full mark) and Logo/ollin-favicon.svg
# (the small form), drawn in Sketch and exported over the files here. An
# export carries what a page never needs: an XML prolog, a title, editor ids,
# a pixel size, a written-out black fill, a translate on the group, and seven
# decimals on every coordinate. This script runs SVGO over both, in place,
# with one settled configuration: the default preset plus the title, any
# description, and the size removed, five decimals kept (three moves edges
# visibly at 1024 px; five is pixel-identical), and the layout left readable
# so the file can still be edited by hand. Running it on a clean master
# changes nothing.
#
# It then writes Logo/ollin-mark-dark.svg, the full mark in the site's paper,
# for the README on GitHub, where the picture is an image and cannot take the
# page's color. The website never reads the twin: it inlines the masters with
# their ink as currentColor and draws the favicon on a tile itself
# (Sources/OllinReference/SiteLogo.swift, whose `paper` this script repeats).
# SiteTests checks the committed twin against the master and the masters for
# an export's leftovers, so a re-export that skips this script fails there.
#
# SVGO leaves a group's translate alone when the group holds a circle (it
# rewrites path data, never cx/cy). The script refuses a master that keeps a
# transform rather than committing one half baked; move the offset into the
# coordinates by hand and run it again.

set -e
set -u

root=${0:A:h:h}
cd "$root"

if ! command -v npx >/dev/null 2>&1; then
    echo "logo.sh: npx (Node) is needed to run SVGO" >&2
    exit 1
fi

config=$(mktemp -t ollin-logo.XXXXXX).mjs
trap 'rm -f "$config"' EXIT
cat > "$config" <<'EOF'
export default {
  multipass: true,
  floatPrecision: 5,
  js2svg: { pretty: true, indent: 2 },
  plugins: [
    'preset-default',
    'removeTitle',
    { name: 'removeDesc', params: { removeAny: true } },
    'removeDimensions',
  ],
};
EOF

for master in Logo/ollin-mark.svg Logo/ollin-favicon.svg; do
    if [[ ! -f $master ]]; then
        echo "logo.sh: $master is not in the checkout" >&2
        exit 1
    fi
    before=$(wc -c < "$master" | tr -d ' ')
    npx --yes svgo --config "$config" -i "$master" -o "$master" >/dev/null
    if grep -q 'transform=' "$master"; then
        echo "logo.sh: $master keeps a transform SVGO could not bake (a translate on a group with a circle in it); move it into the coordinates by hand and run again" >&2
        exit 1
    fi
    after=$(wc -c < "$master" | tr -d ' ')
    if [[ $before == $after ]]; then
        echo "$master: clean ($after bytes)"
    else
        echo "$master: cleaned, $before -> $after bytes"
    fi
done

# The twin: the master with the paper set on its root, which every shape
# inherits. SiteLogo.colored writes the same bytes.
paper='#F4F3F0'
sed "1s|^<svg \(.*\)>\$|<svg \1 fill=\"$paper\">|" Logo/ollin-mark.svg > Logo/ollin-mark-dark.svg
if ! head -1 Logo/ollin-mark-dark.svg | grep -q "fill=\"$paper\""; then
    echo "logo.sh: Logo/ollin-mark.svg does not open with an <svg> tag on one line" >&2
    exit 1
fi
echo "Logo/ollin-mark-dark.svg: written from Logo/ollin-mark.svg in $paper"

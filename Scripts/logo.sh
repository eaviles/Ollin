#!/bin/zsh
#
# Scripts/logo.sh: the logo's files, from the masters.
#
#   Scripts/logo.sh    # clean both masters in place, then write the files made from them
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
# (Sources/OllinReference/SiteLogo.swift, whose `paper` and `ink` this script
# repeats). SiteTests checks the committed twin against the master and the
# masters for an export's leftovers, so a re-export that skips this script
# fails there.
#
# Last it writes the two bitmaps the site cannot make from the masters at
# build time: Logo/ollin-social.png (1200 by 630, the card a link to the site
# unfurls as in a message or a feed) and Logo/ollin-touch.png (180 by 180, the
# icon a phone puts on its home screen), both the full mark in paper centered
# on an ink tile, rasterized by AppKit from the twin. The site copies them in
# as assets/social.png and apple-touch-icon.png.
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

# The bitmaps: the twin drawn on an ink tile at the two sizes. AppKit reads
# an SVG as an image, so no other tool is needed; the source is compiled once
# per run into a temp binary (the interpreter would do, but a compiled run
# is faster and its errors are clearer).
ink='#0B0F14'
raster=$(mktemp -d -t ollin-logo-raster.XXXXXX)
trap 'rm -f "$config"; rm -rf "$raster"' EXIT
cat > "$raster/raster.swift" <<'EOF'
import AppKit

// raster <svg> <png> <width> <height> <mark side> <tile hex>
let args = CommandLine.arguments
guard args.count == 7, let width = Int(args[3]), let height = Int(args[4]), let side = Double(args[5]),
      let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("raster: bad arguments\n".data(using: .utf8)!)
    exit(2)
}
let hex = args[6].dropFirst()
let value = UInt32(hex, radix: 16) ?? 0
let tile = NSColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: 1)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
tile.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
let box = NSRect(x: (Double(width) - side) / 2, y: (Double(height) - side) / 2, width: side, height: side)
image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
           hints: [.interpolation: NSImageInterpolation.high])
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(3) }
try! png.write(to: URL(fileURLWithPath: args[2]))
EOF
xcrun swiftc -O -o "$raster/raster" "$raster/raster.swift"
"$raster/raster" Logo/ollin-mark-dark.svg Logo/ollin-social.png 1200 630 360 "$ink"
echo "Logo/ollin-social.png: the mark in $paper on $ink, 1200 by 630"
"$raster/raster" Logo/ollin-mark-dark.svg Logo/ollin-touch.png 180 180 126 "$ink"
echo "Logo/ollin-touch.png: the mark in $paper on $ink, 180 by 180"

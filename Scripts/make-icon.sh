#!/bin/bash
#
# Renders Resources/AppIcon.icns from code — a rounded square in Kant's accent
# red (#ba0527) with a white "K". Reproducible, no design tool needed.
# Drop a real AppIcon.icns into Resources/ to override.
#
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="Resources"
TMP="$(mktemp -d)"
BASE="${TMP}/icon_1024.png"
ICONSET="${TMP}/AppIcon.iconset"
mkdir -p "${OUT_DIR}" "${ICONSET}"

echo "▶ Rendering base 1024×1024…"
RENDER_SWIFT="${TMP}/render.swift"
cat > "${RENDER_SWIFT}" <<'SWIFT'
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let radius = size * 0.22
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// Accent gradient (top a touch lighter than bottom).
let top = NSColor(red: 0xd0/255.0, green: 0x10/255.0, blue: 0x33/255.0, alpha: 1)
let bottom = NSColor(red: 0xba/255.0, green: 0x05/255.0, blue: 0x27/255.0, alpha: 1)
NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)

// Centered white "K".
let font = NSFont.systemFont(ofSize: size * 0.62, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let letter = "K" as NSString
let textSize = letter.size(withAttributes: attrs)
let point = NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2)
letter.draw(at: point, withAttributes: attrs)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

swift "${RENDER_SWIFT}" "${BASE}"

echo "▶ Generating iconset sizes…"
gen() { sips -z "$2" "$2" "${BASE}" --out "${ICONSET}/$1" >/dev/null; }
gen icon_16x16.png 16
gen icon_16x16@2x.png 32
gen icon_32x32.png 32
gen icon_32x32@2x.png 64
gen icon_128x128.png 128
gen icon_128x128@2x.png 256
gen icon_256x256.png 256
gen icon_256x256@2x.png 512
gen icon_512x512.png 512
cp "${BASE}" "${ICONSET}/icon_512x512@2x.png"

echo "▶ Building ${OUT_DIR}/AppIcon.icns…"
iconutil -c icns "${ICONSET}" -o "${OUT_DIR}/AppIcon.icns"

rm -rf "${TMP}"
echo "✓ Wrote ${OUT_DIR}/AppIcon.icns"

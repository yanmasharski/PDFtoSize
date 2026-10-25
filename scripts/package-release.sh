#!/bin/zsh
# Builds the app and packs it into dist/PDFtoSize.zip (plus a .sha256 file) for a GitHub release.
# The file name has no version on purpose: install.sh downloads releases/latest/download/PDFtoSize.zip.
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/PDFtoSize.app/Contents/Info.plist)"
mkdir -p dist
rm -f dist/PDFtoSize.zip dist/PDFtoSize.zip.sha256
# ditto keeps the code signature and extended attributes; plain zip can break them.
ditto -c -k --keepParent build/PDFtoSize.app dist/PDFtoSize.zip
(cd dist && shasum -a 256 PDFtoSize.zip > PDFtoSize.zip.sha256)
printf 'Packed version %s: dist/PDFtoSize.zip (%s)\n' "$VERSION" "$(du -h dist/PDFtoSize.zip | cut -f1)"

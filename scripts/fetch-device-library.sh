#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
archive=MobileGhost/idevice/libidevice_ffi.a
expected=6524066d54ef23e00d46445c04dfc694e180196d54119d718f68434fa225be35
if [ -f "$archive" ] && [ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" = "$expected" ]; then
    echo 'Verified device library is already present.'
    exit 0
fi
temporary=$(mktemp "${TMPDIR:-/tmp}/mobileghost-library.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
curl --fail --location --proto '=https' --tlsv1.2 --retry 2 \
  'https://raw.githubusercontent.com/truongkma/t-location/5e57f815e5958f133dfbaae8252473054adeccf0/TLocation/idevice/libidevice_ffi.a' \
  --output "$temporary"
actual=$(shasum -a 256 "$temporary" | cut -d ' ' -f 1)
if [ "$actual" != "$expected" ]; then
    echo 'Device library checksum mismatch; refusing to install.' >&2
    exit 1
fi
mv "$temporary" "$archive"
echo 'Device library downloaded and verified.'

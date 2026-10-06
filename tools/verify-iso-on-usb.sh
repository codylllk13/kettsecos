#!/bin/bash
# Read back exactly the ISO image length and compare it byte for byte.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: sudo $0 ISO_PATH /dev/USB_DISK" >&2
  exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "Root access is required to read the USB disk." >&2
  exit 1
fi

ISO_PATH="$(realpath -- "$1")"
TARGET="$(realpath -- "$2")"
[ -s "$ISO_PATH" ] || { echo "Missing or empty ISO: $ISO_PATH" >&2; exit 1; }
[ -b "$TARGET" ] || { echo "Not a block device: $TARGET" >&2; exit 1; }

ISO_BYTES="$(stat -c '%s' -- "$ISO_PATH")"
BLOCK_BYTES=4194304
BLOCK_COUNT=$(((ISO_BYTES + BLOCK_BYTES - 1) / BLOCK_BYTES))
VERIFY_PATH="$(mktemp)"
trap 'rm -f -- "$VERIFY_PATH"' EXIT

echo "Reading back $ISO_BYTES bytes from $TARGET..."
dd if="$TARGET" of="$VERIFY_PATH" bs=4M count="$BLOCK_COUNT" \
  iflag=fullblock status=progress
cmp -n "$ISO_BYTES" -- "$ISO_PATH" "$VERIFY_PATH"
echo "Full image read-back matched ($ISO_BYTES bytes)."

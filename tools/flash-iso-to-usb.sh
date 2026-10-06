#!/bin/bash
# Flash one built AegisOS ISO to an explicitly named removable USB disk.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: sudo $0 ISO_PATH /dev/USB_DISK" >&2
  exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "Root access is required to write the USB disk." >&2
  exit 1
fi

ISO_PATH="$(realpath -- "$1")"
TARGET="$(realpath -- "$2")"
SCRIPT_DIR="$(dirname -- "$(realpath -- "$0")")"
[ -s "$ISO_PATH" ] || { echo "Missing or empty ISO: $ISO_PATH" >&2; exit 1; }
[ -b "$TARGET" ] || { echo "Not a block device: $TARGET" >&2; exit 1; }
xorriso -indev "$ISO_PATH" -toc >/dev/null

device_value() {
  lsblk -dn -o "$1" "$TARGET" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}
USB_MODEL="$(device_value MODEL)"
USB_SIZE="$(device_value SIZE)"
USB_SERIAL="$(device_value SERIAL)"
USB_TRAN="$(device_value TRAN)"
USB_RM="$(device_value RM)"
USB_TYPE="$(device_value TYPE)"

if [ "$USB_TRAN" != usb ] || [ "$USB_RM" != 1 ] || [ "$USB_TYPE" != disk ] ||
   [ -z "$USB_MODEL" ] || [ -z "$USB_SERIAL" ]; then
  echo "The target must be an identified removable USB disk." >&2
  exit 1
fi
if [ -n "$(lsblk -nr -o MOUNTPOINTS "$TARGET" | sed '/^[[:space:]]*$/d')" ]; then
  echo "The USB or one of its partitions is mounted." >&2
  exit 1
fi

EXPECTED="ERASE $TARGET $USB_MODEL $USB_SIZE $USB_SERIAL"
echo "ISO: $ISO_PATH"
echo "USB: $TARGET | $USB_MODEL | $USB_SIZE | $USB_SERIAL"
echo "SHA256: $(sha256sum "$ISO_PATH" | cut -d ' ' -f1)"
echo "This will replace every partition and file on the USB disk."
read -r -p "Type exactly '$EXPECTED' to continue: " CONFIRM
[ "$CONFIRM" = "$EXPECTED" ] || { echo "Confirmation did not match; nothing was written." >&2; exit 1; }

# Device names can change. Recheck all identifiers and mount state before dd.
if [ "$(device_value MODEL)" != "$USB_MODEL" ] ||
   [ "$(device_value SIZE)" != "$USB_SIZE" ] ||
   [ "$(device_value SERIAL)" != "$USB_SERIAL" ] ||
   [ "$(device_value TRAN)" != usb ] ||
   [ "$(device_value RM)" != 1 ] ||
   [ "$(device_value TYPE)" != disk ] ||
   [ -n "$(lsblk -nr -o MOUNTPOINTS "$TARGET" | sed '/^[[:space:]]*$/d')" ]; then
  echo "USB identity or mount state changed; refusing to write." >&2
  exit 1
fi

dd if="$ISO_PATH" of="$TARGET" bs=4M status=progress conv=fsync
sync
"$SCRIPT_DIR/verify-iso-on-usb.sh" "$ISO_PATH" "$TARGET"

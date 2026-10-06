#!/usr/bin/env bash
# Flash a KettsecOS ISO and create an isolated live-boot persistence partition.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: sudo tools/prepare-persistent-usb.sh ISO_PATH /dev/USB_DISK [encrypted|plain]

The whole USB disk will be erased. The default is a LUKS2-encrypted
persistence partition. Use "plain" only when unencrypted persistence is
intended. The script requires the operator to type the displayed device
model, serial number, and byte capacity before it writes anything.
EOF
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit 2
fi

ISO_PATH="$(realpath -- "$1")"
DEVICE="$(realpath -- "$2")"
MODE="${3:-encrypted}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with local administrator access, for example sudo $0 ISO /dev/sdX." >&2
  exit 1
fi
if [ ! -t 0 ]; then
  echo "Run from a terminal so the device and encryption confirmations are interactive." >&2
  exit 1
fi
if [ ! -s "$ISO_PATH" ] || [ ! -b "$DEVICE" ]; then
  echo "The ISO must exist and the target must be a block device." >&2
  exit 1
fi
case "$MODE" in
  encrypted|plain) ;;
  *) usage; exit 2 ;;
esac
if [ "$MODE" = encrypted ] && ! command -v cryptsetup >/dev/null 2>&1; then
  echo "Missing host dependency: cryptsetup. Install cryptsetup-bin before preparing encrypted persistence." >&2
  exit 1
fi

DEVICE_TYPE="$(lsblk -dnro TYPE -- "$DEVICE" | tr -d '[:space:]')"
DEVICE_TRANSPORT="$(lsblk -dnro TRAN -- "$DEVICE" | tr -d '[:space:]')"
DEVICE_REMOVABLE="$(lsblk -dnro RM -- "$DEVICE" | tr -d '[:space:]')"
DEVICE_MODEL="$(lsblk -dnro MODEL -- "$DEVICE" | sed 's/[[:space:]]*$//')"
DEVICE_SERIAL="$(lsblk -dnro SERIAL -- "$DEVICE" | sed 's/[[:space:]]*$//')"
DEVICE_BYTES="$(blockdev --getsize64 "$DEVICE")"
ISO_BYTES="$(stat -c '%s' -- "$ISO_PATH")"

verify_target_identity() {
  local current_type current_transport current_removable current_model current_serial current_bytes
  current_type="$(lsblk -dnro TYPE -- "$DEVICE" | tr -d '[:space:]')"
  current_transport="$(lsblk -dnro TRAN -- "$DEVICE" | tr -d '[:space:]')"
  current_removable="$(lsblk -dnro RM -- "$DEVICE" | tr -d '[:space:]')"
  current_model="$(lsblk -dnro MODEL -- "$DEVICE" | sed 's/[[:space:]]*$//')"
  current_serial="$(lsblk -dnro SERIAL -- "$DEVICE" | sed 's/[[:space:]]*$//')"
  current_bytes="$(blockdev --getsize64 "$DEVICE")"
  if [ "$current_type" != disk ] || [ "$current_transport" != usb ] \
    || [ "$current_removable" != 1 ] || [ "$current_model" != "$DEVICE_MODEL" ] \
    || [ "$current_serial" != "$DEVICE_SERIAL" ] || [ "$current_bytes" != "$DEVICE_BYTES" ]; then
    echo "The target's model, serial, transport or capacity changed; refusing to continue." >&2
    exit 1
  fi
  if lsblk -nrpo MOUNTPOINTS -- "$DEVICE" | grep -q '[^[:space:]]'; then
    echo "A filesystem on the USB became mounted; refusing to continue." >&2
    exit 1
  fi
}

unmount_target_filesystems() {
  local partition mount_path
  while read -r partition; do
    while IFS= read -r mount_path; do
      [ -n "$mount_path" ] || continue
      umount -- "$mount_path"
    done < <(findmnt --source "$partition" --output TARGET --raw --noheadings)
  done < <(lsblk -nrpo PATH,TYPE -- "$DEVICE" | awk '$2 == "part" { print $1 }')
}

unmount_formatted_filesystem() {
  local mount_path
  while IFS= read -r mount_path; do
    [ -n "$mount_path" ] || continue
    umount -- "$mount_path"
  done < <(findmnt --source "$FORMAT_DEVICE" --output TARGET --raw --noheadings)
}

if [ "$DEVICE_TYPE" != disk ] || [ "$DEVICE_TRANSPORT" != usb ] || [ "$DEVICE_REMOVABLE" != 1 ]; then
  echo "Refusing target: it must be a removable USB disk." >&2
  exit 1
fi
if [ -z "$DEVICE_MODEL" ] || [ -z "$DEVICE_SERIAL" ]; then
  echo "Refusing target: model and serial number must be available." >&2
  exit 1
fi
if lsblk -nrpo MOUNTPOINTS -- "$DEVICE" | grep -q '[^[:space:]]'; then
  echo "Unmount every filesystem on the USB before continuing." >&2
  exit 1
fi

SECTOR_SIZE="$(blockdev --getss "$DEVICE")"
DEVICE_SECTORS="$(blockdev --getsz "$DEVICE")"
ISO_SECTORS=$(((ISO_BYTES + 511) / 512))
ALIGN_SECTORS=2048
PERSIST_START=$((((ISO_SECTORS + ALIGN_SECTORS - 1) / ALIGN_SECTORS) * ALIGN_SECTORS))
PERSIST_SECTORS=$((DEVICE_SECTORS - PERSIST_START))
MIN_PERSIST_SECTORS=$((8 * 1024 * 1024 * 1024 / 512))

if [ "$SECTOR_SIZE" -ne 512 ] || [ "$PERSIST_SECTORS" -lt "$MIN_PERSIST_SECTORS" ]; then
  echo "The USB must use 512-byte sectors and leave at least 8 GiB for persistence." >&2
  exit 1
fi

ELTORITO_REPORT="$(mktemp)"
trap 'rm -f -- "$ELTORITO_REPORT"' EXIT
xorriso -indev "$ISO_PATH" -report_el_torito plain >"$ELTORITO_REPORT" 2>&1
grep -Eq 'El Torito boot img.*BIOS' "$ELTORITO_REPORT"
grep -Eq 'El Torito boot img.*UEFI' "$ELTORITO_REPORT"

printf 'ISO: %s (%s bytes)\nTarget: %s\nModel: %s\nSerial: %s\nCapacity: %s bytes\nPersistence: %s, %s bytes\n' \
  "$ISO_PATH" "$ISO_BYTES" "$DEVICE" "$DEVICE_MODEL" "$DEVICE_SERIAL" \
  "$DEVICE_BYTES" "$MODE" "$((PERSIST_SECTORS * 512))"
printf 'This erases all data on the entire USB. Type exactly:\nERASE %s %s %s\n> ' \
  "$DEVICE_MODEL" "$DEVICE_SERIAL" "$DEVICE_BYTES"
IFS= read -r CONFIRMATION
if [ "$CONFIRMATION" != "ERASE $DEVICE_MODEL $DEVICE_SERIAL $DEVICE_BYTES" ]; then
  echo "Confirmation did not match; no changes were made." >&2
  exit 1
fi
verify_target_identity

echo "Writing the boot image (this may take several minutes)..."
dd if="$ISO_PATH" of="$DEVICE" bs=4M conv=fsync status=progress
unmount_target_filesystems
verify_target_identity

# Parrot's hybrid ISO exposes its ISO9660 and EFI partitions through the MBR.
# Append a third MBR partition in the unused USB capacity without touching the
# boot code or the ISO's first two partition entries.
verify_target_identity
sfdisk --append "$DEVICE" <<EOF
start=$PERSIST_START, size=$PERSIST_SECTORS, type=83
EOF
blockdev --rereadpt "$DEVICE"
udevadm settle
unmount_target_filesystems
verify_target_identity
PERSIST_PART="$(lsblk -nrpo PATH,PARTN -- "$DEVICE" | awk '$2 == 3 { print $1; exit }')"
if [ -z "$PERSIST_PART" ] || [ ! -b "$PERSIST_PART" ]; then
  echo "The persistence partition was not detected. The ISO is written, but persistence is not ready." >&2
  exit 1
fi

MAPPER_NAME="kettsecos-persistence"
MOUNT_DIR="$(mktemp -d /run/kettsecos-persistence.XXXXXX)"
MAPPER_OPEN=0
cleanup() {
  if mountpoint -q "$MOUNT_DIR"; then
    umount "$MOUNT_DIR" || true
  fi
  if [ "$MAPPER_OPEN" -eq 1 ]; then
    cryptsetup close "$MAPPER_NAME" || true
  fi
  rmdir "$MOUNT_DIR" 2>/dev/null || true
  rm -f -- "$ELTORITO_REPORT"
}
trap cleanup EXIT

if [ "$MODE" = encrypted ]; then
  echo "Create a new LUKS2 passphrase for this USB. It is never stored by this script."
  verify_target_identity
  cryptsetup luksFormat --type luks2 --label persistence "$PERSIST_PART"
  cryptsetup open "$PERSIST_PART" "$MAPPER_NAME"
  MAPPER_OPEN=1
  FORMAT_DEVICE="/dev/mapper/$MAPPER_NAME"
else
  FORMAT_DEVICE="$PERSIST_PART"
fi

verify_target_identity
mkfs.ext4 -F -m 0 -L persistence "$FORMAT_DEVICE"
unmount_target_filesystems
unmount_formatted_filesystem
mount "$FORMAT_DEVICE" "$MOUNT_DIR"
printf '# KettsecOS live root overlay persistence\n/ union\n' > "$MOUNT_DIR/persistence.conf"
chmod 0644 "$MOUNT_DIR/persistence.conf"
sync -f "$MOUNT_DIR/persistence.conf"
umount "$MOUNT_DIR"
if [ "$MAPPER_OPEN" -eq 1 ]; then
  cryptsetup close "$MAPPER_NAME"
  MAPPER_OPEN=0
fi
sync
echo "Persistent USB is ready. Boot the advanced KettsecOS encrypted or unencrypted persistence entry."

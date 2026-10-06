#!/bin/bash
# Customize an official Ubuntu preinstalled ARM64 image (Raspberry Pi).
# ARM boards don't use ISOs — you ship a flashable .img.xz instead.
#
# Usage:  sudo ./build-pi-image.sh ubuntu-24.04-preinstalled-server-arm64+raspi.img.xz
# Get the base image from: https://cdimage.ubuntu.com/releases/  (raspi images)
#
# Host dependencies:
#   sudo apt install qemu-user-static binfmt-support xz-utils

set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)."; exit 1; }
[ $# -eq 1 ] || { echo "Usage: $0 <ubuntu-preinstalled-arm64+raspi.img.xz>"; exit 1; }

BASE_XZ="$1"
mkdir -p "$WORK_DIR" "$OUT_DIR"
IMG="$WORK_DIR/custom.img"
MNT="$WORK_DIR/pi-root"

echo "Decompressing base image..."
xz -dkc "$BASE_XZ" > "$IMG"

# Grow image by 2G to make room for extra packages
truncate -s +2G "$IMG"

LOOP=$(losetup --find --show --partscan "$IMG")
cleanup() {
  umount -lf "$MNT/boot/firmware" 2>/dev/null || true
  for m in dev/pts dev proc sys run; do umount -lf "$MNT/$m" 2>/dev/null || true; done
  umount -lf "$MNT" 2>/dev/null || true
  losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

# Grow rootfs partition (p2) into the new space
echo ", +" | sfdisk -N 2 "$LOOP"
partprobe "$LOOP"
e2fsck -fy "${LOOP}p2"
resize2fs "${LOOP}p2"

mkdir -p "$MNT"
mount "${LOOP}p2" "$MNT"
mount "${LOOP}p1" "$MNT/boot/firmware"

# Cross-arch chroot via qemu (not needed if your host is arm64)
if [ "$(uname -m)" != "aarch64" ]; then
  cp /usr/bin/qemu-aarch64-static "$MNT/usr/bin/"
fi

mount --bind /dev  "$MNT/dev"
mount --bind /run  "$MNT/run"
mount -t proc proc "$MNT/proc"
mount -t sysfs sysfs "$MNT/sys"
mount -t devpts devpts "$MNT/dev/pts"
cp /etc/resolv.conf "$MNT/etc/resolv.conf"

echo "$TARGET_HOSTNAME" > "$MNT/etc/hostname"

chroot "$MNT" /bin/bash -e <<EOF
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y $EXTRA_PACKAGES
# --- Your Pi-specific customization here ---
apt-get autoremove -y && apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

rm -f "$MNT/usr/bin/qemu-aarch64-static"
cleanup
trap - EXIT

OUT_IMG="$OUT_DIR/${DISTRO_NAME,,}-${DISTRO_VERSION}-arm64+raspi.img"
mv "$IMG" "$OUT_IMG"
echo "Compressing..."
xz -T0 -f "$OUT_IMG"

echo
echo "Done: ${OUT_IMG}.xz"
echo "Flash with Raspberry Pi Imager or: xzcat ${OUT_IMG}.xz | sudo dd of=/dev/sdX bs=4M status=progress"

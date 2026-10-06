#!/bin/bash
# Build a live, bootable x86_64 Ubuntu-based ISO (BIOS + UEFI hybrid).
# Run on an Ubuntu/Debian host (or VM) as root:  sudo ./build-iso.sh
#
# Host dependencies:
#   sudo apt install debootstrap squashfs-tools xorriso grub-pc-bin \
#        grub-efi-amd64-bin mtools dosfstools

set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=config.sh
source ./config.sh

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)."; exit 1; }

mount_binds() {
  mount --bind /dev  "$CHROOT_DIR/dev"
  mount --bind /run  "$CHROOT_DIR/run"
  mount -t proc  proc  "$CHROOT_DIR/proc"
  mount -t sysfs sysfs "$CHROOT_DIR/sys"
  mount -t devpts devpts "$CHROOT_DIR/dev/pts"
}

umount_binds() {
  for m in dev/pts sys proc run dev; do
    umount -lf "$CHROOT_DIR/$m" 2>/dev/null || true
  done
}
trap umount_binds EXIT

# ---------------------------------------------------------------- 1. bootstrap
if [ ! -e "$CHROOT_DIR/etc/os-release" ]; then
  mkdir -p "$CHROOT_DIR"
  debootstrap --arch=amd64 --variant=minbase \
    "$UBUNTU_CODENAME" "$CHROOT_DIR" "$UBUNTU_MIRROR"
fi

# ------------------------------------------------------------- 2. customize
cat > "$CHROOT_DIR/etc/apt/sources.list" <<EOF
deb $UBUNTU_MIRROR $UBUNTU_CODENAME main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_CODENAME-updates main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_CODENAME-security main restricted universe multiverse
EOF

echo "$TARGET_HOSTNAME" > "$CHROOT_DIR/etc/hostname"

cp chroot-customize.sh "$CHROOT_DIR/tmp/"
install -d "$CHROOT_DIR/tmp/aegisos-assets"
cp -a assets/. "$CHROOT_DIR/tmp/aegisos-assets/"
mount_binds
chroot "$CHROOT_DIR" /bin/bash /tmp/chroot-customize.sh \
  "$UBUNTU_CODENAME" \
  "$DISTRO_NAME" \
  "$DISTRO_ID" \
  "$DISTRO_VERSION" \
  "$DISTRO_TAGLINE" \
  "$GTK_THEME" \
  "$WINDOW_THEME" \
  "$ICON_THEME" \
  "$WALLPAPER_PATH" \
  "$PLYMOUTH_THEME" \
  "$DESKTOP_PACKAGES" \
  "$SECURITY_PACKAGES" \
  "$EXTRA_PACKAGES" \
  "$BACKGROUND_PRIMARY" \
  "$BACKGROUND_SECONDARY" \
  "$ACCENT_PRIMARY" \
  "$ACCENT_SECONDARY" \
  "$FOREGROUND_PRIMARY"
umount_binds
rm -f "$CHROOT_DIR/tmp/chroot-customize.sh"

# --------------------------------------------------------------- 3. squashfs
mkdir -p "$IMAGE_DIR"/{casper,boot/grub}

# Kernel + initrd out of the chroot, into the ISO tree
cp "$CHROOT_DIR"/boot/vmlinuz-*    "$IMAGE_DIR/casper/vmlinuz"
cp "$CHROOT_DIR"/boot/initrd.img-* "$IMAGE_DIR/casper/initrd"

rm -f "$IMAGE_DIR/casper/filesystem.squashfs"
mksquashfs "$CHROOT_DIR" "$IMAGE_DIR/casper/filesystem.squashfs" \
  -comp zstd -e boot
printf "%s" "$(du -sx --block-size=1 "$CHROOT_DIR" | cut -f1)" \
  > "$IMAGE_DIR/casper/filesystem.size"

# dpkg-query, not Bash, expands the placeholders in this format string.
# shellcheck disable=SC2016
chroot "$CHROOT_DIR" dpkg-query -W --showformat='${Package} ${Version}\n' \
  > "$IMAGE_DIR/casper/filesystem.manifest"

# ------------------------------------------------------------ 4. bootloader
cat > "$IMAGE_DIR/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=10

menuentry "$DISTRO_NAME $DISTRO_VERSION (live)" {
    linux /casper/vmlinuz boot=casper username=$LIVE_USERNAME quiet splash ---
    initrd /casper/initrd
}
menuentry "$DISTRO_NAME $DISTRO_VERSION (safe graphics)" {
    linux /casper/vmlinuz boot=casper username=$LIVE_USERNAME nomodeset ---
    initrd /casper/initrd
}
menuentry "$DISTRO_NAME $DISTRO_VERSION (forensic mode - no automount or swap)" {
    linux /casper/vmlinuz boot=casper username=$LIVE_USERNAME aegisos.forensic=1 noswap systemd.mask=swap.target rd.systemd.mask=swap.target systemd.gpt_auto=no rd.systemd.gpt_auto=no fsck.mode=skip ---
    initrd /casper/initrd
}
EOF

# ---------------------------------------------------------------- 5. ISO
mkdir -p "$OUT_DIR"
ISO_PATH="$OUT_DIR/${DISTRO_NAME,,}-${DISTRO_VERSION}-amd64.iso"

# grub-mkrescue produces a BIOS+UEFI hybrid ISO in one step
grub-mkrescue -o "$ISO_PATH" "$IMAGE_DIR" -- -volid "$ISO_LABEL"

echo
echo "Done: $ISO_PATH"
echo "Test: qemu-system-x86_64 -m 4G -enable-kvm -cdrom $ISO_PATH"

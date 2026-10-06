#!/bin/bash
# Remaster a pinned, signature-verified Parrot Security Edition ISO.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=config-parrot.sh
source ./config-parrot.sh

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root after fetching the source: python3 tools/fetch-parrot.py" >&2
  exit 1
fi

python3 tools/fetch-parrot.py
python3 tools/fetch-browsers.py
python3 tools/fetch-ai.py
BASE_ISO="cache/parrot/Parrot-security-7.3_amd64.iso"
TOR_BROWSER="cache/browsers/tor-browser-linux-x86_64-15.0.24.tar.xz"
AI_CACHE="cache/ai"
MODEL_CACHE="$AI_CACHE/model"
BUILD_ROOT="$(pwd)/work-parrot"
ISO_TREE="$BUILD_ROOT/iso-tree"
ROOT_TREE="$BUILD_ROOT/root-tree"
OUT_ISO="$(pwd)/out/kettsec-os-${DISTRO_VERSION}-amd64.iso"
BUILD_CPUS="${KETTSEC_BUILD_CPUS:-${KETTCO_BUILD_CPUS:-2}}"
[[ "$BUILD_CPUS" =~ ^[1-9][0-9]*$ ]] || {
  echo "KETTSEC_BUILD_CPUS must be a positive integer" >&2
  exit 2
}
mkdir -p "$BUILD_ROOT" out

if [ ! -e "$BUILD_ROOT/.iso-extracted" ]; then
  rm -rf -- "$ISO_TREE"
  mkdir -p "$ISO_TREE"
  xorriso -osirrox on -indev "$BASE_ISO" -extract / "$ISO_TREE"
  touch "$BUILD_ROOT/.iso-extracted"
fi
test -s "$ISO_TREE/live/filesystem.squashfs"

if [ ! -e "$BUILD_ROOT/.root-extracted" ]; then
  rm -rf -- "$ROOT_TREE"
  unsquashfs -processors "$BUILD_CPUS" -d "$ROOT_TREE" \
    "$ISO_TREE/live/filesystem.squashfs"
  touch "$BUILD_ROOT/.root-extracted"
fi
test -s "$ROOT_TREE/etc/os-release"
install -d "$ROOT_TREE/tmp/aegisos-assets"
cp -a assets/. "$ROOT_TREE/tmp/aegisos-assets/"
install -m0644 sources/mullvad-keyring.asc "$ROOT_TREE/tmp/mullvad-keyring.asc"
install -m0644 "$TOR_BROWSER" "$ROOT_TREE/tmp/tor-browser.tar.xz"
install -m0644 "$AI_CACHE/chatgpt_amd64.deb" "$ROOT_TREE/tmp/chatgpt_amd64.deb"
install -m0644 "$AI_CACHE/codex-linux-x64.tgz" "$ROOT_TREE/tmp/codex-linux-x64.tgz"
install -m0644 "$AI_CACHE/ollama-linux-amd64.tar.zst" "$ROOT_TREE/tmp/ollama-linux-amd64.tar.zst"
# Keep the existing internal Ollama path stable; it is independent of the
# user-facing KettsecOS brand and is referenced by the agent and service.
install -d "$ROOT_TREE/usr/share/kettco/models/blobs"
for model_blob in \
  sha256-62387fdc497bb2f700b9fc2cd81125d89d163c5dc12c14c7e15668fe1f40731f \
  sha256-afb54ad43a39f947407f5cabc59856348d70e072baa5c62d436332157c151bcd \
  sha256-b507b9c2f6ca642bffcd06665ea7c91f235fd32daeefdf875a0f938db05fb315 \
  sha256-7339fa418c9ad3e8e12e74ad0fd26a9cc4be8703f9c110728a992b193be85cb2 \
  sha256-f6417cb1e26962991f8e875a93f3cb0f92bc9b4955e004881251ccbf934a19d2; do
  test -s "$MODEL_CACHE/$model_blob"
  install -m0644 "$MODEL_CACHE/$model_blob" "$ROOT_TREE/usr/share/kettco/models/blobs/$model_blob"
done
install -d "$ROOT_TREE/usr/share/kettco/models/manifests/registry.ollama.ai/huihui_ai/qwen3.5-abliterated"
install -m0644 "$MODEL_CACHE/manifest.json" \
  "$ROOT_TREE/usr/share/kettco/models/manifests/registry.ollama.ai/huihui_ai/qwen3.5-abliterated/9b"
install -m0755 parrot-customize.sh "$ROOT_TREE/tmp/parrot-customize.sh"
# The chroot gets a private tmpfs at /run. Give apt and Flatpak the host's
# upstream DNS servers instead of the 127.0.0.53 stub, which may not be
# reachable from a chroot without the host's resolver service.
if [ -r /run/systemd/resolve/resolv.conf ]; then
  cp /run/systemd/resolve/resolv.conf "$ROOT_TREE/etc/resolv.conf.aegisos-build"
else
  cp -L /etc/resolv.conf "$ROOT_TREE/etc/resolv.conf.aegisos-build"
fi
if grep -Eq '^[[:space:]]*nameserver[[:space:]]+(127\.|::1$)' \
  "$ROOT_TREE/etc/resolv.conf.aegisos-build"; then
  echo "The build host resolver only points to loopback; provide an upstream resolver." >&2
  exit 1
fi
mv -f "$ROOT_TREE/etc/resolv.conf.aegisos-build" "$ROOT_TREE/etc/resolv.conf"

cleanup() {
  for mountpoint in dev/pts sys proc run dev; do
    umount -lf "$ROOT_TREE/$mountpoint" 2>/dev/null || true
  done
}
trap cleanup EXIT
mount --bind /dev "$ROOT_TREE/dev"
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs "$ROOT_TREE/run"
mount --bind /dev/pts "$ROOT_TREE/dev/pts"
mount -t proc proc "$ROOT_TREE/proc"
mount -t sysfs sysfs "$ROOT_TREE/sys"
chroot "$ROOT_TREE" /bin/bash /tmp/parrot-customize.sh "$DISTRO_VERSION"
cleanup
trap - EXIT

# Calamares unpacks this squashfs onto the target disk. Keep /boot in it so
# installed systems receive the kernel and initramfs, as in Parrot's image.
test -s "$ROOT_TREE/boot/vmlinuz-7.0.9+parrot7-amd64"
test -s "$ROOT_TREE/boot/initrd.img-7.0.9+parrot7-amd64"
test -s "$ROOT_TREE/usr/share/plymouth/themes/kettsecos/kettsecos.plymouth"
chroot "$ROOT_TREE" lsinitramfs /boot/initrd.img-7.0.9+parrot7-amd64 \
  > "$BUILD_ROOT/initrd-files.txt"
grep -Fq 'usr/share/plymouth/themes/kettsecos/kettsecos.plymouth' \
  "$BUILD_ROOT/initrd-files.txt"
grep -Fq 'usr/share/plymouth/themes/kettsecos/kettsecos.script' \
  "$BUILD_ROOT/initrd-files.txt"
cp -f "$ROOT_TREE/boot/initrd.img-7.0.9+parrot7-amd64" \
  "$ISO_TREE/live/initrd.img-7.0.9+parrot7-amd64"
rm -f -- "$ISO_TREE/live/filesystem.squashfs.new"
nice -n 10 mksquashfs "$ROOT_TREE" "$ISO_TREE/live/filesystem.squashfs.new" \
  -comp zstd -Xcompression-level 3 -noappend -processors "$BUILD_CPUS"
mv -f -- "$ISO_TREE/live/filesystem.squashfs.new" "$ISO_TREE/live/filesystem.squashfs"
# The format string is interpreted by dpkg-query inside the chroot.
# shellcheck disable=SC2016
chroot "$ROOT_TREE" dpkg-query -W --showformat='${Package}\t${Version}\n' \
  > "$ISO_TREE/live/filesystem.packages"
grep -q '^parrot-tools-full[[:space:]]' "$ISO_TREE/live/filesystem.packages"
for package in kde-plasma-desktop sddm kwin-x11 firefox-esr mullvad-browser \
  mullvad-vpn flatpak grub-pc-bin grub-efi-amd64-bin efibootmgr cryptsetup-initramfs \
  chatgpt; do
  grep -q "^${package}[[:space:]]" "$ISO_TREE/live/filesystem.packages" || {
    echo "Missing required package from image: $package" >&2
    exit 1
  }
done
chroot "$ROOT_TREE" test -x /usr/local/bin/codex
chroot "$ROOT_TREE" test -x /usr/local/bin/ollama
test -s "$ROOT_TREE/usr/share/kettco/models/manifests/registry.ollama.ai/huihui_ai/qwen3.5-abliterated/9b"
test -s "$ROOT_TREE/usr/share/kettco/models/blobs/sha256-afb54ad43a39f947407f5cabc59856348d70e072baa5c62d436332157c151bcd"
grep -Eq 'requiredStorage:[[:space:]]*40' "$ROOT_TREE/etc/calamares/modules/welcome.conf"
test -x "$ROOT_TREE/opt/aegisos/tor-browser/Browser/start-tor-browser"
test -x "$ROOT_TREE/usr/local/bin/aegisos-tor-browser"
test -d "$ROOT_TREE/var/lib/flatpak/app/io.github.ungoogled_software.ungoogled_chromium/x86_64/stable/active"

# Keep legacy Debian live-installer metadata narrow as well. Calamares uses
# its own packages.conf removal list in the installed system.
printf '%s\n' live-boot live-config calamares calamares-settings-parrot \
  > "$ISO_TREE/live/filesystem.packages-remove"

python3 tools/brand-parrot-boot.py "$ISO_TREE" "$DISTRO_VERSION"

rm -f -- "$OUT_ISO"
xorriso -indev "$BASE_ISO" -outdev "$OUT_ISO" \
  -boot_image any replay \
  -volid "$ISO_LABEL" \
  -map "$ISO_TREE/live/filesystem.squashfs" /live/filesystem.squashfs \
  -map "$ISO_TREE/live/filesystem.packages" /live/filesystem.packages \
  -map "$ISO_TREE/live/filesystem.packages-remove" /live/filesystem.packages-remove \
  -map "$ISO_TREE/live/initrd.img-7.0.9+parrot7-amd64" /live/initrd.img-7.0.9+parrot7-amd64 \
  -map "$ISO_TREE/boot/grub/grub.cfg" /boot/grub/grub.cfg \
  -map "$ISO_TREE/boot/grub/live-theme/theme.txt" /boot/grub/live-theme/theme.txt \
  -map "$ISO_TREE/isolinux/menu.cfg" /isolinux/menu.cfg \
  -map "$ISO_TREE/isolinux/live.cfg" /isolinux/live.cfg \
  -commit -end

xorriso -indev "$OUT_ISO" -report_el_torito plain \
  > "$BUILD_ROOT/eltorito-report.txt" 2>&1
grep -Eq 'El Torito boot img.*BIOS' "$BUILD_ROOT/eltorito-report.txt"
grep -Eq 'El Torito boot img.*UEFI' "$BUILD_ROOT/eltorito-report.txt"
echo "Built $OUT_ISO"

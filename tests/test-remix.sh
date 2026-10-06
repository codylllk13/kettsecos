#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config-parrot.sh

fail() { echo "FAIL: $*" >&2; exit 1; }
has() { grep -Fq -- "$2" "$1" || fail "$1 lacks: $2"; }
file() { [ -s "$1" ] || fail "missing or empty: $1"; }

[ "$DISTRO_NAME" = KettsecOS ] || fail "unexpected KettsecOS release name"
[ "$DISTRO_VERSION" = 3.0-preview.3 ] || fail "unexpected KettsecOS release version"
[ "$ISO_LABEL" = KETTSECOS33 ] || fail "unexpected ISO label"
if [ ! -x build-iso.sh ] || [ ! -x build-parrot-iso.sh ]; then
  fail "ISO build entrypoints must be executable"
fi
for p in \
  parrot-customize.sh build-parrot-iso.sh config-parrot.sh \
  tools/fetch-parrot.py tools/fetch-browsers.py tools/brand-parrot-boot.py \
  assets/desktop/kwinrc assets/desktop/aegisos-set-wallpaper \
  assets/branding/kettsecos-logo.svg \
  assets/desktop/aegisos-wallpaper.desktop assets/browser/aegisos-tor-browser \
  assets/browser/aegisos-tor-browser.desktop \
  assets/networking/10-globally-managed-devices.conf \
  assets/agent/aegis-agent assets/agent/aegis_agent/policy.py \
  assets/hardening/aegisos-forensic-mode.sh sources/parrot.json \
  sources/browser-lock.json sources/mullvad-keyring.asc \
  assets/calamares/branding/aegisos/branding.desc \
  assets/calamares/branding/aegisos/show.qml \
  assets/calamares/modules/shellprocess.conf \
  assets/calamares/calamares-3.3.14-disk-confirmation.patch \
  assets/calamares/build-patched-partition.sh \
  tools/prepare-persistent-usb.sh tools/fetch-ai.py sources/ai-lock.json \
  assets/ai/install-ai.sh assets/ai/kettco-ollama.service \
  assets/ai/kettco-local-model.desktop assets/ai/kettco-ai-status; do
  file "$p"
done

has sources/parrot.json '"version": "7.3"'
has sources/parrot.json '"size_bytes": 8555526144'
has sources/browser-lock.json '"version": "15.0.24"'
has sources/browser-lock.json '"mullvad_key_fingerprint": "A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF"'
has sources/browser-lock.json 'io.github.ungoogled_software.ungoogled_chromium'
has assets/desktop/kwinrc 'ButtonsOnRight=IAX'
has parrot-customize.sh 'aegisos-set-wallpaper'
has assets/desktop/kwinrc 'library=org.kde.breeze'
has assets/branding/kettsecos-logo.svg '<title id="title">KettsecOS lllK logo</title>'
has assets/calamares/branding/aegisos/logo.svg 'aria-label="KettsecOS lllK logo"'
has assets/calamares/branding/aegisos/icon.svg 'aria-label="KettsecOS lllK logo"'
has assets/networking/10-globally-managed-devices.conf 'unmanaged-devices='
has assets/calamares/modules/shellprocess.conf 'partitionChoices.install'
has assets/calamares/branding/aegisos/branding.desc 'slideshow: "show.qml"'
has assets/calamares/branding/aegisos/branding.desc 'slideshowAPI: 2'
has assets/calamares/branding/aegisos/branding.desc 'productName: KettsecOS'
has assets/calamares/branding/aegisos/branding.desc 'version: 3.0-preview.3'
has assets/calamares/branding/aegisos/show.qml 'KETTSECOS'
has parrot-customize.sh 'for branding_file in branding.desc logo.svg icon.svg show.qml'
has assets/calamares/modules/partition.conf 'allowManualPartitioning: false'
has assets/calamares/modules/welcome.conf 'requiredStorage: 40'
has assets/calamares/calamares-3.3.14-disk-confirmation.patch 'setCurrentIndex( -1 )'
has assets/calamares/calamares-3.3.14-disk-confirmation.patch 'eraseConfirmationMatches'
has assets/calamares/calamares-3.3.14-disk-confirmation.patch 'DiskIdentityGuardJob'
has assets/calamares/build-patched-partition.sh '3.3.14-1'
has assets/calamares/build-patched-partition.sh 'apt-get source'
has assets/calamares/build-patched-partition.sh 'calamares_viewmodule_partition'
has parrot-customize.sh 'build-patched-partition.sh'
has tools/brand-parrot-boot.py 'persistence-media=removable-usb'
has tools/brand-parrot-boot.py 'persistence-encryption=lukslabel'
has tools/brand-parrot-boot.py 'KettsecOS (persistent storage, encrypted)'
has tools/brand-parrot-boot.py 'KettsecOS (persistent storage, unencrypted)'
has tools/prepare-persistent-usb.sh 'sfdisk --append'
has tools/prepare-persistent-usb.sh 'luksFormat --type luks2 --label persistence'
has tools/prepare-persistent-usb.sh '/ union'
has tools/prepare-persistent-usb.sh 'verify_target_identity'
has tools/prepare-persistent-usb.sh 'unmount_target_filesystems'
has tools/prepare-persistent-usb.sh 'unmount_formatted_filesystem'
has parrot-customize.sh 'parrot-tools-full'
has parrot-customize.sh 'kde-plasma-desktop sddm'
has parrot-customize.sh 'kwin-x11'
has parrot-customize.sh 'systemctl enable --force sddm.service'
has parrot-customize.sh 'sddm shared/default-x-display-manager select sddm'
has parrot-customize.sh 'firefox-esr'
has parrot-customize.sh 'gnome-keyring'
has parrot-customize.sh 'mullvad-browser'
has parrot-customize.sh 'mullvad-vpn'
has parrot-customize.sh 'flatpak'
has parrot-customize.sh 'firmware-realtek'
has parrot-customize.sh 'NetworkManager.service'
has parrot-customize.sh 'systemd-resolved.service'
has parrot-customize.sh 'Theme=kettsecos'
has parrot-customize.sh 'Name=Install KettsecOS'
has parrot-customize.sh 'install-ai.sh'
has assets/ai/install-ai.sh 'chatgpt_amd64.deb'
has assets/ai/install-ai.sh 'codex-linux-x64.tgz'
has assets/ai/install-ai.sh 'qwen3.5-abliterated'
has assets/ai/kettco-ollama.service 'OLLAMA_MODELS=/usr/share/kettco/models'
has assets/ai/kettco-ollama.service 'OLLAMA_NUM_THREADS=2'
has assets/agent/aegis_agent/providers.py 'huihui_ai/qwen3.5-abliterated:9b'
has assets/agent/aegis_agent/providers.py 'AEGIS_LAN_URL'
has build-parrot-iso.sh 'fetch-ai.py'
has build-parrot-iso.sh 'chatgpt_amd64.deb'
has build-parrot-iso.sh 'sha256-afb54ad43a39f947407f5cabc59856348d70e072baa5c62d436332157c151bcd'
has build-parrot-iso.sh 'BIOS'
has build-parrot-iso.sh 'UEFI'
has build-parrot-iso.sh '/run/systemd/resolve/resolv.conf'
has tools/fetch-browsers.py 'VALIDSIG'
has tools/fetch-parrot.py 'VALIDSIG'
has tools/fetch-parrot.py '"--speed-limit", "1024"'
has tools/fetch-parrot.py 'flock(fd, LOCK_EX)'
has assets/agent/aegis_agent/policy.py 'approved'
echo 'PASS: Parrot source verification, toolkit, desktop, networking, browsers, guarded installer, persistent USB workflow, and agent configuration'

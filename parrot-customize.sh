#!/bin/bash
# Customizes the official Parrot Security live filesystem inside the build chroot.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 KETTSECOS_VERSION" >&2
  exit 2
fi

VERSION="$1"
ASSETS=/tmp/aegisos-assets
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

cleanup_policy() { install -d -m0755 /usr/sbin; rm -f /usr/sbin/policy-rc.d; }
trap cleanup_policy EXIT
cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 0755 /usr/sbin/policy-rc.d

# Parrot Security ships Plasma, but make its desktop and display manager an
# explicit dependency so the live and installed systems have working window
# decorations and title-bar controls.
printf '%s\n' 'sddm shared/default-x-display-manager select sddm' | debconf-set-selections

install -Dm0644 /tmp/mullvad-keyring.asc /usr/share/keyrings/mullvad-keyring.asc
chmod 0644 /usr/share/keyrings/mullvad-keyring.asc
cat > /etc/apt/sources.list.d/mullvad.list <<'EOF'
deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=amd64] https://repository.mullvad.net/deb/stable stable main
EOF

if [ "${KETTCO_SKIP_APT:-0}" != 1 ]; then
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates curl flatpak firefox-esr \
    mullvad-browser mullvad-vpn \
    kde-plasma-desktop sddm kwin-x11 kwin-wayland kwin-style-breeze \
    breeze-gtk-theme papirus-icon-theme \
    grub-pc-bin grub-efi-amd64-bin efibootmgr cryptsetup-initramfs \
    gnome-keyring dbus-x11 python3-requests python3-pyqt5 python3-jwt \
    python3-keyring python3-secretstorage \
    wireguard-tools network-manager firmware-realtek ethtool pciutils \
    systemd-resolved \
    aide apparmor apparmor-profiles apparmor-profiles-extra apparmor-utils \
    fail2ban ufw tor usbguard nftables
else
  echo 'Skipping APT refresh and package install; reusing the previously provisioned build tree.'
fi

# Keep Parrot's complete Security Edition metapackage installed for both live
# sessions and Calamares installs. Do not autoremove Parrot security packages.
dpkg-query -W -f='${Status}\n' parrot-tools-full | grep -Fx 'install ok installed'
apt-mark manual parrot-tools-full

# Replace Calamares' partition page with the version-pinned Kettsec disk guard.
# It starts with no disk selected and requires a typed identity match before
# whole-disk erase; an early job verifies the live block device before writes.
"$ASSETS/calamares/build-patched-partition.sh"

# Replace Parrot-facing first-run text with the KettsecOS identity.
installer_desktop=/usr/share/applications/calamares-install-parrot.desktop
if [ -f "$installer_desktop" ]; then
  install -Dm0644 "$ASSETS/calamares/branding/aegisos/icon.svg" \
    /usr/share/icons/hicolor/scalable/apps/kettsecos.svg
  sed -i \
    -e 's/^Name=.*/Name=Install KettsecOS/' \
    -e 's/^GenericName=.*/GenericName=KettsecOS Installer/' \
    -e 's/^Comment=.*/Comment=Install KettsecOS to this computer/' \
    -e 's/^Icon=.*/Icon=kettsecos/' \
    "$installer_desktop"
fi
if [ -f /usr/bin/add-calamares-desktop-icon ]; then
  sed -i \
    -e 's/Name=Install Parrot/Name=Install KettsecOS/' \
    -e 's/Icon=install-parrot/Icon=kettsecos/' \
    /usr/bin/add-calamares-desktop-icon
fi
if [ -f /etc/skel/Desktop/README.license ]; then
  sed -i '1s/Welcome to Parrot OS/Welcome to KettsecOS, based on Parrot Security Edition/' \
    /etc/skel/Desktop/README.license
fi
for firefox_defaults in /etc/firefox/00parrot.js /etc/firefox-esr/00parrot.js; do
  if [ -f "$firefox_defaults" ]; then
    sed -i \
      -e 's#https://start.parrotsec.org/?v=7.1#about:blank#' \
      -e 's#https://www.parrotsec.org/donate#about:blank#' \
      "$firefox_defaults"
  fi
done

# Install Ungoogled Chromium as a system Flatpak, with its upstream Flathub app ID.
flatpak --system remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak --system install --assumeyes --noninteractive flathub io.github.ungoogled_software.ungoogled_chromium
install -Dm0644 "$ASSETS/browser/io.github.ungoogled_software.ungoogled_chromium.desktop" \
  /usr/share/applications/io.github.ungoogled_software.ungoogled_chromium.desktop

# Tor's signed bundle is independently checked by the host-side build script.
install -d /opt/aegisos
tar -xJf /tmp/tor-browser.tar.xz -C /opt/aegisos
test -x /opt/aegisos/tor-browser/Browser/start-tor-browser
chmod -R a+rX,go-w /opt/aegisos/tor-browser
install -Dm0755 "$ASSETS/browser/aegisos-tor-browser" /usr/local/bin/aegisos-tor-browser
install -Dm0644 "$ASSETS/browser/aegisos-tor-browser.desktop" \
  /usr/share/applications/aegisos-tor-browser.desktop

# KWin was absent from the prototype image, leaving applications without
# window decorations and close controls. Install it and set visible controls.
install -Dm0644 "$ASSETS/desktop/kwinrc" /etc/xdg/kwinrc
install -Dm0644 "$ASSETS/desktop/kwinrc" /etc/skel/.config/kwinrc
cat > /etc/xdg/kdeglobals <<'EOF'
[General]
ColorScheme=KettsecMatrix
widgetStyle=Breeze

[Colors:Window]
BackgroundNormal=3,8,5
ForegroundNormal=216,255,224
DecorationFocus=0,255,65
DecorationHover=0,143,17

[Colors:View]
BackgroundNormal=11,27,14
ForegroundNormal=216,255,224
SelectionBackground=0,143,17
SelectionForeground=255,255,255

[Icons]
Theme=Papirus
EOF
install -d /usr/share/color-schemes
cat > /usr/share/color-schemes/KettsecMatrix.colors <<'EOF'
[General]
Name=KettsecMatrix
ColorScheme=KettsecMatrix

[Colors:Window]
BackgroundNormal=3,8,5
ForegroundNormal=216,255,224
DecorationFocus=0,255,65
DecorationHover=0,143,17

[Colors:View]
BackgroundNormal=11,27,14
ForegroundNormal=216,255,224
SelectionBackground=0,143,17
SelectionForeground=255,255,255
EOF
install -Dm0644 /etc/xdg/kdeglobals /etc/skel/.config/kdeglobals

# Use NetworkManager as the only desktop network manager. Do not copy build-host
# connections; Ethernet and Wi-Fi profiles are created by the owner at runtime.
install -Dm0644 "$ASSETS/networking/10-globally-managed-devices.conf" \
  /etc/NetworkManager/conf.d/10-globally-managed-devices.conf
systemctl enable NetworkManager.service
systemctl enable systemd-resolved.service
ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl disable networking.service 2>/dev/null || true

# Reuse Aegis agent, Matrix artwork, Calamares brand and hardening files while
# retaining Parrot's tested live desktop, Calamares modules and package config.
install -d /usr/lib/aegisos-agent/aegis_agent /usr/lib/systemd/user
install -m0644 "$ASSETS/agent/aegis_agent/"*.py /usr/lib/aegisos-agent/aegis_agent/
install -m0755 "$ASSETS/agent/aegis-agent" /usr/bin/aegis-agent
install -m0755 "$ASSETS/agent/aegis-agent-ui" /usr/bin/aegis-agent-ui
install -m0644 "$ASSETS/agent/aegis-agent.service" /usr/lib/systemd/user/aegis-agent.service
install -m0644 "$ASSETS/agent/aegis-agent.desktop" /usr/share/applications/aegis-agent.desktop
systemctl --global enable aegis-agent.service

# Install the pinned native Codex CLI, official ChatGPT Linux preview and the
# bundled offline Qwen3.5 9B model. The installer performs a final digest check;
# account sign-in remains a first-use action for the owner.
"$ASSETS/ai/install-ai.sh"

install -Dm0644 "$ASSETS/branding/aegisos-wallpaper.svg" \
  /usr/share/backgrounds/aegisos/aegisos-wallpaper.svg
sed -i 's/UBUNTU FOUNDATION  \/  KDE PLASMA/PARROT SECURITY  \/  KDE PLASMA/' \
  /usr/share/backgrounds/aegisos/aegisos-wallpaper.svg
sed -i 's/PARROT SECURITY  \/  KDE PLASMA/SECURITY WORKSTATION  \/  KDE PLASMA/' \
  /usr/share/backgrounds/aegisos/aegisos-wallpaper.svg
install -d /usr/share/wallpapers/KettsecOS/contents/images /etc/xdg /etc/skel/.config
install -m0644 /usr/share/backgrounds/aegisos/aegisos-wallpaper.svg \
  /usr/share/wallpapers/KettsecOS/contents/images/1920x1080.svg
cat > /usr/share/wallpapers/KettsecOS/metadata.desktop <<'EOF'
[Desktop Entry]
Name=KettsecOS
X-KDE-PluginInfo-Name=KettsecOS
X-KDE-PluginInfo-Author=KettsecOS contributors
X-KDE-PluginInfo-License=CC0-1.0
X-KDE-PluginInfo-Category=Wallpaper
EOF
install -Dm0755 "$ASSETS/desktop/aegisos-set-wallpaper" \
  /usr/local/bin/aegisos-set-wallpaper
install -Dm0644 "$ASSETS/desktop/aegisos-wallpaper.desktop" \
  /etc/xdg/autostart/aegisos-wallpaper.desktop

for branding_file in branding.desc logo.svg icon.svg show.qml; do
  install -Dm0644 "$ASSETS/calamares/branding/aegisos/$branding_file" \
    "/usr/share/calamares/branding/aegisos/$branding_file"
  install -Dm0644 "$ASSETS/calamares/branding/aegisos/$branding_file" \
    "/etc/calamares/branding/aegisos/$branding_file"
done
install -Dm0644 "$ASSETS/calamares/modules/partition.conf" \
  /etc/calamares/modules/partition.conf
install -Dm0644 "$ASSETS/calamares/modules/welcome.conf" \
  /etc/calamares/modules/welcome.conf
install -Dm0644 "$ASSETS/calamares/modules/bootloader.conf" \
  /etc/calamares/modules/bootloader.conf
install -Dm0644 "$ASSETS/calamares/modules/shellprocess.conf" \
  /etc/calamares/modules/shellprocess.conf
if [ -f /etc/calamares/settings.conf ]; then
  sed -i 's/^branding:.*/branding: aegisos/' /etc/calamares/settings.conf
  # Run the cleanup after the target is configured but before it is unmounted.
  # Parrot ships this module commented out; the live filesystem package list is
  # not used by Calamares' unpackfs installer.
  if ! grep -Eq '^  - shellprocess$' /etc/calamares/settings.conf; then
    settings_tmp=$(mktemp)
    awk '
      /^- exec:$/ { in_exec = 1; print; next }
      /^- show:$/ { in_exec = 0 }
      in_exec && /^  - partition$/ && !inserted {
        print "  - shellprocess"
        inserted = 1
      }
      { print }
      END { if (!inserted) exit 1 }
    ' /etc/calamares/settings.conf > "$settings_tmp"
    mv "$settings_tmp" /etc/calamares/settings.conf
  fi
  if ! grep -Eq '^  - packages$' /etc/calamares/settings.conf; then
    sed -i '/^  - umount$/i\  - packages' /etc/calamares/settings.conf
  fi
else
  echo 'Parrot Calamares settings were not found' >&2
  exit 1
fi
# Keep the full tool meta-package during install. Only remove transient live
# boot and installer packages after unpacking the system.
cat > /etc/calamares/modules/packages.conf <<'EOF'
update_db: false
backend: apt
operations:
  - remove:
      - live-boot
      - live-config
      - live-config-doc
      - live-config-systemd
      - live-tools
      - calamares
      - calamares-settings-parrot
EOF

install -Dm0644 "$ASSETS/hardening/99-aegisos-hardening.conf" \
  /etc/sysctl.d/99-aegisos-hardening.conf
install -Dm0644 "$ASSETS/hardening/60-aegisos-sshd.conf" \
  /etc/ssh/sshd_config.d/60-aegisos-hardening.conf
install -Dm0644 "$ASSETS/hardening/aegisos-fail2ban.local" \
  /etc/fail2ban/jail.d/aegisos.local
install -Dm0644 "$ASSETS/hardening/20auto-upgrades" \
  /etc/apt/apt.conf.d/20auto-upgrades
install -Dm0644 "$ASSETS/hardening/ufw.conf" /etc/ufw/ufw.conf
install -Dm0755 "$ASSETS/hardening/aegisos-privacy.sh" /usr/local/sbin/aegisos-privacy
install -Dm0755 "$ASSETS/hardening/aegisos-forensic-mode.sh" \
  /usr/local/libexec/aegisos-forensic-mode
install -Dm0755 "$ASSETS/hardening/aegisos-aide-init.sh" \
  /usr/local/libexec/aegisos-aide-init
install -Dm0644 "$ASSETS/hardening/aegisos-privacy-routing.service" \
  /etc/systemd/system/aegisos-privacy-routing.service
install -Dm0644 "$ASSETS/hardening/aegisos-forensic-mode.service" \
  /etc/systemd/system/aegisos-forensic-mode.service
install -Dm0644 "$ASSETS/hardening/aegisos-aide-init.service" \
  /etc/systemd/system/aegisos-aide-init.service
install -Dm0644 "$ASSETS/hardening/aegisos-flatpak-update.service" \
  /etc/systemd/system/aegisos-flatpak-update.service
install -Dm0644 "$ASSETS/hardening/aegisos-flatpak-update.timer" \
  /etc/systemd/system/aegisos-flatpak-update.timer
if [ -f /etc/tor/torrc ] && ! grep -Fq 'AegisOS opt-in privacy routing listeners' /etc/tor/torrc; then
  cat "$ASSETS/hardening/aegisos-torrc" >> /etc/tor/torrc
fi
for unit in aegisos-aide-init.service aegisos-forensic-mode.service apparmor.service \
  auditd.service fail2ban.service sddm.service ufw.service; do
  systemctl enable "$unit" 2>/dev/null || true
done
systemctl disable lightdm.service 2>/dev/null || true
systemctl enable --force sddm.service
systemctl enable aegisos-flatpak-update.timer 2>/dev/null || true
systemctl disable ssh.service ssh.socket aegisos-privacy-routing.service \
  tor.service tor@default.service usbguard.service usbguard-dbus.service 2>/dev/null || true

# Replace Parrot's boot splash with the Kettsec script theme. Regenerate the
# initramfs so both the live system and the installed system use this theme.
PLYMOUTH_THEME=kettsecos
PLYMOUTH_DIR="/usr/share/plymouth/themes/$PLYMOUTH_THEME"
install -d "$PLYMOUTH_DIR"
install -m0644 "$ASSETS/branding/plymouth/aegisos.script" \
  "$PLYMOUTH_DIR/$PLYMOUTH_THEME.script"
cat > "$PLYMOUTH_DIR/$PLYMOUTH_THEME.plymouth" <<EOF
[Plymouth Theme]
Name=KettsecOS
Description=KettsecOS dark security-style boot splash
ModuleName=script

[script]
ImageDir=$PLYMOUTH_DIR
ScriptFile=$PLYMOUTH_DIR/$PLYMOUTH_THEME.script
EOF
PLYMOUTH_FILE="$PLYMOUTH_DIR/$PLYMOUTH_THEME.plymouth"
update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
  default.plymouth "$PLYMOUTH_FILE" 200
update-alternatives --set default.plymouth "$PLYMOUTH_FILE"
# Parrot ships an explicit daemon theme setting that overrides the
# default.plymouth alternative. Set both so the generated initramfs embeds the
# theme shown by the live ISO and installed system.
if grep -q '^Theme=' /etc/plymouth/plymouthd.conf; then
  sed -i 's/^Theme=.*/Theme=kettsecos/' /etc/plymouth/plymouthd.conf
else
  printf '\n[Daemon]\nTheme=kettsecos\n' >> /etc/plymouth/plymouthd.conf
fi
update-initramfs -u -k all

cat > /etc/aegisos-release <<EOF
KettsecOS $VERSION based on Parrot Security Edition 7.3
EOF
if [ -f /etc/os-release ]; then
  # Keep ID=parrot so package and upgrade tooling recognizes the base distro.
  sed -i \
    -e 's/^NAME=.*/NAME="KettsecOS"/' \
    -e "s/^PRETTY_NAME=.*/PRETTY_NAME=\"KettsecOS $VERSION (Parrot Security Edition 7.3)\"/" \
    /etc/os-release
fi
if [ -f /etc/lsb-release ]; then
  sed -i \
    -e 's/^DISTRIB_ID=.*/DISTRIB_ID=KettsecOS/' \
    -e "s/^DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION=\"KettsecOS $VERSION based on Parrot Security Edition 7.3\"/" \
    /etc/lsb-release
fi
if [ -f /etc/default/grub.d/grub.cfg ]; then
  sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="KettsecOS"/' \
    /etc/default/grub.d/grub.cfg
fi
cat > /etc/motd <<EOF
KettsecOS $VERSION — Parrot Security Edition
Security tools are for authorized systems only.
EOF
cat > /etc/issue <<EOF
KettsecOS $VERSION\n\l
EOF

systemctl set-default graphical.target
apt-get clean
rm -rf -- /var/lib/apt/lists/* /tmp/aegisos-assets /tmp/parrot-customize.sh \
  /tmp/mullvad-keyring.asc /tmp/tor-browser.tar.xz
python3 -m compileall -q /usr/lib/aegisos-agent
truncate -s 0 /etc/machine-id
cleanup_policy
trap - EXIT

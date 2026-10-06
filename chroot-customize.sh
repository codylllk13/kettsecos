#!/bin/bash
# Runs INSIDE the chroot. Installs the live system, KDE Plasma, security
# tooling, AegisOS branding, and boot-time hardening.
set -euo pipefail

if [ "$#" -ne 18 ]; then
  echo "Usage: $0 CODENAME NAME ID VERSION TAGLINE GTK WINDOW ICON WALLPAPER PLYMOUTH DESKTOP_PKGS SECURITY_PKGS EXTRA_PKGS BG_PRIMARY BG_SECONDARY ACCENT_PRIMARY ACCENT_SECONDARY FG_PRIMARY" >&2
  exit 2
fi

CODENAME="$1"
DISTRO_NAME="$2"
DISTRO_ID="$3"
DISTRO_VERSION="$4"
DISTRO_TAGLINE="$5"
GTK_THEME="$6"
WINDOW_THEME="$7"
ICON_THEME="$8"
WALLPAPER_PATH="$9"
PLYMOUTH_THEME="${10}"
DESKTOP_PACKAGES="${11}"
SECURITY_PACKAGES="${12}"
EXTRA_PACKAGES="${13}"
BACKGROUND_PRIMARY="${14}"
BACKGROUND_SECONDARY="${15}"
ACCENT_PRIMARY="${16}"
ACCENT_SECONDARY="${17}"
FOREGROUND_PRIMARY="${18}"
ASSET_DIR="/tmp/aegisos-assets"

rgb_triplet() {
  local hex="${1#\#}"
  printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}
BG_PRIMARY_RGB="$(rgb_triplet "$BACKGROUND_PRIMARY")"
BG_SECONDARY_RGB="$(rgb_triplet "$BACKGROUND_SECONDARY")"
ACCENT_PRIMARY_RGB="$(rgb_triplet "$ACCENT_PRIMARY")"
ACCENT_SECONDARY_RGB="$(rgb_triplet "$ACCENT_SECONDARY")"
FG_PRIMARY_RGB="$(rgb_triplet "$FOREGROUND_PRIMARY")"

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

remove_policy_rc() {
  rm -f /usr/sbin/policy-rc.d
}

unit_exists() {
  local unit="$1"

  [ -e "/etc/systemd/system/$unit" ] ||
    [ -e "/usr/lib/systemd/system/$unit" ] ||
    [ -e "/lib/systemd/system/$unit" ]
}

enable_unit() {
  local unit="$1"

  if unit_exists "$unit"; then
    systemctl enable "$unit"
  else
    echo "Skipping unavailable systemd unit: $unit"
  fi
}

disable_unit() {
  local unit="$1"

  if unit_exists "$unit"; then
    systemctl disable "$unit"
  fi
}

echo "Customizing Ubuntu $CODENAME as $DISTRO_NAME..."

# Block package post-install scripts from starting services against the build
# host. Enabling units still creates the correct target symlinks for first boot.
cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x /usr/sbin/policy-rc.d
trap remove_policy_rc EXIT

apt-get update

# systemd first so machine-id and unit-management tools exist.
apt-get install -y systemd-sysv

# Kernel + live boot support (casper = Ubuntu's live-boot system).
apt-get install -y --no-install-recommends \
  linux-generic casper discover os-prober \
  locales console-setup sudo

# Avoid interactive package questions during an unattended image build.
echo "shared/default-x-display-manager select sddm" |
  debconf-set-selections
echo "wireshark-common wireshark-common/install-setuid boolean true" |
  debconf-set-selections
echo "macchanger macchanger/automatically_run boolean false" |
  debconf-set-selections
echo "aide-common aide/aideinit boolean false" |
  debconf-set-selections

PACKAGE_SET="$DESKTOP_PACKAGES $SECURITY_PACKAGES $EXTRA_PACKAGES"
# Package names are trusted, whitespace-separated values from config.sh.
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends $PACKAGE_SET

# Ubuntu's NetworkManager package excludes Ethernet unless a desktop policy
# overrides its vendor configuration. Make wired DHCP available in live and
# installed sessions without copying this build host's network profiles.
install -Dm0644 "$ASSET_DIR/networking/10-globally-managed-devices.conf" \
  /etc/NetworkManager/conf.d/10-globally-managed-devices.conf
install -Dm0600 "$ASSET_DIR/networking/01-aegisos-network-manager.yaml" \
  /etc/netplan/01-aegisos-network-manager.yaml
netplan generate

# Replace Kubuntu's installer branding and settings with AegisOS configuration.
install -d /etc/calamares/modules /etc/calamares/branding/aegisos
install -Dm0644 "$ASSET_DIR/calamares/settings.conf" /etc/calamares/settings.conf
install -Dm0644 "$ASSET_DIR/calamares/modules/"*.conf /etc/calamares/modules/
install -Dm0644 "$ASSET_DIR/calamares/branding/aegisos/"* /etc/calamares/branding/aegisos/
install -Dm0755 "$ASSET_DIR/installer/aegisos-installer" /usr/bin/aegisos-installer
install -Dm0644 "$ASSET_DIR/installer/aegisos-installer.desktop" /usr/share/applications/aegisos-installer.desktop

# Install the user-level agent and its shared service without copying weights
# or credentials into the image.
install -d /usr/lib/aegisos-agent/aegis_agent /usr/bin /usr/lib/systemd/user
install -m0644 "$ASSET_DIR/agent/aegis_agent/"*.py /usr/lib/aegisos-agent/aegis_agent/
install -m0755 "$ASSET_DIR/agent/aegis-agent" /usr/bin/aegis-agent
install -m0755 "$ASSET_DIR/agent/aegis-agent-ui" /usr/bin/aegis-agent-ui
install -m0644 "$ASSET_DIR/agent/aegis-agent.service" /usr/lib/systemd/user/aegis-agent.service
install -m0644 "$ASSET_DIR/agent/aegis-agent.desktop" /usr/share/applications/aegis-agent.desktop
systemctl --global enable aegis-agent.service

# Locale.
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Desktop artwork and defaults.
install -Dm0644 \
  "$ASSET_DIR/branding/aegisos-wallpaper.svg" \
  "$WALLPAPER_PATH"
install -d /usr/share/wallpapers/AegisOS/contents/images /etc/xdg /etc/skel/.config
install -m0644 "$WALLPAPER_PATH" \
  /usr/share/wallpapers/AegisOS/contents/images/1920x1080.svg
cat > /usr/share/wallpapers/AegisOS/metadata.desktop <<EOF
[Desktop Entry]
Name=$DISTRO_NAME
X-KDE-PluginInfo-Name=AegisOS
X-KDE-PluginInfo-Author=AegisOS contributors
X-KDE-PluginInfo-License=CC0-1.0
X-KDE-PluginInfo-Category=Wallpaper
EOF

cat > /etc/xdg/kdeglobals <<EOF
[General]
ColorScheme=AegisMatrix
Name=$DISTRO_NAME
widgetStyle=$WINDOW_THEME

[Colors:Window]
BackgroundNormal=$BG_PRIMARY_RGB
ForegroundNormal=$FG_PRIMARY_RGB
DecorationFocus=$ACCENT_PRIMARY_RGB
DecorationHover=$ACCENT_SECONDARY_RGB

[Colors:View]
BackgroundNormal=$BG_SECONDARY_RGB
ForegroundNormal=$FG_PRIMARY_RGB
SelectionBackground=$ACCENT_SECONDARY_RGB
SelectionForeground=255,255,255

[Icons]
Theme=$ICON_THEME
EOF

install -d /etc/gtk-3.0
cat > /etc/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-theme-name=$GTK_THEME
gtk-icon-theme-name=$ICON_THEME
gtk-font-name=Ubuntu 11
EOF

install -d /usr/share/konsole
cat > /usr/share/konsole/AegisMatrix.colorscheme <<'EOF'
[General]
Description=AegisOS Matrix
Opacity=1

[Foreground]
Color=216,255,224

[Background]
Color=3,8,5

[Color0]
Color=8,18,10
[Color1]
Color=255,76,76
[Color2]
Color=0,255,65
[Color3]
Color=190,255,77
[Color4]
Color=60,180,255
[Color5]
Color=200,100,255
[Color6]
Color=90,255,210
[Color7]
Color=216,255,224
[Color8]
Color=60,90,65
[Color9]
Color=255,110,110
[Color10]
Color=50,255,100
[Color11]
Color=220,255,110
[Color12]
Color=100,200,255
[Color13]
Color=220,140,255
[Color14]
Color=120,255,220
[Color15]
Color=255,255,255

[ForegroundIntense]
Color=255,255,255

[BackgroundIntense]
Color=3,8,5
EOF
cat > /usr/share/konsole/AegisMatrix.profile <<'EOF'
[Appearance]
ColorScheme=AegisMatrix
Font=Monospace,10,-1,5,50,0,0,0,0,0

[General]
Name=AegisMatrix
Parent=FALLBACK/

[Scrolling]
HistoryMode=2
ScrollBarPosition=2

[Terminal]
Command=/bin/bash
EOF
cat > /etc/xdg/konsolerc <<'EOF'
[Desktop Entry]
DefaultProfile=AegisMatrix.profile
EOF

cat > /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc <<EOF
[Containments][1]
activityId=
formfactor=0
immutability=1
lastScreen=0
location=0
plugin=org.kde.plasma.folder
wallpaperplugin=org.kde.image

[Containments][1][Wallpaper][org.kde.image][General]
Image=file:///usr/share/wallpapers/AegisOS/contents/images/1920x1080.svg
FillMode=2
EOF

install -d /etc/sddm.conf.d
cat > /etc/sddm.conf.d/aegisos.conf <<'EOF'
[Theme]
Current=breeze
EOF

# Give new users, including casper's live user, a two-line green prompt.
install -d /etc/skel/.config/aegisos
cat > /etc/skel/.config/aegisos/prompt.sh <<'EOF'
# AegisOS interactive Bash prompt.
case "$-" in
  *i*) ;;
  *) return ;;
esac

if [ -t 1 ]; then
  PS1='\[\e[38;5;46m\]┌─[\[\e[38;5;82m\]\u@\h\[\e[38;5;46m\]]─[\[\e[38;5;120m\]\w\[\e[38;5;46m\]]\n└─\[\e[0m\]\$ '
fi
EOF

touch /etc/skel/.bashrc
if ! grep -Fq "# AegisOS prompt" /etc/skel/.bashrc; then
  cat >> /etc/skel/.bashrc <<'EOF'

# AegisOS prompt
[ -r "$HOME/.config/aegisos/prompt.sh" ] &&
  . "$HOME/.config/aegisos/prompt.sh"
EOF
fi

# Install a small script-based Plymouth theme without copied logos/artwork.
PLYMOUTH_DIR="/usr/share/plymouth/themes/$PLYMOUTH_THEME"
install -d "$PLYMOUTH_DIR"
install -m0644 \
  "$ASSET_DIR/branding/plymouth/aegisos.script" \
  "$PLYMOUTH_DIR/$PLYMOUTH_THEME.script"
cat > "$PLYMOUTH_DIR/$PLYMOUTH_THEME.plymouth" <<EOF
[Plymouth Theme]
Name=$DISTRO_NAME
Description=$DISTRO_NAME dark security-style boot splash
ModuleName=script

[script]
ImageDir=$PLYMOUTH_DIR
ScriptFile=$PLYMOUTH_DIR/$PLYMOUTH_THEME.script
EOF
PLYMOUTH_FILE="$PLYMOUTH_DIR/$PLYMOUTH_THEME.plymouth"
update-alternatives \
  --install /usr/share/plymouth/themes/default.plymouth \
  default.plymouth \
  "$PLYMOUTH_FILE" \
  200
update-alternatives --set default.plymouth "$PLYMOUTH_FILE"

# On-disk hardening. Do not load firewall/AppArmor policy inside the chroot:
# those policies are enabled for the built system's first real boot.
install -Dm0644 \
  "$ASSET_DIR/hardening/99-aegisos-hardening.conf" \
  /etc/sysctl.d/99-aegisos-hardening.conf
install -Dm0644 \
  "$ASSET_DIR/hardening/60-aegisos-sshd.conf" \
  /etc/ssh/sshd_config.d/60-aegisos-hardening.conf
install -Dm0644 \
  "$ASSET_DIR/hardening/aegisos-fail2ban.local" \
  /etc/fail2ban/jail.d/aegisos.local
install -Dm0644 \
  "$ASSET_DIR/hardening/20auto-upgrades" \
  /etc/apt/apt.conf.d/20auto-upgrades
install -Dm0644 \
  "$ASSET_DIR/hardening/ufw.conf" \
  /etc/ufw/ufw.conf
install -Dm0755 \
  "$ASSET_DIR/hardening/aegisos-privacy.sh" \
  /usr/local/sbin/aegisos-privacy
install -Dm0755 \
  "$ASSET_DIR/hardening/aegisos-forensic-mode.sh" \
  /usr/local/libexec/aegisos-forensic-mode
install -Dm0755 \
  "$ASSET_DIR/hardening/aegisos-aide-init.sh" \
  /usr/local/libexec/aegisos-aide-init
install -Dm0644 \
  "$ASSET_DIR/hardening/aegisos-privacy-routing.service" \
  /etc/systemd/system/aegisos-privacy-routing.service
install -Dm0644 \
  "$ASSET_DIR/hardening/aegisos-forensic-mode.service" \
  /etc/systemd/system/aegisos-forensic-mode.service
install -Dm0644 \
  "$ASSET_DIR/hardening/aegisos-aide-init.service" \
  /etc/systemd/system/aegisos-aide-init.service

if ! grep -Fq "# AegisOS opt-in privacy routing listeners." /etc/tor/torrc; then
  printf '\n' >> /etc/tor/torrc
  cat "$ASSET_DIR/hardening/aegisos-torrc" >> /etc/tor/torrc
fi

sed -i \
  -e 's/^DEFAULT_INPUT_POLICY=.*/DEFAULT_INPUT_POLICY="DROP"/' \
  -e 's/^DEFAULT_OUTPUT_POLICY=.*/DEFAULT_OUTPUT_POLICY="ACCEPT"/' \
  -e 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' \
  -e 's/^IPV6=.*/IPV6=yes/' \
  /etc/default/ufw

for unit in \
  aegisos-aide-init.service \
  aegisos-forensic-mode.service \
  apparmor.service \
  apt-daily.timer \
  apt-daily-upgrade.timer \
  auditd.service \
  fail2ban.service \
  sddm.service \
  NetworkManager.service \
  systemd-resolved.service \
  ufw.service \
  unattended-upgrades.service; do
  enable_unit "$unit"
done

# The server is installed and hardened, but remote login stays off until the
# owner provisions a public key and explicitly enables it.
disable_unit ssh.service
disable_unit ssh.socket

# Tor routing and USB authorization can disrupt connectivity or input devices,
# so both remain explicit owner opt-ins. The privacy service starts Tor itself.
disable_unit aegisos-privacy-routing.service
disable_unit tor.service
disable_unit tor@default.service
disable_unit usbguard.service
disable_unit usbguard-dbus.service

# The AIDE package enables its timer during installation. Delay it until the
# first persistent boot has created a baseline; live sessions intentionally
# never create a throwaway database.
disable_unit dailyaidecheck.timer
systemctl set-default graphical.target

# Cosmetic identity; keep Ubuntu/Debian lineage explicit for compatibility.
cat > /etc/os-release <<EOF
NAME="$DISTRO_NAME"
VERSION="$DISTRO_VERSION (Ubuntu $CODENAME)"
ID=$DISTRO_ID
ID_LIKE="ubuntu debian"
PRETTY_NAME="$DISTRO_NAME $DISTRO_VERSION (Ubuntu $CODENAME base)"
VERSION_ID="$DISTRO_VERSION"
VERSION_CODENAME=$CODENAME
UBUNTU_CODENAME=$CODENAME
EOF

cat > /etc/lsb-release <<EOF
DISTRIB_ID=$DISTRO_NAME
DISTRIB_RELEASE=$DISTRO_VERSION
DISTRIB_CODENAME=$CODENAME
DISTRIB_DESCRIPTION="$DISTRO_NAME $DISTRO_VERSION"
EOF

printf '%s %s \\n \\l\n' "$DISTRO_NAME" "$DISTRO_VERSION" > /etc/issue
printf '%s %s\n' "$DISTRO_NAME" "$DISTRO_VERSION" > /etc/issue.net
cat > /etc/motd <<EOF
$DISTRO_NAME $DISTRO_VERSION — $DISTRO_TAGLINE
Security tools must only be used on systems you own or are authorized to test.
EOF

# Rebuild initramfs so casper, AppArmor, and the selected Plymouth theme land
# in the live image.
update-initramfs -u

# Cleanup to shrink the squashfs.
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
truncate -s 0 /etc/machine-id

remove_policy_rc
trap - EXIT

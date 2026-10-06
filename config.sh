#!/bin/bash
# Central configuration for your remix. Edit this, not the build scripts.
# Values in this file are consumed by scripts that source it.
# shellcheck disable=SC2034

# Identity. Keep DISTRO_ID lowercase and machine-friendly.
DISTRO_NAME="AegisOS"
DISTRO_ID="aegisos"
DISTRO_VERSION="2.0"
DISTRO_TAGLINE="Secure by default. Built for authorized security work."
ISO_LABEL="AEGISOS_20"          # max 32 chars, A-Z 0-9 _
TARGET_HOSTNAME="aegis"

# Ubuntu base
UBUNTU_CODENAME="noble"          # 24.04 LTS
UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu/"
UBUNTU_PORTS_MIRROR="http://ports.ubuntu.com/ubuntu-ports/"  # for ARM

# Desktop identity. GTK applications follow the Breeze style in Plasma.
GTK_THEME="Breeze-Dark"
WINDOW_THEME="Breeze"
ICON_THEME="Papirus-Dark"
WALLPAPER_PATH="/usr/share/backgrounds/aegisos/aegisos-wallpaper.svg"
PLYMOUTH_THEME="aegisos"

# Original AegisOS palette. Keep these as six-digit CSS hex colors for the
# Plasma, installer, and boot artwork defaults.
BACKGROUND_PRIMARY="#030805"
BACKGROUND_SECONDARY="#0b1b0e"
ACCENT_PRIMARY="#00ff41"
ACCENT_SECONDARY="#008f11"
FOREGROUND_PRIMARY="#d8ffe0"

# KDE Plasma desktop and installer packages baked into the amd64 ISO.
DESKTOP_PACKAGES="
  kde-plasma-desktop
  plasma-workspace
  plasma-nm
  kwin-x11
  kwin-wayland
  kwin-style-breeze
  systemsettings
  sddm
  dolphin
  konsole
  kate
  ark
  kde-spectacle
  kcalc
  kde-config-gtk-style
  breeze-gtk-theme
  sddm-theme-breeze
  gnome-keyring
  calamares
  calamares-settings-kubuntu
  network-manager
  netplan.io
  ethtool
  pciutils
  usbutils
  iputils-ping
  dnsutils
  rfkill
  policykit-1
  fonts-ubuntu
  papirus-icon-theme
  plymouth-theme-spinner
"

# Hardening and authorized security-testing tools from Ubuntu's own archives.
# Intentionally excludes large wordlists and third-party repositories.
SECURITY_PACKAGES="
  aide
  aide-common
  apparmor
  apparmor-profiles
  apparmor-profiles-extra
  apparmor-utils
  auditd
  binwalk
  chkrootkit
  fail2ban
  firejail
  firejail-profiles
  foremost
  gobuster
  libimage-exiftool-perl
  macchanger
  nftables
  openssh-server
  proxychains4
  radare2
  rkhunter
  smbclient
  sslscan
  steghide
  tor
  torsocks
  ufw
  unattended-upgrades
  usbguard
  whatweb
  yara
  aircrack-ng
  dirb
  gdb
  hashcat
  hydra
  john
  netcat-openbsd
  nikto
  nmap
  sqlmap
  tcpdump
  wireshark
"

# Additional packages remain an additive extension point for both builders.
EXTRA_PACKAGES="
  curl
  epiphany-browser
  git
  htop
  vim
  python3
  python3-pyqt5
  python3-requests
  python3-keyring
  python3-jwt
  bubblewrap
"

# Live session user (created by casper at boot, not baked into the image)
LIVE_USERNAME="live"

# Paths (relative to repo root)
WORK_DIR="work"
CHROOT_DIR="$WORK_DIR/chroot"
IMAGE_DIR="$WORK_DIR/image"
OUT_DIR="out"

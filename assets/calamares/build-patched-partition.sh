#!/bin/bash
# Build only KettsecOS' patched Calamares partition plugin against the exact ABI
# shipped in Parrot Security Edition. This runs in the build chroot as root.
set -euo pipefail

CALAMARES_VERSION="$(dpkg-query -W -f='${Version}' calamares)"
if [ "$CALAMARES_VERSION" != '3.3.14-1' ]; then
  echo "Expected Calamares 3.3.14-1, found $CALAMARES_VERSION; refusing ABI-uncertain build." >&2
  exit 1
fi

BUILD_CPUS="${KETTCO_BUILD_CPUS:-2}"
[[ "$BUILD_CPUS" =~ ^[1-9][0-9]*$ ]] || {
  echo 'KETTCO_BUILD_CPUS must be a positive integer' >&2
  exit 2
}

WORK_ROOT=/tmp/kettco-calamares-build
PATCH=/tmp/aegisos-assets/calamares/calamares-3.3.14-disk-confirmation.patch
PLUGIN_DIR=/usr/lib/x86_64-linux-gnu/calamares/modules/partition

apt-get update
# This image gets libxkbcommon0 from Parrot backports, while the stable
# development package depends on the older exact runtime version. Select the
# matching dev package first so build-dep does not try to downgrade the live
# system's library.
LIBXKBCOMMON_VERSION="$(dpkg-query -W -f='${Version}' libxkbcommon0)"
apt-get install --yes "libxkbcommon-dev=$LIBXKBCOMMON_VERSION"
apt-mark auto libxkbcommon-dev
apt-get build-dep --yes calamares
rm -rf -- "$WORK_ROOT"
mkdir -p "$WORK_ROOT"
(
  cd "$WORK_ROOT"
  # APT authenticates the exact Parrot/Debian source package used to build the
  # installed binary, including its distro patch series.
  apt-get source "calamares=$CALAMARES_VERSION"
)
SOURCE_ROOT="$(find "$WORK_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'calamares-*' -print -quit)"
BUILD_ROOT="$WORK_ROOT/build"
if [ -z "$SOURCE_ROOT" ]; then
  echo 'APT did not unpack the matching Calamares source package.' >&2
  exit 1
fi
patch --directory="$SOURCE_ROOT" --strip=1 --fuzz=0 --batch --input="$PATCH"

SKIP_MODULES="$(find "$SOURCE_ROOT/src/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
  | awk '$0 != "partition"' | paste -sd ' ' -)"
cmake -S "$SOURCE_ROOT" -B "$BUILD_ROOT" \
  -DCMAKE_BUILD_TYPE=Release \
  -DWITH_QT6=ON \
  -DBUILD_CRASH_REPORTING=OFF \
  -DBUILD_SCHEMA_TESTING=OFF \
  -DINSTALL_CONFIG=OFF \
  -DSKIP_MODULES="$SKIP_MODULES"
cmake --build "$BUILD_ROOT" --target calamares_viewmodule_partition --parallel "$BUILD_CPUS"
PLUGIN="$(find "$BUILD_ROOT/src/modules/partition" -maxdepth 1 -type f \
  -name 'libcalamares_viewmodule_partition.so' -print -quit)"
if [ -z "$PLUGIN" ]; then
  echo 'Calamares partition plugin build produced no shared library.' >&2
  exit 1
fi
install -D -m0755 "$PLUGIN" "$PLUGIN_DIR/libcalamares_viewmodule_partition.so"
if ldd "$PLUGIN_DIR/libcalamares_viewmodule_partition.so" | grep -q 'not found'; then
  echo 'Patched Calamares partition plugin has unresolved runtime libraries.' >&2
  exit 1
fi

rm -rf -- "$WORK_ROOT"
apt-get autoremove --yes --purge
apt-get clean

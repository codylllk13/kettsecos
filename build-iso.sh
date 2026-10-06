#!/bin/bash
# Build the current AegisOS image from a verified Parrot Security ISO.
set -euo pipefail
cd "$(dirname "$0")"
exec ./build-parrot-iso.sh "$@"

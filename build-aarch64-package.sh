#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

SYSROOT="${DENIAL_ARM64_SYSROOT:-$HOME/.cache/denial/arm64-sysroot}"

if [ ! -d "$SYSROOT/usr/lib/pkgconfig" ]; then
  printf 'error: ARM64 sysroot not found at %s\n' "$SYSROOT" >&2
  printf 'set DENIAL_ARM64_SYSROOT to an Arch Linux ARM root\n' >&2
  exit 1
fi

export DENIAL_TARGET_ARCH=aarch64
export DENIAL_ARM64_SYSROOT="$SYSROOT"
export DENIAL_PC_PACKAGE_ROOT="$ROOT"

exec "$ROOT/tools/denial-pc" arch-package

#!/usr/bin/env bash
# scripts/release.sh — builds and checksums the mcm binary for one
# target. Always fully static (see project.json's link-args) — this
# binary is dropped onto a bare machine by install.sh with nothing else
# installed, so it can't assume the target's glibc/libgcc match whatever
# built it.
#
#   scripts/release.sh TARGET [CC] [OUTPUT_NAME]
#     TARGET      a c3c --target value, e.g. linux-x64, linux-aarch64
#     CC          the C compiler to link with (default: cc) — for a
#                 cross-target this needs to be that target's cross-gcc,
#                 e.g. aarch64-linux-gnu-gcc
#     OUTPUT_NAME name to embed in the output filename (default: TARGET)
#                 — lets the published asset match `uname -m` (x86_64)
#                 rather than c3c's own target spelling (linux-x64),
#                 since that's what install.sh picks an asset by.
#
# Deliberately always routes linking through the given CC (--linker=cc)
# rather than c3c's builtin ld.lld: lld doesn't know a cross-gcc's own
# library search paths (crt1.o, libgcc, ...), so cross-linking through it
# directly fails to find them. --linux-crt is derived from the compiler
# itself (gcc -print-file-name=crt1.o) instead of a hardcoded per-distro
# path, so this works unmodified on Arch (dev machine) and Ubuntu (CI) —
# verified locally against both a native and a
# aarch64-linux-gnu-gcc-cross build before this script was written.
#
# No target-specific branching needed: this same recipe (derive
# --linux-crt from whichever CC is given, always pass --linker=cc)
# produces a correct binary for the native case too, not just cross
# targets — one code path, not two.
#
# Called once per target from .github/workflows/release.yml's matrix;
# runs unmodified under any other CI or by hand, same as every other
# script in this project.
set -Eeuo pipefail

TARGET="${1:?Usage: release.sh TARGET [CC] [OUTPUT_NAME]}"
CC="${2:-cc}"
OUTPUT_NAME="${3:-$TARGET}"

CRT_DIR="$(dirname "$("$CC" -print-file-name=crt1.o)")"

c3c build --target "$TARGET" --linker=cc --cc "$CC" --linux-crt "$CRT_DIR"

BIN="build/mcm"
[[ -f "$BIN" ]] || { echo "Build did not produce $BIN" >&2; exit 1; }

OUT="build/mcm-$OUTPUT_NAME"
mv -- "$BIN" "$OUT"

if command -v sha256sum > /dev/null 2>&1; then
    sha256sum -- "$OUT" | awk '{print $1}' > "$OUT.sha256"
elif command -v shasum > /dev/null 2>&1; then
    shasum -a 256 -- "$OUT" | awk '{print $1}' > "$OUT.sha256"
else
    echo "Neither sha256sum nor shasum is available." >&2
    exit 1
fi

echo "Built $OUT"
echo "SHA256: $(cat "$OUT.sha256")"

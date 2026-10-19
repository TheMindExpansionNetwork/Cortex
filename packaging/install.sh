#!/bin/sh
# Cortex Terminal: one-line installer for Linux and macOS.
#
#     curl -fsSL https://github.com/Niko1221/Strata/releases/latest/download/install.sh | sh
#
# What it does, in order (and nothing else):
#   1. finds out which computer this is (system, processor, graphics card) so it can fetch the right archive;
#   2. downloads the Terminal archive named in the release folder's install-manifest.txt and checks its SHA-256 against it;
#   3. unpacks it into  ${XDG_DATA_HOME:-~/.local/share}/cortex/terminal/<version>  (no administrator rights, nothing outside your home);
#   4. checks the release's signed feed with the Terminal it just unpacked (`cortex update --check`); if that check fails, it removes
#      what it unpacked and stops;
#   5. puts a `cortex` link in ~/.local/bin and prints:  Installed. Run: cortex launch
#
# The engine (the part that talks to your graphics card) and the model are NOT part of this: `cortex launch` fetches the engine for
# your card the first time you choose a model, from the same release folder, signed.
#
# <feed> is where the release folder is hosted: GitHub Releases of Niko1221/Strata (the "latest" release's files), built in as the default.
# Set CORTEX_FEED to another folder (a URL) to use that instead, for example a local test feed:  CORTEX_FEED=http://127.0.0.1:8099 sh install.sh
#
# Settings (all optional): CORTEX_FEED, CORTEX_DATA_DIR (default ~/.local/share/cortex), CORTEX_BIN_DIR (default ~/.local/bin),
# CORTEX_INSTALL_TEST_TRUST=1 (a test feed: also fetch <feed>/test-trust.json and trust only that key for the check in step 4).
set -eu

FEED="${CORTEX_FEED:-https://github.com/Niko1221/Strata/releases/latest/download}"
FEED="${FEED%/}"
DATA_DIR="${CORTEX_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/cortex}"
BIN_DIR="${CORTEX_BIN_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*"; }
die() { printf 'cortex installer: %s\n' "$*" >&2; exit 1; }

[ -n "$FEED" ] || die "this installer does not know where the Cortex release folder is. Set CORTEX_FEED to its address and run it again, for example: CORTEX_FEED=https://example.org/strata sh install.sh"

# ---- tools
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -q -O "$2" "$1"; }
else
  die "neither curl nor wget is installed, so nothing can be downloaded. Install one (for example: sudo apt install curl) and run this again."
fi
if command -v sha256sum >/dev/null 2>&1; then
  sha() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  die "no sha256sum or shasum was found, so the download cannot be checked. Install coreutils and run this again."
fi
command -v tar >/dev/null 2>&1 || die "tar is not installed; install it and run this again."

# ---- 1. this computer
os=$(uname -s); arch=$(uname -m)
case "$os-$arch" in
  Linux-x86_64|Linux-amd64) platform=linux-x86_64 ;;
  Darwin-arm64|Darwin-aarch64) platform=macos-arm64 ;;
  *) die "this computer ($os $arch) has no Cortex Terminal yet. Supported: Linux x86_64, macOS on Apple silicon (Windows: use install.ps1)." ;;
esac
gpu=""
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || true)
  [ -n "$gpu" ] && gpu="NVIDIA $gpu"
fi
if [ -z "$gpu" ] && [ "$os" = Linux ] && command -v lspci >/dev/null 2>&1; then
  gpu=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | sed 's/^[^:]*: *//' || true)
fi
if [ -z "$gpu" ] && [ "$os" = Darwin ]; then
  gpu=$(system_profiler SPDisplaysDataType 2>/dev/null | sed -n 's/^ *Chipset Model: //p' | head -1 || true)
fi
say "Cortex Terminal installer"
say "  This computer: $os $arch ($platform)${gpu:+, graphics: $gpu}"
say "  Release folder: $FEED"

# ---- 2. download and check
work=$(mktemp -d "${TMPDIR:-/tmp}/cortex-install.XXXXXX") || die "cannot make a temporary folder"
trap 'rm -rf "$work"' EXIT INT TERM
fetch "$FEED/install-manifest.txt" "$work/manifest.txt" || die "could not read $FEED/install-manifest.txt. Check the address and your internet connection."
line=$(awk -v p="$platform" '$1 == p { print; exit }' "$work/manifest.txt")
[ -n "$line" ] || die "this release has no Terminal for $platform."
set -- $line
version=$2; rel=$3; want=$4
say "  Terminal $version ($(( ${5:-0} / 1048576 )) MB)"
say "Downloading…"
fetch "$FEED/$rel" "$work/terminal.tar.gz" || die "the download failed. Check your internet connection and run this again; nothing was installed."
got=$(sha "$work/terminal.tar.gz")
[ "$got" = "$want" ] || die "the download does not match the release's checksum (got $got, wanted $want). It was not installed; try again, and if it repeats the release folder is damaged."
say "  Checksum ok."

# ---- 3. unpack
dest="$DATA_DIR/terminal/$version"
mkdir -p "$DATA_DIR/terminal" "$BIN_DIR"
rm -rf "$dest.incoming"; mkdir -p "$dest.incoming"
tar -xzf "$work/terminal.tar.gz" -C "$dest.incoming" || die "the archive could not be unpacked (is the disk full?). Nothing was installed."
if [ ! -f "$dest.incoming/bin/cortex" ]; then                  # an archive with one top folder (a terminal archive instead of the feed's control package)
  inner=$(ls -d "$dest.incoming"/*/ 2>/dev/null | head -1)
  if [ -n "$inner" ] && [ -f "${inner}bin/cortex" ]; then
    mv "${inner%/}" "$dest.inner" && rm -rf "$dest.incoming" && mv "$dest.inner" "$dest.incoming"
  fi
fi
[ -f "$dest.incoming/bin/cortex" ] || { rm -rf "$dest.incoming"; die "the archive does not look like a Cortex Terminal (no bin/cortex). Nothing was installed."; }
chmod +x "$dest.incoming/bin/cortex" 2>/dev/null || true

# ---- 4. the signed feed, checked with the Terminal just unpacked
if [ "${CORTEX_INSTALL_TEST_TRUST:-}" = 1 ]; then
  fetch "$FEED/test-trust.json" "$work/test-trust.json" || { rm -rf "$dest.incoming"; die "the test feed has no test-trust.json"; }
  CORTEX_UPDATE_TRUSTED_KEYS="$work/test-trust.json"; export CORTEX_UPDATE_TRUSTED_KEYS
fi
say "Checking the release's signature…"
if ! "$dest.incoming/bin/cortex" update --check --no-engine --feed "$FEED" >"$work/check.txt" 2>&1; then
  sed -e 's/^/    /' "$work/check.txt" | head -6 >&2
  rm -rf "$dest.incoming"
  die "the release folder's signed feed could not be verified, so nothing was installed. If you trust this source, ask its owner to publish a signed feed."
fi
say "  Signature ok."

# ---- 5. in place
rm -rf "$dest"
mv "$dest.incoming" "$dest"
ln -sfn "$dest" "$DATA_DIR/terminal/current"
ln -sf "$DATA_DIR/terminal/current/bin/cortex" "$BIN_DIR/cortex"
case ":$PATH:" in
  *":$BIN_DIR:"*) say "Installed. Run: cortex launch" ;;
  *) say "Installed. Run: $BIN_DIR/cortex launch"
     say "  (To type just 'cortex', add this line to your shell profile: export PATH=\"$BIN_DIR:\$PATH\")" ;;
esac

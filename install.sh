#!/bin/sh
# Standalone installer for cloudflared-ios on rootless jailbroken iOS.
#
#   curl -fsSL https://raw.githubusercontent.com/repos1tory/cloudflared-ios/main/install.sh | sh
#
# Env overrides: PREFIX (default /var/jb), SUDO (default sudo),
#                VERSION (default 2026.10.3), REPO, ASSET_FILE (local tarball).
set -eu
umask 022

PREFIX="${PREFIX:-/var/jb}"
SUDO="${SUDO:-sudo}"
VERSION="${VERSION:-2026.10.3}"
REPO="${REPO:-repos1tory/cloudflared-ios}"
ASSET_FILE="${ASSET_FILE:-}"
ASSET="cloudflared-ios-${VERSION}.tar.gz"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET}"

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "this installer is for iOS (Darwin), got: $(uname -s)"
[ -d "$PREFIX" ] || fail "no $PREFIX found; this installer targets rootless jailbreaks"
command -v curl >/dev/null 2>&1 || fail "curl not found"
command -v tar >/dev/null 2>&1 || fail "tar not found"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "$ASSET_FILE" ]; then
  say "==> using local asset: $ASSET_FILE"
  cp "$ASSET_FILE" "$TMP/$ASSET"
else
  say "==> downloading $ASSET"
  curl -fL --progress-bar -o "$TMP/$ASSET" "$URL"
fi

say "==> extracting"
mkdir -p "$TMP/out"
# GNU tar's gzip child exec is broken on iOS, so decompress explicitly.
gzip -dc "$TMP/$ASSET" | tar -xf - -C "$TMP/out"
[ -f "$TMP/out/cloudflared" ] || fail "archive is missing cloudflared"
[ -f "$TMP/out/quick-shim.js" ] || fail "archive is missing quick-shim.js"
[ -f "$TMP/out/cloudflared-wrapper" ] || fail "archive is missing the wrapper"

say "==> installing to $PREFIX/usr/lib/cloudflared-ios"
$SUDO mkdir -p "$PREFIX/usr/lib/cloudflared-ios" "$PREFIX/usr/bin"
$SUDO cp "$TMP/out/cloudflared" "$PREFIX/usr/lib/cloudflared-ios/cloudflared"
$SUDO cp "$TMP/out/quick-shim.js" "$PREFIX/usr/lib/cloudflared-ios/quick-shim.js"
$SUDO cp "$TMP/out/entitlements.plist" "$PREFIX/usr/lib/cloudflared-ios/entitlements.plist"
$SUDO cp "$TMP/out/cloudflared-wrapper" "$PREFIX/usr/bin/cloudflared"
$SUDO chmod 755 "$PREFIX/usr/lib/cloudflared-ios/cloudflared" "$PREFIX/usr/bin/cloudflared"
$SUDO chmod 644 "$PREFIX/usr/lib/cloudflared-ios/quick-shim.js" \
                "$PREFIX/usr/lib/cloudflared-ios/entitlements.plist"

say "==> verifying"
"$PREFIX/usr/bin/cloudflared" --version

if ! [ -x "$PREFIX/usr/bin/node" ] && ! command -v node >/dev/null 2>&1; then
  say ""
  say "note: nodejs is required for the quick-tunnel shim."
  say "      install the 'nodejs' package from repos1tory, then re-run a quick tunnel."
fi

say ""
say "Done. Try:"
say "    cloudflared tunnel --url http://127.0.0.1:8123"

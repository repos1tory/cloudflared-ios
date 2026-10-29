#!/bin/sh
# Standalone installer for cloudflared-ios on rootless jailbroken iOS.
#
#   curl -fsSL https://raw.githubusercontent.com/repos1tory/cloudflared-ios/main/install.sh | sh
#
# Env overrides: PREFIX (default /var/jb), SUDO (default sudo),
#                VERSION (default 2026.10.3-2), REPO, ASSET_FILE (local tarball).
set -eu
umask 022

PREFIX="${PREFIX:-/var/jb}"
SUDO="${SUDO:-sudo}"
VERSION="${VERSION:-2026.10.3-2}"
BASE_VERSION="${VERSION%-*}"
REPO="${REPO:-repos1tory/cloudflared-ios}"
ASSET_FILE="${ASSET_FILE:-}"
ASSET="cloudflared-ios-${BASE_VERSION}.tar.gz"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET}"

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "this installer is for iOS (Darwin), got: $(uname -s)"
[ -d "$PREFIX" ] || fail "no $PREFIX found; this installer targets rootless jailbreaks"
command -v curl >/dev/null 2>&1 || fail "curl not found"
command -v tar >/dev/null 2>&1 || fail "tar not found"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cloudflared-ios-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

if [ -n "$ASSET_FILE" ]; then
  say "==> using local asset: $ASSET_FILE"
  cp "$ASSET_FILE" "$TMP/$ASSET"
else
  say "==> downloading $ASSET"
  curl -fL --progress-bar -o "$TMP/$ASSET" "$URL"
fi

say "==> extracting"
mkdir -p "$TMP/out"
if command -v gzip >/dev/null 2>&1; then
  gzip -dc "$TMP/$ASSET" | tar -xf - -C "$TMP/out"
elif command -v node >/dev/null 2>&1; then
  node -e '
    const fs = require("fs"), zlib = require("zlib");
    fs.writeFileSync(process.argv[2], zlib.gunzipSync(fs.readFileSync(process.argv[1])));
  ' "$TMP/$ASSET" "$TMP/asset.tar"
  tar -xf "$TMP/asset.tar" -C "$TMP/out"
else
  fail "need gzip or node to extract the archive (install one from Sileo)"
fi
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
"$PREFIX/usr/bin/cloudflared" tunnel --help >/dev/null

if ! [ -x "$PREFIX/usr/bin/node" ] && ! command -v node >/dev/null 2>&1; then
  say ""
  say "note: Node.js is optional. The cloudflared binary and named tunnels work"
  say "      without it; only the quick-tunnel compatibility shim uses Node."
  say "      Install the 'nodejs' package if quick tunnels fail to provision."
fi

say ""
say "Done. Try:"
say "    cloudflared tunnel --url http://127.0.0.1:8123"

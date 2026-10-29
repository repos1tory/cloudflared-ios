#!/bin/sh
# Build the iOS port from Cloudflare's official darwin/arm64 release.
#
#   sh scripts/build.sh [version]
#
# Produces dist/cloudflared-ios-<version>.tar.gz and a rootless .deb.
# Runs on-device (needs python3 or node, ldid, dpkg-deb) or on macOS with those
# tools. Node is only a build-time fallback for the Mach-O patch/gzip; the
# installed cloudflared CLI does not need Node.
set -eu
umask 022

VERSION="${1:-2026.10.3}"
REVISION="${PACKAGE_REVISION:-2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build"
DIST="$ROOT/dist"
PKG="$WORK/pkg"
ASSET="cloudflared-darwin-arm64.tgz"
URL="https://github.com/cloudflare/cloudflared/releases/download/${VERSION}/${ASSET}"

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

for tool in curl tar dpkg-deb ldid; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing required tool: $tool"
done
command -v python3 >/dev/null 2>&1 || command -v node >/dev/null 2>&1 ||
  fail "need python3 or node for the Mach-O patch"

mkdir -p "$WORK" "$DIST"
rm -rf "$PKG"
mkdir -p "$PKG/DEBIAN" \
         "$PKG/var/jb/usr/lib/cloudflared-ios" \
         "$PKG/var/jb/usr/bin" \
         "$PKG/var/jb/usr/share/doc/cloudflared-ios"

# --- fetch upstream ---------------------------------------------------------
if [ ! -f "$WORK/$ASSET" ]; then
  say "==> downloading cloudflared $VERSION (darwin/arm64)"
  curl -fL --progress-bar -o "$WORK/$ASSET" "$URL"
fi

rm -rf "$WORK/upstream"
mkdir -p "$WORK/upstream"
if command -v gzip >/dev/null 2>&1; then
  tar -xzf "$WORK/$ASSET" -C "$WORK/upstream"
else
  node "$ROOT/scripts/gunzip.mjs" "$WORK/$ASSET" "$WORK/$ASSET.tar"
  tar -xf "$WORK/$ASSET.tar" -C "$WORK/upstream"
fi
[ -f "$WORK/upstream/cloudflared" ] || fail "release archive did not contain cloudflared"

say "==> patching Mach-O platform and framework paths"
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/scripts/patch_macho.py" \
    "$WORK/upstream/cloudflared" "$WORK/cloudflared.ios"
else
  node "$ROOT/scripts/patch-macho.mjs" \
    "$WORK/upstream/cloudflared" "$WORK/cloudflared.ios"
fi
node "$ROOT/scripts/verify-macho.mjs" "$WORK/cloudflared.ios"

say "==> signing with ldid"
chmod 755 "$WORK/cloudflared.ios"
ldid -S"$ROOT/entitlements.plist" "$WORK/cloudflared.ios"

# --- stage package ----------------------------------------------------------
LIB="$PKG/var/jb/usr/lib/cloudflared-ios"
cp "$WORK/cloudflared.ios" "$LIB/cloudflared"
cp "$ROOT/quick-shim.js" "$LIB/quick-shim.js"
cp "$ROOT/entitlements.plist" "$LIB/entitlements.plist"
cp "$ROOT/bin/cloudflared" "$PKG/var/jb/usr/bin/cloudflared"
cp "$ROOT/README.md" "$ROOT/LICENSE" "$PKG/var/jb/usr/share/doc/cloudflared-ios/"
chmod 755 "$LIB/cloudflared" "$PKG/var/jb/usr/bin/cloudflared"
chmod 644 "$LIB/quick-shim.js" "$LIB/entitlements.plist" \
          "$PKG/var/jb/usr/share/doc/cloudflared-ios/README.md" \
          "$PKG/var/jb/usr/share/doc/cloudflared-ios/LICENSE"

SIZE="$(du -sk "$PKG/var" | cut -f1)"
cat > "$PKG/DEBIAN/control" <<EOF
Package: com.repos1tory.cloudflared
Name: cloudflared
Version: ${VERSION}-${REVISION}
Architecture: iphoneos-arm64
Maintainer: repos1tory
Author: Cloudflare, Inc.; iOS port by repos1tory
Section: Networking
Priority: optional
Depends: firmware (>= 15.0)
Suggests: nodejs (>= 22.19.0)
Installed-Size: ${SIZE}
Homepage: https://github.com/repos1tory/cloudflared-ios
Description: Cloudflare Tunnel client for jailbroken iOS (arm64)
 cloudflared as a native command-line tool for rootless jailbroken iOS
 (palera1n rootless and Dopamine). Quick tunnels and named tunnels run
 directly on the device; no Mac or companion server is required. Node.js is
 optional and is only used by the quick-tunnel compatibility shim; the
 native binary itself does not depend on npm or Node.
EOF

# --- release tarball --------------------------------------------------------
say "==> writing release tarball"
TARSTAGE="$WORK/tar"
rm -rf "$TARSTAGE"
mkdir -p "$TARSTAGE"
cp "$WORK/cloudflared.ios" "$TARSTAGE/cloudflared"
cp "$ROOT/quick-shim.js" "$TARSTAGE/quick-shim.js"
cp "$ROOT/bin/cloudflared" "$TARSTAGE/cloudflared-wrapper"
cp "$ROOT/entitlements.plist" "$TARSTAGE/entitlements.plist"
cp "$ROOT/README.md" "$ROOT/LICENSE" "$TARSTAGE/"
chmod 755 "$TARSTAGE/cloudflared" "$TARSTAGE/cloudflared-wrapper"
if command -v gzip >/dev/null 2>&1; then
  # GNU tar on this platform cannot exec a bare "gzip" child; pipe explicitly.
  tar -cf - -C "$TARSTAGE" . | gzip -9 > "$DIST/cloudflared-ios-${VERSION}.tar.gz"
else
  tar -cf "$WORK/cloudflared.tar" -C "$TARSTAGE" .
  node "$ROOT/scripts/gzip.mjs" "$WORK/cloudflared.tar" \
    "$DIST/cloudflared-ios-${VERSION}.tar.gz"
fi

# --- deb --------------------------------------------------------------------
say "==> writing .deb"
DEB="$DIST/cloudflared-ios_${VERSION}-${REVISION}_iphoneos-arm64.deb"
if ! dpkg-deb --build --root-owner-group "$PKG" "$DEB" 2>/dev/null; then
  dpkg-deb --build "$PKG" "$DEB"
fi

say ""
say "binary:  $WORK/cloudflared.ios"
say "tarball: $DIST/cloudflared-ios-${VERSION}.tar.gz"
say "deb:     $DEB"
if command -v sha256sum >/dev/null 2>&1; then
  say "sha256:  $(sha256sum "$DEB" | cut -d' ' -f1)"
else
  say "sha256:  $(shasum -a 256 "$DEB" | cut -d' ' -f1)"
fi

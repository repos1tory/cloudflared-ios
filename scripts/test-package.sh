#!/bin/sh
# test-package.sh — exercise a built cloudflared .deb without installing it.
#
#   sh scripts/test-package.sh dist/cloudflared-ios_*.deb
#
# The native CLI is tested with a fake payload and with the real iOS binary on
# a jailbroken device. No network, account, or Node install is required.
set -eu

DEB="${1:-}"
[ -n "$DEB" ] && [ -f "$DEB" ] || {
  echo "usage: test-package.sh <cloudflared-ios .deb>" >&2
  exit 2
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cloudflared-ios-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

dpkg-deb -x "$DEB" "$TMP/root"
PREFIX="$TMP/root/var/jb"
CL="$PREFIX/usr/bin/cloudflared"
BIN="$PREFIX/usr/lib/cloudflared-ios/cloudflared"

[ -x "$CL" ] || { echo "FAIL: wrapper missing" >&2; exit 1; }
[ -x "$BIN" ] || { echo "FAIL: cloudflared binary missing" >&2; exit 1; }
[ -f "$PREFIX/usr/lib/cloudflared-ios/quick-shim.js" ] || {
  echo "FAIL: quick-shim.js missing" >&2
  exit 1
}

echo "==> control fields"
DEPENDS="$(dpkg-deb -f "$DEB" Depends || true)"
SUGGESTS="$(dpkg-deb -f "$DEB" Suggests || true)"
printf 'Depends: %s\nSuggests: %s\n' "$DEPENDS" "$SUGGESTS"
printf '%s\n' "$DEPENDS" | grep -q 'nodejs' && {
  echo "FAIL: native package still depends on nodejs" >&2
  exit 1
}
printf '%s\n' "$SUGGESTS" | grep -q 'nodejs' || {
  echo "FAIL: optional Node quick-shim dependency not declared in Suggests" >&2
  exit 1
}

# The wrapper must not need Node for version/help/named-tunnel paths.
grep -q 'CLOUDFLARED_IOS_DISABLE_SHIM' "$CL" || {
  echo "FAIL: wrapper lacks direct-provisioning override" >&2
  exit 1
}

SH="$(command -v sh)"
FAKE="$TMP/fake"
mkdir -p "$FAKE" "$TMP/empty"
if [ -x /var/jb/bin/sh ]; then FAKE_SH=/var/jb/bin/sh; else FAKE_SH=/bin/sh; fi
cat > "$FAKE/cloudflared" <<EOF
#!$FAKE_SH
echo "FAKE \$*"
EOF
chmod 755 "$FAKE/cloudflared"

echo "==> wrapper without Node (version/help/quick fallback)"
OUT="$(env PATH="$TMP/empty" PREFIX="$PREFIX" CLOUDFLARED_IOS_DIR="$FAKE" \
  "$SH" "$CL" --version)"
printf '%s\n' "$OUT" | grep -q 'FAKE --version' || {
  echo "FAIL: --version did not exec the native binary" >&2
  exit 1
}
OUT="$(env PATH="$TMP/empty" PREFIX="$PREFIX" CLOUDFLARED_IOS_DIR="$FAKE" \
  "$SH" "$CL" tunnel --help)"
printf '%s\n' "$OUT" | grep -q 'FAKE tunnel --help' || {
  echo "FAIL: tunnel --help did not exec the native binary" >&2
  exit 1
}
OUT="$(env PATH="$TMP/empty" PREFIX="$PREFIX" CLOUDFLARED_IOS_DIR="$FAKE" \
  "$SH" "$CL" tunnel --url http://127.0.0.1:1)"
printf '%s\n' "$OUT" | grep -q 'FAKE tunnel --url' || {
  echo "FAIL: quick tunnel without Node did not fall back to the native binary" >&2
  exit 1
}

# On a jailbroken device, also run the real patched binary. Do not attempt this
# on a macOS CI runner: the binary targets iOS, not macOS.
if [ -d /var/jb ] && [ "$(uname -s)" = "Darwin" ]; then
  echo "==> real binary --version"
  PREFIX="$PREFIX" "$SH" "$CL" --version

  echo "==> real binary tunnel --help"
  PREFIX="$PREFIX" "$SH" "$CL" tunnel --help > "$TMP/help.txt"
  grep -q 'USAGE' "$TMP/help.txt" || {
    echo "FAIL: tunnel --help output missing USAGE" >&2
    exit 1
  }
fi

echo "PASS: cloudflared package smoke test"

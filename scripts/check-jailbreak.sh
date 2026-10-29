#!/bin/sh
# check-jailbreak.sh — reject jailbreak-specific absolute paths. Both
# palera1n rootless and Dopamine mount the bootstrap at /var/jb.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bad=0
for f in install.sh bin/cloudflared scripts/*.sh scripts/*.mjs; do
  [ -f "$f" ] || continue
  [ "$f" = "scripts/check-jailbreak.sh" ] && continue
  if grep -nE '/private/preboot|dopamine-[A-Za-z0-9]|jb-[A-Za-z0-9]{4,}' "$f"; then
    echo "FAIL: jailbreak-specific path in $f" >&2
    bad=1
  fi
done

grep -q 'PREFIX="${PREFIX:-/var/jb}"' bin/cloudflared || {
  echo "FAIL: wrapper does not default to /var/jb" >&2
  bad=1
}
grep -q 'CLOUDFLARED_IOS_DIR' bin/cloudflared || {
  echo "FAIL: wrapper lacks CLOUDFLARED_IOS_DIR override" >&2
  bad=1
}

[ "$bad" -eq 0 ] || exit 1
echo "PASS: runtime files are jailbreak-neutral (palera1n/Dopamine rootless)"

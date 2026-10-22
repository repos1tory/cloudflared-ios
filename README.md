# cloudflared-ios

### Cloudflare Tunnel client running natively on jailbroken iOS (arm64)

`cloudflared` 2026.10.3, adapted from Cloudflare's official Darwin arm64 build so it can run as a
plain CLI on a **rootless jailbroken iPad/iPhone**. No Mac, Linux box, or companion computer is
required.

```
$ cloudflared --version
cloudflared version 2026.10.3 (built 2026-10-21-13:12 UTC)

$ cloudflared tunnel --url http://127.0.0.1:8123
...
|  https://example-words-here.trycloudflare.com  |
```

Tested on an **iPad7,5 (A10), iOS 16.6, rootless `/var/jb`**, serving a local web app over HTTPS.

> This is an unofficial port. It is not affiliated with or supported by Cloudflare.

---

## What works

| | |
|---|---|
| `cloudflared --version`, `--help` | ✅ |
| Quick tunnels (`tunnel --url`, `--hello-world`) | ✅ verified end-to-end |
| Named tunnels (`tunnel run --token …`) | ⚠️ expected to work; not tested with an account here |
| `tunnel login`, `tunnel create`, DNS routes | ⚠️ binary runs; account flow untested |
| QUIC and HTTP/2 edge transports | ✅ pre-checks pass; QUIC used |
| HTTPS termination | ✅ Cloudflare edge certificate |
| Auto-update | ❌ disabled; update by installing a newer package |

## Requirements

- Rootless jailbreak with the bootstrap at `/var/jb` (Dopamine, palera1n rootless, etc.)
- iOS 15+ on arm64
- `nodejs` from the repos1tory (used only by the quick-tunnel compatibility shim)
- `sudo` for system-wide installation

## Install

From the repos1tory (recommended):

```
https://repos1tory.github.io/
```

Install **cloudflared** from Sileo/Zebra. Or use the standalone installer:

```sh
curl -fsSL https://raw.githubusercontent.com/repos1tory/cloudflared-ios/main/install.sh | sh
```

Manual install from a checkout:

```sh
sudo mkdir -p /var/jb/usr/lib/cloudflared-ios
sudo cp cloudflared quick-shim.js /var/jb/usr/lib/cloudflared-ios/
sudo cp bin/cloudflared /var/jb/usr/bin/cloudflared
sudo chmod 755 /var/jb/usr/bin/cloudflared /var/jb/usr/lib/cloudflared-ios/cloudflared
```

Then:

```sh
cloudflared --version
cloudflared tunnel --url http://127.0.0.1:8123
```

## How the port works

The official `cloudflared-darwin-arm64` binary is a Mach-O executable with two macOS assumptions:

1. `LC_BUILD_VERSION` identifies the platform as **macOS** (`platform 1`), not iOS (`platform 2`);
2. CoreFoundation and Security are referenced through their macOS `Versions/A/` paths, which do not
   exist in the iOS dyld shared cache.

The build script patches those load commands in place, then re-signs the binary with `ldid` and
minimal jailbreak entitlements. The result is still Cloudflare's binary — no Cloudflare code is
recompiled or modified.

### Quick-tunnel API shim

Current `cloudflared` sends an **empty** `POST /tunnel` body for a public quick tunnel. On this
device that request stalls or returns `409 Tunnelstore request failed`, while an explicit `{}` body
provisions the tunnel correctly. The installed wrapper starts a tiny localhost-only Node shim for
quick-tunnel commands and points `cloudflared` at it with `--quick-service`.

This shim exists only for quick tunnels. Named-tunnel commands bypass it and exec the real binary
directly. If a future upstream release fixes the empty-body request, the shim can be removed.

## Limitations

- **No background daemon.** iOS suspends processes when the app is backgrounded; keep the terminal
  session alive while the tunnel is in use.
- **Quick tunnels are temporary.** The URL changes on every run and has no uptime guarantee.
- **No auto-update.** This build uses the official release's binary; update by reinstalling.
- **No account flows tested.** Named tunnels and `tunnel login` should work but are unverified here.
- **Public exposure.** Anyone with the URL can reach the origin. Do not expose private services.

## Build

On the device, from a checkout:

```sh
sh scripts/build.sh 2026.10.3
```

The script downloads the official Darwin arm64 release, patches the Mach-O, signs it, and writes:

```
dist/cloudflared-ios-2026.10.3.tar.gz
dist/cloudflared-ios_2026.10.3-1_iphoneos-arm64.deb
```

It requires `curl`, `tar`, `python3`, `ldid`, and `dpkg-deb`.

The patch and packaging steps are reproducible; the exact binary is Cloudflare's published artifact.
Verify the upstream download against the release checksum if you redistribute it.

## Prior art and name check

Before publishing, searches for `cloudflared-ios`, `cloudflared iOS`, `cloudflared jailbreak`, and
`cloudflared iphoneos-arm64` found no existing standalone iOS port of the `cloudflared` CLI.
[`wiedymi/swift-cloudflared`](https://github.com/wiedymi/swift-cloudflared) is a separate Swift SDK
for Cloudflare Access TCP tunnels, not this CLI. `repos1tory/cloudflared-ios` was confirmed absent
on GitHub before creation.

## License

Apache-2.0. `cloudflared` is © Cloudflare, Inc. and licensed under Apache-2.0; see [`LICENSE`](LICENSE).
The iOS patch, wrapper, shim, and packaging scripts are released under the same license.

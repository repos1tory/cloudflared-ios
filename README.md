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

Verified on an **iPad7,5 (A10), iPadOS 17.7.8, Dopamine rootless**, with and without Node.js
installed. The same package is written for **palera1n rootless**: both jailbreaks mount the
bootstrap at `/var/jb`, and no runtime file contains a preboot UUID or a jailbreak-specific path.

> This is an unofficial port. It is not affiliated with or supported by Cloudflare.

---

## What works

| | |
|---|---|
| `cloudflared --version`, `--help` | ✅ verified on-device |
| `cloudflared tunnel --help` | ✅ verified on-device |
| Quick tunnels (`tunnel --url`, `--hello-world`) | ✅ verified end-to-end |
| Named tunnels (`tunnel run --token …`) | ⚠️ expected to work; not tested with an account here |
| `tunnel login`, `tunnel create`, DNS routes | ⚠️ binary runs; account flow untested |
| QUIC and HTTP/2 edge transports | ✅ pre-checks pass; QUIC used |
| HTTPS termination | ✅ Cloudflare edge certificate |
| Auto-update | ❌ disabled; update by installing a newer package |

## Requirements

- Rootless jailbreak with the bootstrap at `/var/jb` (palera1n rootless, Dopamine, etc.)
- iOS 15+ on arm64
- **No Node.js or npm required** for the native CLI, named tunnels, or `--version`/`--help`.
  Node.js is optional and is used only by the quick-tunnel compatibility shim.
- `sudo` for the standalone installer. Sileo/APT installation does not need a shell password.

## Install

From the repos1tory (recommended):

```
https://repos1tory.github.io/
```

Install **cloudflared** from Sileo/Zebra. The repository is signed; see the
[repository key instructions](https://repos1tory.github.io/#repository-key) if your client still
says “unauthenticated”.

Or use the standalone installer:

```sh
curl -fsSL https://raw.githubusercontent.com/repos1tory/cloudflared-ios/main/install.sh | sh
```

Manual install from a checkout:

```sh
sh scripts/build.sh 2026.10.3
sudo dpkg -i dist/cloudflared-ios_2026.10.3-2_iphoneos-arm64.deb
```

Then:

```sh
cloudflared --version
cloudflared tunnel --help
cloudflared tunnel --url http://127.0.0.1:8123
```

Uninstall:

```sh
sudo dpkg -r com.repos1tory.cloudflared
```

## Authentication

- **Quick tunnels** need no Cloudflare account and no stored credentials.
- **Named tunnels** can use a token from the Zero Trust dashboard:

  ```sh
  cloudflared tunnel run --token <token>
  ```

  The token is a credential: keep it out of shell history and chat, and pass it through an
  environment variable or a mode-600 file rather than a command line visible to other processes.
- `cloudflared tunnel login` opens a browser-based certificate flow; it is not automated here.

A palera1n-era home may contain old `~/.cloudflared/cert.pem` or tunnel JSON files if you used
`tunnel login`. On this device no such file was present in either the palera1n or Dopamine home,
so there was nothing to migrate; quick tunnels and token-based named tunnels do not need it.

## How the port works

The official `cloudflared-darwin-arm64` binary is a Mach-O executable with two macOS assumptions:

1. `LC_BUILD_VERSION` identifies the platform as **macOS** (`platform 1`), not iOS (`platform 2`);
2. CoreFoundation and Security are referenced through their macOS `Versions/A/` paths, which do not
   exist in the iOS dyld shared cache.

The build script patches those load commands in place, then re-signs the binary with `ldid` and
minimal jailbreak entitlements. The result is still Cloudflare's binary — no Cloudflare code is
recompiled or modified.

The patcher has both a Python implementation (`scripts/patch_macho.py`, used on macOS CI) and a
Node implementation (`scripts/patch-macho.mjs`), so the package can also be rebuilt on a device
that has Node but no Python. `scripts/verify-macho.mjs` asserts the platform is iOS and that no
macOS framework path remains before signing.

### Quick-tunnel API shim

Current `cloudflared` sends an **empty** `POST /tunnel` body for a public quick tunnel. On this
device that request stalls or returns `409 Tunnelstore request failed`, while an explicit `{}`
body provisions the tunnel correctly. When Node is available, the wrapper starts a tiny
localhost-only shim for quick-tunnel commands and points `cloudflared` at it with
`--quick-service`.

This shim exists only for quick tunnels. Named-tunnel commands, `--version`, and `--help` bypass it
and exec the real binary directly. If Node is missing, the wrapper skips the shim and tries direct
provisioning; the native CLI still works. Set `CLOUDFLARED_IOS_DISABLE_SHIM=1` to force that path.

## Limitations

- **No background daemon.** iOS suspends processes when the app is backgrounded; keep the terminal
  session alive while the tunnel is in use.
- **Quick tunnels are temporary.** The URL changes on every run and has no uptime guarantee.
- **No auto-update.** This build uses the official release's binary; update by reinstalling.
- **No account flows tested.** Named tunnels and `tunnel login` should work but are unverified here.
- **Public exposure.** Anyone with the URL can reach the origin. Do not expose private services.

## Build and test

On the device or on macOS:

```sh
sh scripts/build.sh 2026.10.3          # -> dist/cloudflared-ios_2026.10.3-2_iphoneos-arm64.deb
sh scripts/test-package.sh dist/*.deb  # control fields, wrapper fallbacks, real binary on iOS
sh scripts/check-jailbreak.sh          # rejects preboot/Dopamine-specific paths
```

`test-package.sh` extracts the package into a temporary root, so it does not need root and does not
touch `/var/jb`. The real-binary `--version` and `tunnel --help` checks run automatically when
`/var/jb` exists (i.e. on the jailbroken device).

The build requires `curl`, `tar`, `ldid`, and `dpkg-deb`; it uses Python if present, otherwise Node,
for the Mach-O patch and for gzip fallbacks. CI builds on macOS with `ldid` and `dpkg`.

## Prior art and name check

Before publishing, searches for `cloudflared-ios`, `cloudflared iOS`, `cloudflared jailbreak`, and
`cloudflared iphoneos-arm64` found no existing standalone iOS port of the `cloudflared` CLI.
[`wiedymi/swift-cloudflared`](https://github.com/wiedymi/swift-cloudflared) is a separate Swift SDK
for Cloudflare Access TCP tunnels, not this CLI. `repos1tory/cloudflared-ios` was confirmed absent
on GitHub before creation.

## License

Apache-2.0. `cloudflared` is © Cloudflare, Inc. and licensed under Apache-2.0; see [`LICENSE`](LICENSE).
The iOS patch, wrapper, shim, and packaging scripts are released under the same license.

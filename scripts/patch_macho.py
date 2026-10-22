#!/usr/bin/env python3
"""Adapt Cloudflare's darwin/arm64 cloudflared Mach-O for jailbroken iOS.

This does not recompile anything. It changes the platform tag from macOS to iOS
and rewrites the macOS framework paths to the paths present in the iOS dyld
shared cache. The caller must re-sign the result (see build.sh).
"""
import struct
import sys

LC_LOAD_DYLIB = 0xC
LC_LOAD_UPWARD_DYLIB = 0x18F
LC_BUILD_VERSION = 0x32
MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C


def main(src: str, dst: str) -> int:
    data = bytearray(open(src, "rb").read())
    magic, cputype, _sub, _filetype, ncmds, _sizeofcmds, _flags, _res = struct.unpack_from(
        "<IiiIIIII", data, 0
    )
    if magic != MH_MAGIC_64 or cputype != CPU_TYPE_ARM64:
        raise SystemExit("error: expected a 64-bit arm64 Mach-O")

    changes = []
    off = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmdsize < 8 or off + cmdsize > len(data):
            raise SystemExit("error: corrupt load command table")

        if cmd == LC_BUILD_VERSION:
            platform, minos, sdk, _ntools = struct.unpack_from("<IIII", data, off + 8)
            changes.append(f"platform {platform} -> 2 (iOS); minos {minos:#x} -> 0xf0000")
            struct.pack_into("<I", data, off + 8, 2)          # PLATFORM_IOS
            struct.pack_into("<I", data, off + 12, 0x000F0000)  # iOS 15.0
            # Keep the upstream SDK field; it is informational for dyld.

        elif cmd in (LC_LOAD_DYLIB, LC_LOAD_UPWARD_DYLIB):
            name_off = struct.unpack_from("<I", data, off + 8)[0]
            start = off + name_off
            end = data.find(b"\0", start)
            if end < 0:
                raise SystemExit("error: unterminated dylib path")
            name = data[start:end].decode("utf-8")
            fixed = name.replace("/Versions/A/", "/")
            if fixed != name:
                old = data[start:end + 1]
                new = fixed.encode("utf-8") + b"\0"
                if len(new) > len(old):
                    raise SystemExit(f"error: replacement path too long: {fixed}")
                data[start:start + len(old)] = new + b"\0" * (len(old) - len(new))
                changes.append(f"{name} -> {fixed}")

        off += cmdsize

    if not changes:
        raise SystemExit("error: no macOS-specific load commands found")

    open(dst, "wb").write(data)
    print("\n".join(changes))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} <cloudflared-darwin-arm64> <output>")
    raise SystemExit(main(sys.argv[1], sys.argv[2]))

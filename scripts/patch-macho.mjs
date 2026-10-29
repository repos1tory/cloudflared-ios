#!/usr/bin/env node
// patch-macho.mjs — Node fallback for scripts/patch_macho.py.
//
// Adapts Cloudflare's darwin/arm64 cloudflared Mach-O for jailbroken iOS:
//   * LC_BUILD_VERSION platform -> iOS (2), minos -> 15.0
//   * macOS /Versions/A/ framework paths -> the iOS dyld shared-cache paths
// The caller still has to re-sign the result with ldid.
//
// Usage: node scripts/patch-macho.mjs <input> <output>
import fs from "node:fs";

const LC_LOAD_DYLIB = 0xc;
const LC_LOAD_UPWARD_DYLIB = 0x18f;
const LC_BUILD_VERSION = 0x32;
const MH_MAGIC_64 = 0xfeedfacf;
const CPU_TYPE_ARM64 = 0x0100000c;

const [, , src, dst] = process.argv;
if (!src || !dst) {
  console.error("usage: patch-macho.mjs <input> <output>");
  process.exit(2);
}

const data = Buffer.from(fs.readFileSync(src));
if (data.readUInt32LE(0) !== MH_MAGIC_64 || data.readInt32LE(4) !== CPU_TYPE_ARM64) {
  console.error("error: expected a 64-bit arm64 Mach-O");
  process.exit(1);
}
const ncmds = data.readUInt32LE(16);
const changes = [];
let off = 32;

for (let i = 0; i < ncmds; i++) {
  if (off + 8 > data.length) {
    console.error("error: corrupt load command table");
    process.exit(1);
  }
  const cmd = data.readUInt32LE(off);
  const cmdsize = data.readUInt32LE(off + 4);
  if (cmdsize < 8 || off + cmdsize > data.length) {
    console.error("error: corrupt load command table");
    process.exit(1);
  }

  if (cmd === LC_BUILD_VERSION) {
    const platform = data.readUInt32LE(off + 8);
    const minos = data.readUInt32LE(off + 12);
    data.writeUInt32LE(2, off + 8); // PLATFORM_IOS
    data.writeUInt32LE(0x000f0000, off + 12); // iOS 15.0
    changes.push(`platform ${platform} -> 2 (iOS); minos ${minos.toString(16)} -> f0000`);
  } else if (cmd === LC_LOAD_DYLIB || cmd === LC_LOAD_UPWARD_DYLIB) {
    const nameOff = data.readUInt32LE(off + 8);
    const start = off + nameOff;
    let end = start;
    while (end < data.length && data[end] !== 0) end++;
    if (end >= data.length) {
      console.error("error: unterminated dylib path");
      process.exit(1);
    }
    const name = data.toString("utf8", start, end);
    const fixed = name.replaceAll("/Versions/A/", "/");
    if (fixed !== name) {
      const oldLen = end - start + 1;
      const newBuf = Buffer.from(fixed + "\0", "utf8");
      if (newBuf.length > oldLen) {
        console.error(`error: replacement path too long: ${fixed}`);
        process.exit(1);
      }
      newBuf.copy(data, start);
      data.fill(0, start + newBuf.length, start + oldLen);
      changes.push(`${name} -> ${fixed}`);
    }
  }
  off += cmdsize;
}

if (changes.length === 0) {
  console.error("error: no macOS-specific load commands found");
  process.exit(1);
}
fs.writeFileSync(dst, data);
console.log(changes.join("\n"));

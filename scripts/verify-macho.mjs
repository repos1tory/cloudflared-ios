#!/usr/bin/env node
// verify-macho.mjs — assert the iOS port's Mach-O edits are present.
// Usage: node scripts/verify-macho.mjs <cloudflared>
import fs from "node:fs";

const LC_LOAD_DYLIB = 0xc;
const LC_LOAD_UPWARD_DYLIB = 0x18f;
const LC_BUILD_VERSION = 0x32;
const MH_MAGIC_64 = 0xfeedfacf;
const CPU_TYPE_ARM64 = 0x0100000c;

const file = process.argv[2];
if (!file) {
  console.error("usage: verify-macho.mjs <cloudflared>");
  process.exit(2);
}
const data = fs.readFileSync(file);
if (data.readUInt32LE(0) !== MH_MAGIC_64 || data.readInt32LE(4) !== CPU_TYPE_ARM64) {
  console.error("FAIL: not a 64-bit arm64 Mach-O");
  process.exit(1);
}
const ncmds = data.readUInt32LE(16);
let off = 32;
let platform = null;
let macPaths = [];
for (let i = 0; i < ncmds; i++) {
  const cmd = data.readUInt32LE(off);
  const cmdsize = data.readUInt32LE(off + 4);
  if (cmdsize < 8 || off + cmdsize > data.length) {
    console.error("FAIL: corrupt load command table");
    process.exit(1);
  }
  if (cmd === LC_BUILD_VERSION) {
    platform = data.readUInt32LE(off + 8);
  } else if (cmd === LC_LOAD_DYLIB || cmd === LC_LOAD_UPWARD_DYLIB) {
    const nameOff = data.readUInt32LE(off + 8);
    const start = off + nameOff;
    const end = data.indexOf(0, start);
    if (end < 0) {
      console.error("FAIL: unterminated dylib path");
      process.exit(1);
    }
    const name = data.toString("utf8", start, end);
    if (name.includes("/Versions/A/")) macPaths.push(name);
  }
  off += cmdsize;
}
if (platform !== 2) {
  console.error(`FAIL: LC_BUILD_VERSION platform is ${platform}, expected 2 (iOS)`);
  process.exit(1);
}
if (macPaths.length) {
  console.error("FAIL: macOS framework paths remain:\n  " + macPaths.join("\n  "));
  process.exit(1);
}
console.log("PASS: Mach-O platform is iOS and no macOS framework paths remain");

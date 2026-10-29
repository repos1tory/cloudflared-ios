#!/usr/bin/env node
// gzip.mjs <input> <output> — portable gzip for device builds without gzip(1).
import fs from "node:fs";
import zlib from "node:zlib";

const [, , input, output] = process.argv;
if (!input || !output) {
  console.error("usage: gzip.mjs <input> <output>");
  process.exit(2);
}
fs.writeFileSync(output, zlib.gzipSync(fs.readFileSync(input), { level: 9 }));

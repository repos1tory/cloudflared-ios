#!/usr/bin/env node
// gunzip.mjs <input> <output> — portable gzip decompression for device builds.
import fs from "node:fs";
import zlib from "node:zlib";

const [, , input, output] = process.argv;
if (!input || !output) {
  console.error("usage: gunzip.mjs <input> <output>");
  process.exit(2);
}
fs.writeFileSync(output, zlib.gunzipSync(fs.readFileSync(input)));

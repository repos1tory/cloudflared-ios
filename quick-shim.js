#!/usr/bin/env node
/* Local quick-tunnel provisioning shim.
 *
 * cloudflared 2026.10.3 sends an empty POST body when requesting a public quick
 * tunnel. Cloudflare's API currently stalls or answers 409 for that request on
 * iOS, while an explicit "{}" body succeeds. This shim listens on loopback only,
 * forwards POST /tunnel to the real service with "{}", and returns the JSON
 * unchanged. It never persists credentials.
 *
 * Usage: node quick-shim.js <port-file>
 * The chosen loopback port is written to <port-file> once listening.
 */
"use strict";

const fs = require("fs");
const http = require("http");
const https = require("https");

const portFile = process.argv[2] || "";
const UPSTREAM = "api.trycloudflare.com";
const TIMEOUT_MS = 7000; // two attempts stay under cloudflared's 15s client timeout

function reply(res, status, body) {
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  });
  res.end(body);
}

const server = http.createServer((req, res) => {
  if (req.method !== "POST" || req.url !== "/tunnel") {
    reply(res, 404, '{"success":false,"errors":[{"code":0,"message":"not found"}]}');
    return;
  }

  // Consume the (normally empty) request body before forwarding.
  req.resume();
  req.on("end", () => {
    const body = "{}";
    let answered = false;

    function attempt(n) {
      function finish(status, payload) {
        if (answered) return;
        answered = true;
        reply(res, status, payload);
      }

      const upstream = https.request(
        {
          hostname: UPSTREAM,
          port: 443,
          path: "/tunnel",
          method: "POST",
          family: 4,
          timeout: TIMEOUT_MS,
          headers: {
            "Content-Type": "application/json",
            "Content-Length": Buffer.byteLength(body),
            "User-Agent": "cloudflared-ios-quick-shim/1",
            "Accept": "application/json",
          },
        },
        (up) => {
          let data = "";
          up.setEncoding("utf8");
          up.on("data", (chunk) => {
            data += chunk;
            if (data.length > 1 << 20) {
              upstream.destroy();
              finish(
                502,
                '{"success":false,"errors":[{"code":0,"message":"upstream response too large"}]}'
              );
            }
          });
          up.on("end", () => finish(up.statusCode || 502, data));
        }
      );

      upstream.on("timeout", () => upstream.destroy(new Error("upstream timeout")));
      upstream.on("error", (err) => {
        if (answered) return;
        if (n === 0) {
          // A cold DNS/TLS connection occasionally stalls on iOS; retry once.
          attempt(1);
          return;
        }
        finish(
          502,
          JSON.stringify({ success: false, errors: [{ code: 0, message: String(err.message || err) }] })
        );
      });
      upstream.end(body);
    }

    attempt(0);
  });
});

server.on("error", (err) => {
  console.error("quick shim:", err.message);
  process.exit(1);
});

server.listen(0, "127.0.0.1", () => {
  const port = server.address().port;
  if (portFile) {
    try {
      fs.writeFileSync(portFile, String(port));
    } catch (err) {
      console.error("quick shim: cannot write port file:", err.message);
      process.exit(1);
    }
  }
  console.error("quick shim listening on 127.0.0.1:" + port);
});

for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => server.close(() => process.exit(0)));
}

#!/usr/bin/env bash
set -euo pipefail
image=${1:?Usage: bash scripts/smoke-image.sh IMAGE}
container=$(docker run -d "$image")
trap 'docker rm -f "$container" >/dev/null' EXIT
docker exec "$container" node -e '
const assert = require("node:assert/strict");
const fs = require("node:fs");
const crypto = require("node:crypto");
(async () => {
  let ready = false;
  for (let attempt = 0; attempt < 30; attempt++) {
    try {
      const response = await fetch("http://127.0.0.1:3000/healthz");
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {status: "ok"});
      ready = true;
      break;
    } catch (error) {
      if (attempt === 29) throw error;
      await new Promise(resolve => setTimeout(resolve, 500));
    }
  }
  assert.ok(ready);
  const response = await fetch("http://127.0.0.1:3000/");
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {service: "apptrust-workshop", version: process.env.APP_VERSION});
  assert.equal((await fetch("http://127.0.0.1:3000/missing")).status, 404);
  for (const [name, expected] of [
    ["log4j-api", "6e77bb229fc8dcaf09038beeb5e9030b22e9e01b51b458b0183ce669ebcc92ef"],
    ["log4j-core", "00bcf388472ca80a687014181763b66d777177f22cbbf179fd60e1b1ac9bc9b0"]
  ]) {
    const path = `/app/lib/${name}-2.24.1.jar`;
    const digest = crypto.createHash("sha256").update(fs.readFileSync(path)).digest("hex");
    assert.equal(digest, expected);
    console.log(`${path}: SHA-256 verified`);
  }
  assert.notEqual(process.getuid(), 0);
  console.log("Container HTTP endpoints, release version, JARs, and non-root user verified");
})().catch(error => { console.error(error); process.exit(1); });
'

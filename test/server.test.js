const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('../app/server');
for (const [path, status, expected] of [
  ['/healthz', 200, { status: 'ok' }],
  ['/', 200, { service: 'apptrust-workshop', version: process.env.APP_VERSION || 'local' }],
  ['/missing', 404, { error: 'Not found' }],
]) {
  test(`GET ${path} returns ${status}`, async (t) => {
    const server = createServer();
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(() => new Promise(resolve => server.close(resolve)));
    const response = await fetch(`http://127.0.0.1:${server.address().port}${path}`);
    assert.equal(response.status, status);
    assert.deepEqual(await response.json(), expected);
  });
}

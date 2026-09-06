const http = require('node:http');
function createServer() {
  return http.createServer((req, res) => {
    res.writeHead(['/healthz', '/'].includes(req.url) ? 200 : 404, { 'content-type': 'application/json' });
    res.end(JSON.stringify(req.url === '/healthz' ? { status: 'ok' } : req.url === '/' ?
      { service: 'apptrust-workshop', version: process.env.APP_VERSION || 'local' } : { error: 'Not found' }));
  });
}
if (require.main === module) createServer().listen(process.env.PORT || 3000, '0.0.0.0');
module.exports = { createServer };

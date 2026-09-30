// http-server.js
const http = require('http');

// This is a completely normal web server — it could serve any website.
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('just a normal web page, nothing WebSocket about this yet');
});

server.listen(3000, () => console.log('listening on http://localhost:3000'));

// make-real-jpeg.js
let sharp;
try {
  sharp = require('sharp');
} catch (err) {
  console.log('sharp is not available in this environment:', err.message.split('\n')[0]);
  console.log('skip this step — the rest of the lab does not need sharp.');
  process.exit(0);
}

sharp({ create: { width: 1600, height: 1200, channels: 3, background: { r: 80, g: 140, b: 200 } } })
  .jpeg()
  .toFile('samples/real-photo.jpg')
  .then(() => console.log('created a real JPEG'));

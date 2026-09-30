// create-sample-images.js
const { createBMP } = require('./bmp-utils');
const fs = require('fs');

fs.mkdirSync('samples', { recursive: true });
fs.mkdirSync('thumbs', { recursive: true });

const COUNT = 8;
for (let i = 0; i < COUNT; i++) {
  const seed = i * 37;
  const img = createBMP(1600, 1200, (x, y) => [
    (x + seed) % 256,
    (y + seed) % 256,
    (x + y + seed) % 256,
  ]);
  fs.writeFileSync(`samples/photo${i}.bmp`, img);
}
console.log(`created ${COUNT} real sample images in ./samples/`);

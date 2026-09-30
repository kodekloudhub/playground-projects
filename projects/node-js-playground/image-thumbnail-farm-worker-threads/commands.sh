#!/usr/bin/env bash
set -euo pipefail

node create-sample-images.js
ls -lh samples/

node blocking-demo.js

node main-basic.js

node nonblocking-demo.js

node pool-demo.js
ls -lh thumbs/

node transfer-compare.js

node shutdown-demo.js

node benchmark.js

npm install sharp@0.33.5

node make-real-jpeg.js
node -e "require('./resize-work-smart').resizeImageFileSmart('samples/real-photo.jpg','thumbs/real-photo-thumb.jpg',200,150).then(r => console.log('resized using engine:', r.engine))"
ls -lh samples/real-photo.jpg thumbs/real-photo-thumb.jpg

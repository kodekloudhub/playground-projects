// microtask-battle.js
process.nextTick(() => console.log('nextTick A'));
Promise.resolve().then(() => console.log('promise A'));
process.nextTick(() => console.log('nextTick B'));
Promise.resolve().then(() => console.log('promise B'));

setTimeout(() => console.log('timer (only after ALL microtasks are drained)'), 0);

console.log('sync');

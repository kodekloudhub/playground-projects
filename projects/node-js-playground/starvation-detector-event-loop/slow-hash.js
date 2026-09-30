// slow-hash.js
// One shared setting for "how heavy is one password hash?" Every server in this lab imports it, so the work is identical in every before/after test.
const crypto = require('crypto');

const ITERATIONS = 200000; // raise or lower this in Task 0 until one hash takes ~100-300ms
const KEY_LENGTH = 64;
const DIGEST = 'sha512';
const SALT = 'fixed-salt-for-this-lab'; // real apps use a random salt per user

function hashSync(password) {
  return crypto.pbkdf2Sync(password, SALT, ITERATIONS, KEY_LENGTH, DIGEST).toString('hex');
}

function hashAsync(password, callback) {
  crypto.pbkdf2(password, SALT, ITERATIONS, KEY_LENGTH, DIGEST, (err, key) => {
    if (err) return callback(err);
    callback(null, key.toString('hex'));
  });
}

module.exports = { hashSync, hashAsync, ITERATIONS };

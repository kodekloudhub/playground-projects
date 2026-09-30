// pool.js
const { Worker } = require('worker_threads');
const os = require('os');

class ThumbnailPool {
  constructor(workerFile, poolSize = os.cpus().length) {
    this.queue = [];       // jobs waiting for a free worker
    this.idleWorkers = []; // workers currently free
    this.allWorkers = [];

    for (let i = 0; i < poolSize; i++) {
      const worker = new Worker(workerFile);
      worker.id = i;
      this.allWorkers.push(worker);
      this.idleWorkers.push(worker);
    }
    console.log(`[pool] started with ${poolSize} workers`);
  }

  submit(jobData) {
    return new Promise((resolve, reject) => {
      this.queue.push({ jobData, resolve, reject });
      this._dispatch();
    });
  }

  _dispatch() {
    while (this.queue.length > 0 && this.idleWorkers.length > 0) {
      const worker = this.idleWorkers.pop();
      const job = this.queue.shift();

      console.log(`[pool] worker ${worker.id} picked up ${job.jobData.inputPath} (${this.queue.length} still queued)`);

      const onMessage = (result) => {
        console.log(`[pool] worker ${worker.id} finished -> ${result.outputPath}`);
        worker.off('message', onMessage);
        job.resolve(result);
        this.idleWorkers.push(worker);
        this._dispatch(); // this worker is free again — check the queue
      };

      worker.on('message', onMessage);
      worker.postMessage(job.jobData);
    }
  }

  async shutdown() {
    console.log(`[pool] shutdown requested, ${this.queue.length} jobs still queued, will be rejected`);

    this.queue.forEach((job) => job.reject(new Error('pool shutting down')));
    this.queue = [];

    const busyCount = this.allWorkers.length - this.idleWorkers.length;
    console.log(`[pool] waiting for ${busyCount} in-flight job(s) to finish...`);

    await new Promise((resolve) => {
      const check = setInterval(() => {
        if (this.idleWorkers.length === this.allWorkers.length) {
          clearInterval(check);
          resolve();
        }
      }, 50);
    });

    await Promise.all(this.allWorkers.map((w) => w.terminate()));
    console.log('[pool] all workers terminated — shutdown complete');
  }
}

module.exports = { ThumbnailPool };

// loop-monitor.js
const { monitorEventLoopDelay } = require('perf_hooks');

function startLoopMonitor() {
  // Node checks the loop every 10ms and records how LATE each check was.
  const histogram = monitorEventLoopDelay({ resolution: 10 });
  histogram.enable();

  const toMs = (ns) => (ns / 1e6).toFixed(1); // the histogram stores nanoseconds

  setInterval(() => {
    console.log(
      `[loop] delay p50=${toMs(histogram.percentile(50))}ms ` +
      `p99=${toMs(histogram.percentile(99))}ms ` +
      `max=${toMs(histogram.max)}ms`
    );
    histogram.reset(); // start fresh, so each line covers only the last second
  }, 1000);
}

module.exports = { startLoopMonitor };

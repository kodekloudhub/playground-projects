// diff.js
function diffOrder(predicted, actual) {
  return predicted.map((label, i) => ({
    position: i + 1,
    predicted: label,
    actual: actual[i],
    correct: label === actual[i],
  }));
}

function printDiff(rows) {
  console.log('\n--- Prediction vs. Reality ---');
  for (const row of rows) {
    const mark = row.correct ? '✅' : '❌';
    console.log(`${mark} position ${row.position}: predicted "${row.predicted}", actual "${row.actual}"`);
  }
  const score = rows.filter((r) => r.correct).length;
  console.log(`\nScore: ${score}/${rows.length}`);
}

module.exports = { diffOrder, printDiff };

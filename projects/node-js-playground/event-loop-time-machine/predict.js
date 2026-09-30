// predict.js
const readline = require('readline');

function askPrediction(labels) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

  return new Promise((resolve) => {
    console.log('\nThe 5 callbacks that will run:', labels.join(', '));

    function prompt() {
      rl.question('Type your predicted firing order, comma-separated: ', (answer) => {
        const predicted = answer.split(',').map((s) => s.trim());

        const unknown = predicted.filter((label) => !labels.includes(label));
        const isCompleteSet =
          predicted.length === labels.length && new Set(predicted).size === labels.length;

        if (unknown.length > 0) {
          console.log(`\nNot a real label: "${unknown.join('", "')}". Valid labels are: ${labels.join(', ')}`);
          prompt(); // ask again instead of accepting garbage
          return;
        }
        if (!isCompleteSet) {
          console.log(`\nYou need all 5 labels, each exactly once. You gave ${predicted.length}: ${predicted.join(', ')}`);
          prompt(); // ask again instead of accepting a partial/duplicated guess
          return;
        }

        rl.close();
        resolve(predicted);
      });
    }

    prompt();
  });
}

module.exports = { askPrediction };

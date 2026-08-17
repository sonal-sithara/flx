const path = require('path');
const Mocha = require('mocha');
const { glob } = require('glob');

/**
 * Entry point VS Code calls inside the extension host.
 */
async function run() {
  const mocha = new Mocha({
    // tdd, because the suite is written with suite/test rather than
    // describe/it — the convention VS Code's own extension samples use.
    ui: 'tdd',
    color: true,
    // Starting the language server means spawning `dart run`, which is slow
    // the first time.
    timeout: 120000,
  });

  const testsRoot = __dirname;
  const files = await glob('**/*.test.js', { cwd: testsRoot });
  for (const file of files) {
    mocha.addFile(path.resolve(testsRoot, file));
  }

  return new Promise((resolve, reject) => {
    mocha.run((failures) => {
      if (failures > 0) {
        reject(new Error(`${failures} test(s) failed`));
      } else {
        resolve();
      }
    });
  });
}

module.exports = { run };

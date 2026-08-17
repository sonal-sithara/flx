const fs = require('fs');
const os = require('os');
const path = require('path');
const { runTests } = require('@vscode/test-electron');

/**
 * Launches a real VS Code with this extension loaded and runs the suite
 * inside its extension host.
 *
 * The server itself is covered by Dart tests driven through the real LSP
 * framing. What is untested without this is the half in between: whether the
 * extension activates, finds the server, and speaks to it — which is exactly
 * where an installed extension fails.
 */
async function main() {
  const extensionDevelopmentPath = path.resolve(__dirname, '..');
  const extensionTestsPath = path.resolve(__dirname, 'suite', 'index.js');

  // The repository root, so the extension resolves the server the way a
  // developer checkout does: packages/flx_lsp, run from source.
  const workspace = path.resolve(__dirname, '..', '..', '..');

  const runtimeDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flxvsc-'));

  await runTests({
    extensionDevelopmentPath,
    extensionTestsPath,
    launchArgs: [
      workspace,
      // VS Code opens a Unix domain socket under the user-data dir, and those
      // cap at 103 characters. The default lands inside this project, whose
      // path is long enough to blow the limit, so keep it short and outside.
      '--user-data-dir', path.join(runtimeDir, 'user-data'),
      '--extensions-dir', path.join(runtimeDir, 'extensions'),
      // Other installed extensions would only add noise and startup time.
      '--disable-extensions',
      '--disable-gpu',
      '--no-sandbox',
    ],
  });
}

main().catch((error) => {
  console.error('Failed to run tests:', error);
  process.exit(1);
});

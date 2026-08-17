const path = require('path');
const fs = require('fs');
const vscode = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');

/** @type {LanguageClient | undefined} */
let client;

/**
 * Works out how to launch the server.
 *
 * A compiled executable starts in milliseconds; `dart run` takes a second or
 * two but always matches the checkout, which matters while the server itself
 * is under development. So source is the default and the binary is opt-in.
 */
function resolveServerOptions(folder) {
  const config = vscode.workspace.getConfiguration('flx');
  const explicit = config.get('server.path', '').trim();

  if (explicit) {
    return { command: explicit, args: [], transport: TransportKind.stdio };
  }

  const packagePath = config.get('server.packagePath', 'packages/flx_lsp');
  const entry = path.join(folder, packagePath, 'bin', 'flx_lsp.dart');

  if (!fs.existsSync(entry)) {
    throw new Error(
      `flx: cannot find the language server at ${entry}. ` +
        'Set "flx.server.packagePath" or "flx.server.path" in settings.'
    );
  }

  return {
    command: 'dart',
    args: ['run', entry],
    options: { cwd: path.join(folder, packagePath) },
    transport: TransportKind.stdio,
  };
}

function start() {
  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length === 0) return;
  const root = folders[0].uri.fsPath;

  let serverOptions;
  try {
    serverOptions = resolveServerOptions(root);
  } catch (error) {
    vscode.window.showErrorMessage(String(error.message ?? error));
    return;
  }

  const config = vscode.workspace.getConfiguration('flx');

  client = new LanguageClient(
    'flx',
    'flx Language Server',
    serverOptions,
    {
      documentSelector: [{ scheme: 'file', language: 'flx' }],
      synchronize: {
        fileEvents: vscode.workspace.createFileSystemWatcher('**/*.flx'),
      },
      initializationOptions: {
        semanticDiagnostics: config.get('semanticDiagnostics', true),
      },
      // The server writes nothing to stdout except protocol traffic, so any
      // stderr output is worth surfacing rather than swallowing.
      outputChannelName: 'flx',
    }
  );

  client.start();
}

async function stop() {
  if (!client) return;
  const stopping = client.stop();
  client = undefined;
  await stopping;
}

function activate(context) {
  start();

  context.subscriptions.push(
    vscode.commands.registerCommand('flx.restartServer', async () => {
      await stop();
      start();
      vscode.window.showInformationMessage('flx: language server restarted');
    })
  );

  // Relaunch when the launch settings change, since they only take effect at
  // startup.
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(async (event) => {
      if (!event.affectsConfiguration('flx.server') &&
          !event.affectsConfiguration('flx.semanticDiagnostics')) {
        return;
      }
      await stop();
      start();
    })
  );
}

function deactivate() {
  return stop();
}

module.exports = { activate, deactivate };

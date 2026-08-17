const path = require('path');
const fs = require('fs');
const vscode = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');

/** @type {LanguageClient | undefined} */
let client;

/**
 * Works out how to launch the server, most specific first: an explicit
 * setting, then a bundled binary, then the source checkout.
 *
 * A released VSIX carries a binary for its platform, so an installed
 * extension needs neither Dart nor a copy of this repository. Running from
 * source is the fallback, for working on the server itself — slower to start,
 * but always matching the checkout.
 */
function resolveServerOptions(context, folder) {
  const config = vscode.workspace.getConfiguration('flx');

  // 1. An explicit path always wins.
  const explicit = config.get('server.path', '').trim();
  if (explicit) {
    return { command: explicit, args: [], transport: TransportKind.stdio };
  }

  // 2. A bundled binary, which is what a released VSIX carries. Built per
  //    platform by .github/workflows/release.yml, because an installed
  //    extension cannot run the server from source — a user's Flutter project
  //    has no packages/flx_lsp.
  const bundled = path.join(
    context.extensionPath,
    'server',
    process.platform === 'win32' ? 'flx_lsp.exe' : 'flx_lsp'
  );
  if (fs.existsSync(bundled)) {
    return { command: bundled, args: [], transport: TransportKind.stdio };
  }

  // 3. From source, for working on the server itself. Slower to start, but
  //    always matches the checkout.
  const packagePath = config.get('server.packagePath', 'packages/flx_lsp');
  const entry = path.join(folder, packagePath, 'bin', 'flx_lsp.dart');
  if (!fs.existsSync(entry)) {
    throw new Error(
      'flx: no language server found. This build has no bundled binary and ' +
        `there is no source checkout at ${entry}. Set "flx.server.path" to a ` +
        'compiled flx_lsp, or "flx.server.packagePath" to the package.'
    );
  }
  return {
    command: 'dart',
    args: ['run', entry],
    options: { cwd: path.join(folder, packagePath) },
    transport: TransportKind.stdio,
  };
}

function start(context) {
  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length === 0) return;
  const root = folders[0].uri.fsPath;

  let serverOptions;
  try {
    serverOptions = resolveServerOptions(context, root);
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
  start(context);

  context.subscriptions.push(
    vscode.commands.registerCommand('flx.restartServer', async () => {
      await stop();
      start(context);
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
      start(context);
    })
  );
}

function deactivate() {
  return stop();
}

module.exports = { activate, deactivate };

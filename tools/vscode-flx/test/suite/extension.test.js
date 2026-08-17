const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vscode = require('vscode');

/// Polls until [check] returns something truthy, or gives up.
async function waitFor(check, { timeout = 60000, interval = 250, what }) {
  const deadline = Date.now() + timeout;
  let last;
  while (Date.now() < deadline) {
    last = await check();
    if (last !== undefined && last !== null && !(Array.isArray(last) && last.length === 0)) {
      return last;
    }
    await new Promise((r) => setTimeout(r, interval));
  }
  throw new Error(`timed out waiting for ${what}`);
}

/// Writes a .flx into a temporary directory inside the workspace and opens it.
///
/// Inside the workspace so the server, which indexes the workspace root on
/// initialize, treats it the way it would any other file.
let scratchDir;

function scratchFile(name, contents) {
  if (!scratchDir) {
    const root = vscode.workspace.workspaceFolders[0].uri.fsPath;
    scratchDir = fs.mkdtempSync(path.join(root, '.flx-vscode-test-'));
  }
  const file = path.join(scratchDir, name);
  fs.writeFileSync(file, contents);
  return vscode.Uri.file(file);
}

async function open(uri) {
  const document = await vscode.workspace.openTextDocument(uri);
  await vscode.window.showTextDocument(document);
  return document;
}

/// Offset of `|` in the text, with the marker removed.
function withCursor(marked) {
  const offset = marked.indexOf('|');
  assert.ok(offset >= 0, 'no | marker');
  return { text: marked.replace('|', ''), offset };
}

suite('flx extension', () => {
  suiteTeardown(() => {
    if (scratchDir) fs.rmSync(scratchDir, { recursive: true, force: true });
  });

  test('activates on a .flx file', async () => {
    const uri = scratchFile('activate.flx', 'composable A {\n  Text("hi")\n}\n');
    const document = await open(uri);

    assert.strictEqual(
      document.languageId,
      'flx',
      'the .flx extension should map to the flx language'
    );

    const extension = vscode.extensions.getExtension('flx.flx');
    assert.ok(extension, 'extension not found by id');
    await extension.activate();
    assert.ok(extension.isActive, 'extension did not activate');
  });

  test('publishes a syntax diagnostic from the language server', async () => {
    // Proves the whole chain: activation, spawning the server, the client
    // handshake, and diagnostics coming back.
    const uri = scratchFile(
      'broken.flx',
      'composable lower {\n  Text("hi")\n}\n'
    );
    await open(uri);

    const diagnostics = await waitFor(
      () => vscode.languages.getDiagnostics(uri),
      { what: 'diagnostics from the server' }
    );

    assert.strictEqual(diagnostics.length, 1);
    assert.match(diagnostics[0].message, /must start with a capital letter/);
    assert.match(diagnostics[0].message, /Lower/, 'the hint should be included');
    assert.strictEqual(diagnostics[0].source, 'flxc');
    assert.strictEqual(diagnostics[0].range.start.line, 0);
    assert.strictEqual(diagnostics[0].range.start.character, 11);
  });

  test('clears diagnostics once the file is fixed', async () => {
    const uri = scratchFile('fixme.flx', 'composable bad {\n  Text("hi")\n}\n');
    const document = await open(uri);

    await waitFor(() => vscode.languages.getDiagnostics(uri), {
      what: 'the initial error',
    });

    const edit = new vscode.WorkspaceEdit();
    edit.replace(
      uri,
      new vscode.Range(new vscode.Position(0, 11), new vscode.Position(0, 14)),
      'Good'
    );
    await vscode.workspace.applyEdit(edit);

    await waitFor(
      () => (vscode.languages.getDiagnostics(uri).length === 0 ? true : null),
      { what: 'diagnostics to clear' }
    );

    assert.ok(document.getText().includes('composable Good'));
  });

  test('offers hook completions in a binding', async () => {
    const { text, offset } = withCursor(
      'composable A {\n  val count = |\n  Text("hi")\n}\n'
    );
    const uri = scratchFile('complete.flx', text);
    const document = await open(uri);

    const list = await waitFor(
      async () => {
        const result = await vscode.commands.executeCommand(
          'vscode.executeCompletionItemProvider',
          uri,
          document.positionAt(offset)
        );
        return result && result.items.length ? result : null;
      },
      { what: 'completion items' }
    );

    const labels = list.items.map((i) =>
      typeof i.label === 'string' ? i.label : i.label.label
    );
    assert.ok(labels.includes('useState'), `no useState in: ${labels.slice(0, 12)}`);
    assert.ok(labels.includes('useFetch'));
  });

  test('offers widget completions in a children block', async () => {
    const { text, offset } = withCursor(
      'composable A {\n  Column {\n    |\n  }\n}\n'
    );
    const uri = scratchFile('children.flx', text);
    const document = await open(uri);

    const list = await waitFor(
      async () => {
        const result = await vscode.commands.executeCommand(
          'vscode.executeCompletionItemProvider',
          uri,
          document.positionAt(offset)
        );
        return result && result.items.length ? result : null;
      },
      { what: 'widget completions' }
    );

    const labels = list.items.map((i) =>
      typeof i.label === 'string' ? i.label : i.label.label
    );
    assert.ok(labels.includes('LazyColumn'), `no LazyColumn in: ${labels.slice(0, 12)}`);
    assert.ok(!labels.includes('useState'), 'hooks do not belong in the tree');
  });

  test('hovers a hook with its signature', async () => {
    const text = 'composable A {\n  val count = useState(0)\n  Text("hi")\n}\n';
    const uri = scratchFile('hover.flx', text);
    const document = await open(uri);

    const hovers = await waitFor(
      () =>
        vscode.commands.executeCommand(
          'vscode.executeHoverProvider',
          uri,
          document.positionAt(text.indexOf('useState') + 2)
        ),
      { what: 'a hover' }
    );

    const rendered = hovers
      .flatMap((h) => h.contents)
      .map((c) => (typeof c === 'string' ? c : c.value))
      .join('\n');
    assert.match(rendered, /StateRef<T> useState<T>/);
  });

  test('goes to the definition of a composable', async () => {
    const text =
      'composable Badge(label) {\n  Text(label)\n}\n\n' +
      'composable A {\n  Column {\n    Badge(label: "x")\n  }\n}\n';
    const uri = scratchFile('definition.flx', text);
    const document = await open(uri);

    const useSite = text.indexOf('Badge(label: "x")') + 2;
    const locations = await waitFor(
      () =>
        vscode.commands.executeCommand(
          'vscode.executeDefinitionProvider',
          uri,
          document.positionAt(useSite)
        ),
      { what: 'a definition' }
    );

    assert.ok(locations.length >= 1);
    assert.strictEqual(locations[0].range.start.line, 0, 'the declaration line');
  });

  test('lists composables in the outline', async () => {
    const uri = scratchFile(
      'symbols.flx',
      '@page("/one")\ncomposable One {\n  val x = useState(0)\n  Text("1")\n}\n\n' +
        'composable Two {\n  Text("2")\n}\n'
    );
    await open(uri);

    const symbols = await waitFor(
      () =>
        vscode.commands.executeCommand(
          'vscode.executeDocumentSymbolProvider',
          uri
        ),
      { what: 'document symbols' }
    );

    const names = symbols.map((s) => s.name);
    assert.deepStrictEqual(names, ['One', 'Two']);
    assert.ok(
      symbols[0].children.some((c) => c.name === 'x'),
      'bindings should nest under their composable'
    );
  });
});

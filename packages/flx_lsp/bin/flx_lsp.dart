import 'dart:io';

import 'package:flx_lsp/src/protocol.dart';
import 'package:flx_lsp/src/server.dart';

/// Entry point for the flx language server.
///
/// Speaks LSP over stdin/stdout, so stdout is reserved for protocol traffic —
/// anything diagnostic must go to stderr or it corrupts the stream.
Future<void> main(List<String> args) async {
  if (args.contains('--version')) {
    stdout.writeln('flx_lsp 0.2.0');
    return;
  }
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(
      'flx_lsp — language server for .flx\n\n'
      'Speaks LSP over stdio; editors launch it, you generally should not.\n\n'
      '  --version   print the version\n'
      '  --help      show this message\n',
    );
    return;
  }

  final connection = LspConnection(stdin, stdout.add);
  final server = FlxLanguageServer(connection)..onExit(exit);
  await server.serve();
}

/// The flx compiler, as a library.
///
/// `flxc` is usable in two ways: as the `flxc` command, and as this library.
/// The language server is built entirely on what is exported here, which is
/// the point — the editor and the build agree because they run the same
/// lexer, the same parser and the same spans.
///
/// The pipeline, in the order it runs:
///
/// ```dart
/// final source = Source('screen.flx', text);
/// final ast    = Parser.parse(source);              // throws FlxError
/// final dart   = CodeGenerator(ast, runtimeImport: 'package:flx_runtime/flx_runtime.dart')
///     .generate();
/// ```
///
/// Or all at once, over a directory:
///
/// ```dart
/// final result = Compiler().build('lib/pages');
/// ```
///
/// Errors are always [FlxError], which carries a [Span] and renders with a
/// caret and a hint. Everything else is a bug.
library flxc;

/// The syntax tree. Stable enough to build tooling on, and what the language
/// server's outline, hover and go-to-definition read.
export 'src/ast.dart';

/// Directory-level compilation and route-table generation.
export 'src/compiler.dart';

/// Running the Dart analyzer over generated code and reporting the results
/// against the `.flx` that produced it.
export 'src/dart_analysis.dart';

/// The one error type, with source location and a fix hint.
export 'src/diagnostics.dart';

/// Code generation, for callers that want the AST step separately.
export 'src/codegen.dart' show CodeGenerator;

/// Tokenisation. Exposed because tooling frequently needs tokens when the
/// file is too broken to parse.
export 'src/lexer.dart' show Lexer;

/// Parsing, plus the tables that decide what a `{ ... }` block means.
export 'src/parser.dart'
    show
        Parser,
        baseNameOf,
        builderWidgets,
        containerWidgets,
        layoutWidgets,
        scaffoldProviders;

/// Source text and the spans that point into it.
export 'src/source.dart';

/// Mapping a location in generated Dart back to the `.flx` behind it.
export 'src/sourcemap.dart';

/// Tokens.
export 'src/token.dart';

/// Rebuilding on change.
export 'src/watcher.dart' show Watcher;

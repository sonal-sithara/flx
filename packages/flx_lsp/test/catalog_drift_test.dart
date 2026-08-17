import 'dart:io';

import 'package:flx_lsp/src/catalog.dart';
import 'package:test/test.dart';

/// Keeps the hand-written catalog honest.
///
/// The catalog cannot be generated — the useful half of it is *when to reach
/// for a thing and what goes wrong if you don't*, which no signature carries.
/// The cost of writing it by hand is that it rots silently: someone adds a
/// widget to packages/flx, and the editor never mentions it again.
///
/// So this test reads the runtime and fails when the two disagree.
void main() {
  final runtime = Directory('../flx_runtime/lib/src');

  late String source;

  setUpAll(() {
    expect(runtime.existsSync(), isTrue,
        reason: 'expected packages/flx_runtime beside flx_lsp');
    source = runtime
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
  });

  /// Exported types that are not DSL widgets: engine internals, DI plumbing
  /// and value types. Adding to this list is a deliberate act.
  const notWidgets = <String>{
    'Composable',
    'FlxScope',
    'Injector',
    'Notifier',
    'ViewModel',
    'Disposable',
    'StateRef',
    'Ref',
    'AsyncValue',
    'RouteDef',
    'AppRouter',
    'Styles',
    'page',
    'ItemBuilder',
    'Provider',
  };

  test('every public widget in flx is documented', () {
    final declared = RegExp(
      r'^class\s+([A-Z]\w*)(?:<[^>]*>)?\s+extends\s+(StatelessWidget|StatefulWidget)',
      multiLine: true,
    )
        .allMatches(source)
        .map((m) => m.group(1)!)
        .where((name) => !name.startsWith('_'))
        .where((name) => !notWidgets.contains(name))
        .toSet();

    final documented = {for (final symbol in allWidgets) symbol.name};
    final missing = declared.difference(documented);

    expect(
      missing,
      isEmpty,
      reason: 'these widgets exist in packages/flx but the language server '
          'will never suggest them — add them to catalog.dart (or to '
          'notWidgets in this test if they are not DSL widgets): $missing',
    );
  });

  test('every public hook in flx is documented', () {
    // A hook is a top-level function named use*, so the match must start at
    // column zero — `useState(0)` inside a method body must not count.
    final declared = RegExp(
      r'^[A-Za-z_][\w<>?,\s.]*?\b(use[A-Z]\w*)\s*(?:<[^>]*>)?\s*\(',
      multiLine: true,
    )
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

    final documented = {for (final hook in hooks) hook.name};
    final missing = declared.difference(documented);

    expect(
      missing,
      isEmpty,
      reason: 'these hooks exist in packages/flx but are undocumented in '
          'catalog.dart: $missing',
    );
  });

  test('the catalog does not describe things that no longer exist', () {
    final documented = [
      for (final symbol in allWidgets)
        if (!const {
          // Flutter's own widgets, legitimately offered but not declared here.
          'Text', 'Icon', 'SizedBox', 'Spacer', 'Divider',
          'Column', 'Row', 'Stack', 'Wrap',
          // Flutter's own builder-shaped widgets, documented so the DSL's
          // interop story is discoverable from the editor.
          'LayoutBuilder', 'StreamBuilder', 'FutureBuilder',
          'ValueListenableBuilder', 'AnimatedBuilder', 'Builder',
          'Scaffold', 'AppBar',
        }.contains(symbol.name))
          symbol.name,
      for (final hook in hooks) hook.name,
    ];

    final stale = [
      for (final name in documented)
        if (!RegExp('\\b$name\\b').hasMatch(source)) name,
    ];

    expect(stale, isEmpty,
        reason: 'the catalog documents symbols that packages/flx no longer '
            'exports: $stale');
  });

  group('catalog integrity', () {
    test('every symbol has a signature and documentation', () {
      for (final symbol in [...hooks, ...allWidgets, ...keywords]) {
        expect(symbol.signature, isNotEmpty, reason: symbol.name);
        expect(symbol.documentation.length, greaterThan(20),
            reason: '${symbol.name} needs a real explanation');
      }
    });

    test('names are unique', () {
      final names = [...hooks, ...allWidgets, ...keywords].map((s) => s.name);
      expect(names.toSet().length, names.length,
          reason: 'a duplicate would shadow itself in hover lookup');
    });

    test('every widget with arguments is in widgetArguments', () {
      // Layout widgets get their arguments from layoutArguments instead.
      const layoutNames = {'Column', 'Row', 'Stack', 'Wrap'};
      final undocumented = [
        for (final widget in allWidgets)
          if (!layoutNames.contains(widget.name) &&
              !widgetArguments.containsKey(widget.name) &&
              widget.signature.contains('{'))
            widget.name,
      ];

      expect(undocumented, isEmpty,
          reason: 'these widgets take named arguments the server cannot '
              'suggest: $undocumented');
    });

    test('shorthand argument names line up with flxc', () {
      // These must match _shorthandTypes in flxc's codegen, or the editor
      // offers a completion the compiler then rejects.
      const compilerKnows = {
        'style': 'Styles',
        'main': 'MainAxisAlignment',
        'cross': 'CrossAxisAlignment',
        'alignment': 'Alignment',
        'textAlign': 'TextAlign',
        'overflow': 'TextOverflow',
        'fit': 'BoxFit',
        'axis': 'Axis',
        'keyboard': 'TextInputType',
        'size': 'MainAxisSize',
      };

      compilerKnows.forEach((argument, type) {
        final entry = shorthandValues[argument];
        expect(entry, isNotNull,
            reason: 'flxc resolves `$argument:` but the server does not offer '
                'its values');
        expect(entry!.$1, type, reason: 'wrong type for `$argument:`');
      });
    });
  });
}

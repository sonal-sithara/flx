import 'dart:async';
import 'dart:io';

import 'compiler.dart';
import 'diagnostics.dart';

/// Rebuilds on every `.flx` change under a directory.
///
/// A failed build never stops the watcher — the error is printed and the
/// next save gets another chance, which is the whole point of watch mode.
class Watcher {
  Watcher(this.dir, this.compiler, {this.debounce = const Duration(milliseconds: 80)});

  final String dir;
  final Compiler compiler;

  /// Editors often emit several events per save (write, truncate, rename),
  /// so changes are coalesced before rebuilding.
  final Duration debounce;

  Timer? _pending;

  Future<void> run() async {
    _build(initial: true);

    final target = Directory(dir);
    if (!target.existsSync()) {
      stderr.writeln("flxc: no such directory: '$dir'");
      exitCode = 1;
      return;
    }

    stdout.writeln('flxc: watching $dir for changes — Ctrl-C to stop');

    // Watching recursively is not supported on every platform; fall back to
    // polling the modification times when it isn't.
    if (FileSystemEntity.isWatchSupported) {
      await for (final event in target.watch(recursive: true)) {
        if (!event.path.endsWith('.flx')) continue;
        _schedule();
      }
    } else {
      await _poll(target);
    }
  }

  void _schedule() {
    _pending?.cancel();
    _pending = Timer(debounce, () => _build(initial: false));
  }

  Future<void> _poll(Directory target) async {
    var previous = _snapshot(target);
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final current = _snapshot(target);
      if (!_sameSnapshot(previous, current)) {
        previous = current;
        _build(initial: false);
      }
    }
  }

  Map<String, DateTime> _snapshot(Directory target) => {
        for (final f in target
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.flx')))
          f.path: f.statSync().modified,
      };

  static bool _sameSnapshot(Map<String, DateTime> a, Map<String, DateTime> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _build({required bool initial}) {
    final started = DateTime.now();
    try {
      final result = compiler.build(dir);
      final ms = DateTime.now().difference(started).inMilliseconds;
      stdout.writeln(
        'flxc: ${initial ? 'built' : 'rebuilt'} ${result.files.length} file(s), '
        '${result.pageCount} route(s) in ${ms}ms',
      );
    } on FlxError catch (e) {
      stderr.writeln(e.render());
      stderr.writeln('flxc: build failed — waiting for changes');
    } on FileSystemException catch (e) {
      stderr.writeln('flxc: ${e.message} (${e.path})');
    }
  }
}

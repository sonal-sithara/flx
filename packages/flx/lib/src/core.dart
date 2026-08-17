import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

// ============================================================
// flx hooks engine — zero dependencies.
//
// How it works (same principle as React):
// Each Composable keeps an ordered list of "slots". Every time
// build() runs, a cursor walks the list; each use*() call claims
// the next slot. That's why hooks must be called in the same
// order on every build (no hooks inside if/for).
// ============================================================

_ComposableState? _current;

_ComposableState get _ctx {
  final c = _current;
  if (c == null) {
    throw FlutterError(
      'Hooks can only be called inside the build() of a Composable.\n'
      'If this is a callback, capture the hook in a `val` during build and '
      'use the captured value inside the callback instead.',
    );
  }
  return c;
}

/// Base class for hook-enabled widgets. Extend this instead of
/// StatelessWidget/StatefulWidget:
///
/// class ProfileScreen extends Composable {
///   const ProfileScreen({super.key});
///   @override
///   Widget build(BuildContext context) {
///     final count = useState(0);
///     ...
///   }
/// }
abstract class Composable extends StatefulWidget {
  const Composable({super.key});

  Widget build(BuildContext context);

  @override
  State<Composable> createState() => _ComposableState();
}

class _ComposableState extends State<Composable> {
  final List<_Slot> _slots = [];
  final List<_EffectSlot> _pendingEffects = [];
  int _cursor = 0;
  bool _building = false;
  bool _frameScheduled = false;

  @override
  Widget build(BuildContext context) {
    final previous = _current;
    _current = this;
    _cursor = 0;
    _building = true;
    try {
      final built = widget.build(context);
      _assertStableHookCount();
      return built;
    } finally {
      _building = false;
      _current = previous;
      if (_pendingEffects.isNotEmpty) _scheduleEffects();
    }
  }

  /// Hooks are positional, so a build that claims fewer slots than the last
  /// one means a hook was called conditionally. Left unchecked this shows up
  /// much later as a value mysteriously belonging to the wrong hook.
  void _assertStableHookCount() {
    assert(() {
      if (_cursor < _slots.length) {
        throw FlutterError(
          'A Composable called fewer hooks on this build than the last one '
          '(${_cursor} vs ${_slots.length}).\n'
          'Hooks must run in the same order every build — move any use*() '
          'call out of an if, loop or early return.',
        );
      }
      return true;
    }());
  }

  T _use<T extends _Slot>(T Function() create) {
    if (_cursor >= _slots.length) {
      _slots.add(create());
    } else if (_slots[_cursor] is! T) {
      // Hook order changed (usually a hot reload) —
      // dispose and rebuild slots from this point.
      for (var i = _cursor; i < _slots.length; i++) {
        _pendingEffects.remove(_slots[i]);
        _slots[i].dispose();
      }
      _slots.removeRange(_cursor, _slots.length);
      _slots.add(create());
    }
    return _slots[_cursor++] as T;
  }

  void _requestRebuild() {
    if (!mounted) return;
    if (_building) return; // the new value is read later in this same build
    setState(() {});
  }

  /// Effects run after the frame, never during build. Running them inline
  /// would make `useEffect(() => nav.push(...))` throw, and would let a
  /// setState land in the middle of the build it belongs to.
  void _scheduleEffects() {
    if (_frameScheduled) return;
    _frameScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (!mounted) return;
      final due = List<_EffectSlot>.of(_pendingEffects);
      _pendingEffects.clear();
      for (final slot in due) {
        slot.run();
      }
    });
  }

  @override
  void dispose() {
    for (final s in _slots) {
      s.dispose();
    }
    _slots.clear();
    _pendingEffects.clear();
    super.dispose();
  }
}

abstract class _Slot {
  void dispose() {}
}

bool _sameKeys(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ============================================================
// Core hooks
// ============================================================

/// Reactive state. Setting .value rebuilds the widget.
class StateRef<T> extends _Slot {
  StateRef(this._value, this._owner);

  T _value;
  final _ComposableState _owner;

  T get value => _value;

  set value(T next) {
    if (identical(next, _value) || next == _value) return;
    _value = next;
    _owner._requestRebuild();
  }

  /// Derives the next value from the current one:
  ///   count.update((n) => n + 1)
  void update(T Function(T current) transform) => value = transform(_value);

  @override
  String toString() => 'StateRef($_value)';
}

StateRef<T> useState<T>(T initial) {
  final ctx = _ctx;
  return ctx._use(() => StateRef<T>(initial, ctx));
}

/// Mutable holder that does NOT trigger rebuilds.
class Ref<T> extends _Slot {
  Ref(this.value);
  T value;
}

Ref<T> useRef<T>(T initial) => _ctx._use(() => Ref<T>(initial));

/// Caches an expensive computation until [keys] change.
class _MemoSlot<T> extends _Slot {
  List<Object?>? keys;
  late T value;
}

T useMemoized<T>(T Function() create, [List<Object?> keys = const []]) {
  final slot = _ctx._use(() => _MemoSlot<T>());
  if (slot.keys == null || !_sameKeys(slot.keys!, keys)) {
    slot.keys = List.of(keys);
    slot.value = create();
  }
  return slot.value;
}

/// Side effects with cleanup. Runs after the frame in which [keys] changed
/// (or after every build when keys is null). Return a cleanup function or
/// null.
class _EffectSlot extends _Slot {
  List<Object?>? keys;
  bool hasRun = false;
  bool isPending = false;
  void Function()? Function()? effect;
  void Function()? cleanup;

  void run() {
    isPending = false;
    cleanup?.call();
    cleanup = effect?.call();
  }

  @override
  void dispose() {
    cleanup?.call();
    cleanup = null;
    effect = null;
  }
}

void useEffect(
  void Function()? Function() effect, [
  List<Object?>? keys,
]) {
  final ctx = _ctx;
  final slot = ctx._use(() => _EffectSlot());
  final shouldRun = !slot.hasRun ||
      keys == null ||
      slot.keys == null ||
      !_sameKeys(slot.keys!, keys);

  // Always hold the newest closure so the effect sees this build's values.
  slot.effect = effect;

  if (shouldRun) {
    slot.hasRun = true;
    slot.keys = keys == null ? null : List.of(keys);
    if (!slot.isPending) {
      slot.isPending = true;
      ctx._pendingEffects.add(slot);
    }
  }
}

/// Returns a callback that schedules a rebuild of this Composable.
///
/// The escape hatch for bridging external change sources — a ViewModel, a
/// stream, a Listenable — into the hooks engine.
VoidCallback useRebuild() => _ctx._requestRebuild;

/// Rebuilds whenever [listenable] notifies. Works with ValueNotifier,
/// AnimationController, ScrollController and anything else Flutter exposes
/// as a Listenable.
T useListenable<T extends Listenable>(T listenable) {
  final rebuild = useRebuild();
  useEffect(() {
    listenable.addListener(rebuild);
    return () => listenable.removeListener(rebuild);
  }, [listenable]);
  return listenable;
}

/// A TextEditingController tied to this Composable's lifetime.
class _DisposableSlot<T> extends _Slot {
  _DisposableSlot(this.value, this._dispose);
  final T value;
  final void Function(T) _dispose;

  @override
  void dispose() => _dispose(value);
}

TextEditingController useTextEditingController({String text = ''}) {
  final slot = _ctx._use(
    () => _DisposableSlot<TextEditingController>(
      TextEditingController(text: text),
      (c) => c.dispose(),
    ),
  );
  return slot.value;
}

/// A FocusNode tied to this Composable's lifetime.
FocusNode useFocusNode() {
  final slot = _ctx._use(
    () => _DisposableSlot<FocusNode>(FocusNode(), (n) => n.dispose()),
  );
  return slot.value;
}

/// The BuildContext of the Composable currently building.
///
/// Context-dependent hooks (useTheme, useNavigator, ...) build on this.
/// Rule: grab them in a `val` during build, then use inside callbacks:
///   val nav = useNavigator()
///   Button("Back") { nav.pop() }
BuildContext useContext() => _ctx.context;

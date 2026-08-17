import 'package:flutter/widgets.dart';

// ============================================================
// clean_ui hooks engine — zero dependencies, ~150 lines.
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
  assert(
    c != null,
    'Hooks can only be called inside the build() of a Composable.',
  );
  return c!;
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
  int _cursor = 0;
  bool _building = false;

  @override
  Widget build(BuildContext context) {
    final prev = _current;
    _current = this;
    _cursor = 0;
    _building = true;
    try {
      return widget.build(context);
    } finally {
      _building = false;
      _current = prev;
    }
  }

  T _use<T extends _Slot>(T Function() create) {
    if (_cursor >= _slots.length) {
      _slots.add(create());
    } else if (_slots[_cursor] is! T) {
      // Hook order changed (usually a hot reload) —
      // dispose and rebuild slots from this point.
      for (var i = _cursor; i < _slots.length; i++) {
        _slots[i].dispose();
      }
      _slots.removeRange(_cursor, _slots.length);
      _slots.add(create());
    }
    final slot = _slots[_cursor] as T;
    _cursor++;
    return slot;
  }

  void _requestRebuild() {
    if (_building) return; // value will be read later in this same build
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final s in _slots) {
      s.dispose();
    }
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

  set value(T v) {
    if (identical(v, _value) || v == _value) return;
    _value = v;
    _owner._requestRebuild();
  }
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

/// Side effects with cleanup. Runs when [keys] change
/// (or every build if keys is null). Return a cleanup function
/// or null.
class _EffectSlot extends _Slot {
  List<Object?>? keys;
  bool hasRun = false;
  void Function()? cleanup;

  @override
  void dispose() => cleanup?.call();
}

void useEffect(
  void Function()? Function() effect, [
  List<Object?>? keys,
]) {
  final slot = _ctx._use(() => _EffectSlot());
  final shouldRun = !slot.hasRun ||
      keys == null ||
      slot.keys == null ||
      !_sameKeys(slot.keys!, keys);
  if (shouldRun) {
    slot.cleanup?.call();
    slot.hasRun = true;
    slot.keys = keys == null ? null : List.of(keys);
    slot.cleanup = effect();
  }
}

/// The BuildContext of the Composable currently building.
///
/// Context-dependent hooks (useTheme, useNavigator, ...) build on this.
/// Rule: grab them in a `val` during build, then use inside callbacks:
///   val nav = useNavigator()
///   Button("Back") { nav.pop() }
BuildContext useContext() => _ctx.context;

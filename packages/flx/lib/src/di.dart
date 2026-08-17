import 'package:flutter/widgets.dart';

import 'core.dart';

/// Implement this on anything the [Injector] should tear down with the scope.
abstract class Disposable {
  void dispose();
}

typedef Provider<T> = T Function(Injector injector);

/// A small, explicit DI container.
///
/// Registration happens once at startup; [get] resolves by type. Scopes nest,
/// so a screen can override a service for its subtree without touching the
/// root — which is what makes tests able to swap a repository for a fake.
class Injector {
  Injector({Injector? parent}) : _parent = parent;

  final Injector? _parent;
  final _providers = <Type, Provider<Object?>>{};
  final _singletons = <Type, Object?>{};
  final _isSingleton = <Type>{};

  /// A new instance on every [get].
  void factory<T extends Object>(Provider<T> create) {
    _providers[T] = create;
    _isSingleton.remove(T);
    _singletons.remove(T);
  }

  /// One lazily-created instance, cached for the life of this scope.
  void singleton<T extends Object>(Provider<T> create) {
    _providers[T] = create;
    _isSingleton.add(T);
    _singletons.remove(T);
  }

  /// An already-built instance. Not disposed by this scope — whoever
  /// constructed it owns it.
  void value<T extends Object>(T instance) {
    _providers[T] = (_) => instance;
    _isSingleton.remove(T);
    _singletons[T] = instance;
  }

  bool has<T extends Object>() =>
      _providers.containsKey(T) || (_parent?.has<T>() ?? false);

  /// Resolves [T], walking up to parent scopes. Throws a readable error
  /// rather than returning null — a missing registration is a bug, not a
  /// state to handle.
  T get<T extends Object>() {
    final provider = _providers[T];
    if (provider == null) {
      final parent = _parent;
      if (parent != null) return parent.get<T>();
      throw StateError(
        'No provider registered for $T.\n'
        'Register it before runApp:\n'
        '  final injector = Injector()\n'
        '    ..singleton<$T>((i) => $T());\n'
        'and wrap your app in FlxScope(injector: injector, child: ...).',
      );
    }
    if (_isSingleton.contains(T)) {
      return (_singletons[T] ??= provider(this)) as T;
    }
    return provider(this) as T;
  }

  /// Disposes every [Disposable] this scope built itself.
  ///
  /// Instances handed over through [value] are deliberately left alone —
  /// this scope never constructed them, so it does not own their lifetime.
  void dispose() {
    for (final type in _isSingleton) {
      final instance = _singletons[type];
      if (instance is Disposable) instance.dispose();
    }
    _singletons.clear();
    _providers.clear();
    _isSingleton.clear();
  }
}

/// Publishes an [Injector] to a widget subtree.
///
///   runApp(FlxScope(injector: injector, child: App()));
class FlxScope extends InheritedWidget {
  const FlxScope({required this.injector, required super.child, super.key});

  final Injector injector;

  static Injector of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FlxScope>();
    if (scope == null) {
      throw FlutterError(
        'useInject() was called with no FlxScope above it.\n'
        'Wrap your app: runApp(FlxScope(injector: injector, child: App()));',
      );
    }
    return scope.injector;
  }

  @override
  bool updateShouldNotify(FlxScope oldWidget) =>
      oldWidget.injector != injector;
}

/// Resolves a dependency from the nearest [FlxScope].
///
///   val auth = useInject<AuthService>()
T useInject<T extends Object>() => FlxScope.of(useContext()).get<T>();

/// Anything that announces "I changed" to interested listeners.
///
/// Kept separate from [ViewModel] so non-UI objects — a repository, a sync
/// engine, a clock — can be change sources without pretending to be screen
/// state. A ViewModel that depends on one simply listens to it and re-notifies.
abstract class Notifier implements Disposable {
  final _listeners = <VoidCallback>{};
  bool _disposed = false;

  bool get isDisposed => _disposed;

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @protected
  void notify() {
    if (_disposed) return;
    // Copy first: a listener may remove itself while being notified.
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}

/// Base class for screen state that outlives a single build.
///
/// A ViewModel holds the logic; the composable stays a pure function of it.
/// Call [notify] after mutating state to rebuild every listening composable.
abstract class ViewModel extends Notifier {}

/// Resolves a [ViewModel] and rebuilds this composable whenever it notifies.
///
///   val vm = useViewModel<TodosViewModel>()
T useViewModel<T extends ViewModel>() {
  final vm = FlxScope.of(useContext()).get<T>();
  final rebuild = useRebuild();
  useEffect(() {
    vm.addListener(rebuild);
    return () => vm.removeListener(rebuild);
  }, [vm]);
  return vm;
}

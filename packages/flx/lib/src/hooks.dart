import 'dart:async';

import 'core.dart';

// ============================================================
// Higher-level hooks — all built on our own core, no packages.
// ============================================================

/// Result of an async operation: loading / data / error.
class AsyncValue<T> {
  const AsyncValue.loading()
      : data = null,
        error = null,
        isLoading = true;

  const AsyncValue.withData(this.data)
      : error = null,
        isLoading = false;

  const AsyncValue.withError(this.error)
      : data = null,
        isLoading = false;

  final T? data;
  final Object? error;
  final bool isLoading;

  bool get hasData => !isLoading && error == null;
  bool get hasError => error != null;

  /// Exhaustive pattern matching:
  /// user.when(
  ///   loading: () => Spinner(),
  ///   error: (e) => Text('$e'),
  ///   data: (u) => Text(u.name),
  /// )
  R when<R>({
    required R Function(T data) data,
    required R Function() loading,
    required R Function(Object error) error,
  }) {
    if (isLoading) return loading();
    final err = this.error;
    if (err != null) return error(err);
    return data(this.data as T);
  }
}

/// Declarative data fetching:
/// final user = useFetch(fetchCurrentUser);
/// Re-fetches when [keys] change.
AsyncValue<T> useFetch<T>(
  Future<T> Function() fetcher, {
  List<Object?> keys = const [],
}) {
  final state = useState<AsyncValue<T>>(const AsyncValue.loading());

  useEffect(() {
    var cancelled = false;
    state.value = AsyncValue<T>.loading();

    Future<void> run() async {
      try {
        final result = await fetcher();
        if (!cancelled) state.value = AsyncValue<T>.withData(result);
      } catch (e) {
        if (!cancelled) state.value = AsyncValue<T>.withError(e);
      }
    }

    run();
    return () => cancelled = true;
  }, keys);

  return state.value;
}

/// Run a callback repeatedly:
/// useInterval(tick, const Duration(seconds: 1));
void useInterval(void Function() callback, Duration delay) {
  final saved = useRef(callback);
  saved.value = callback;
  useEffect(() {
    final t = Timer.periodic(delay, (_) => saved.value());
    return t.cancel;
  }, [delay]);
}

/// Debounced value — updates only after [delay] of no changes:
/// final query = useDebounced(searchText.value, const Duration(milliseconds: 300));
T useDebounced<T>(T value, Duration delay) {
  final state = useState(value);
  useEffect(() {
    final t = Timer(delay, () => state.value = value);
    return t.cancel;
  }, [value]);
  return state.value;
}

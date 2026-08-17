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

/// Subscribes to a [stream] and rebuilds on every event.
///
/// The stream counterpart of [useFetch], and the reason BLoC-style and
/// Riverpod-style sources compose with flx at all: their state arrives as a
/// stream, not a future.
///
///   val state = useStream(bloc.stream, initialData: bloc.state)
///
/// In a `val`, flxc generates the same `AsyncValue.when` wrapping as
/// [useFetch], so the name refers to the resolved value below.
///
/// [initialData] skips the loading state — pass a bloc's current state and the
/// first frame already has data. A null [initialData] means "start loading",
/// which for a nullable T is indistinguishable from an initial null; use
/// [useFetch] or a non-nullable wrapper if that distinction matters.
///
/// The subscription is cancelled on dispose and whenever [stream] or [keys]
/// change.
AsyncValue<T> useStream<T>(
  Stream<T> stream, {
  T? initialData,
  List<Object?> keys = const [],
}) {
  final state = useState<AsyncValue<T>>(
    initialData == null
        ? AsyncValue<T>.loading()
        : AsyncValue<T>.withData(initialData),
  );

  useEffect(() {
    final subscription = stream.listen(
      (event) => state.value = AsyncValue<T>.withData(event),
      onError: (Object error) => state.value = AsyncValue<T>.withError(error),
    );
    return subscription.cancel;
  }, [stream, ...keys]);

  return state.value;
}

/// The latest value of a [stream], without the loading and error states.
///
/// For sources that always have a current value — a bloc, a behaviour subject,
/// a ticker — where `.when` wrapping is noise.
T useStreamValue<T>(T initial, Stream<T> stream, {List<Object?> keys = const []}) {
  final state = useState<T>(initial);
  useEffect(() {
    final subscription = stream.listen((event) => state.value = event);
    return subscription.cancel;
  }, [stream, ...keys]);
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flx/flx.dart';

/// A Composable whose body is supplied per-test.
class Probe extends Composable {
  const Probe(this.body, {super.key});

  final Widget Function(BuildContext context) body;

  @override
  Widget build(BuildContext context) => body(context);
}

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('useState', () {
    testWidgets('rebuilds when the value changes', (tester) async {
      late StateRef<int> count;
      await tester.pumpWidget(wrap(Probe((_) {
        count = useState(0);
        return Text('${count.value}', textDirection: TextDirection.ltr);
      })));

      expect(find.text('0'), findsOneWidget);
      count.value = 1;
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('does not rebuild when set to an equal value',
        (tester) async {
      var builds = 0;
      late StateRef<int> count;
      await tester.pumpWidget(wrap(Probe((_) {
        builds++;
        count = useState(7);
        return const SizedBox();
      })));

      expect(builds, 1);
      count.value = 7;
      await tester.pump();
      expect(builds, 1, reason: 'setting an equal value is a no-op');
    });

    testWidgets('update() derives the next value', (tester) async {
      late StateRef<int> count;
      await tester.pumpWidget(wrap(Probe((_) {
        count = useState(10);
        return Text('${count.value}', textDirection: TextDirection.ltr);
      })));

      count.update((n) => n * 3);
      await tester.pump();
      expect(find.text('30'), findsOneWidget);
    });

    testWidgets('state survives rebuilds of the parent', (tester) async {
      late StateRef<int> count;
      Widget build(String title) => wrap(
            Column(children: [
              Text(title, textDirection: TextDirection.ltr),
              Probe((_) {
                count = useState(0);
                return Text('n=${count.value}',
                    textDirection: TextDirection.ltr);
              }),
            ]),
          );

      await tester.pumpWidget(build('a'));
      count.value = 5;
      await tester.pump();
      await tester.pumpWidget(build('b'));

      expect(find.text('n=5'), findsOneWidget);
    });
  });

  group('useEffect', () {
    testWidgets('runs after the frame, not during build', (tester) async {
      final order = <String>[];

      await tester.pumpWidget(wrap(Probe((_) {
        order.add('build');
        useEffect(() {
          order.add('effect');
          return null;
        }, const []);
        return const SizedBox();
      })));

      expect(order, ['build', 'effect'],
          reason: 'an effect running inside build would make '
              'Navigator.push throw');
    });

    testWidgets('can navigate — the reason effects are deferred',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Probe((context) {
          final nav = useNavigator();
          useEffect(() {
            nav.push(MaterialPageRoute<void>(
              builder: (_) => const Text('pushed',
                  textDirection: TextDirection.ltr),
            ));
            return null;
          }, const []);
          return const Text('home', textDirection: TextDirection.ltr);
        }),
      ));

      await tester.pumpAndSettle();
      expect(find.text('pushed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('runs once for a constant key list', (tester) async {
      var runs = 0;
      late StateRef<int> tick;

      await tester.pumpWidget(wrap(Probe((_) {
        tick = useState(0);
        useEffect(() {
          runs++;
          return null;
        }, const []);
        return Text('${tick.value}', textDirection: TextDirection.ltr);
      })));

      expect(runs, 1);
      tick.value = 1;
      await tester.pump();
      await tester.pump();
      expect(runs, 1);
    });

    testWidgets('re-runs and cleans up when keys change', (tester) async {
      final log = <String>[];
      late StateRef<int> key;

      await tester.pumpWidget(wrap(Probe((_) {
        key = useState(0);
        // Capture this build's value, the way a React effect closes over its
        // render's props — reading key.value later would see the new one.
        final captured = key.value;
        useEffect(() {
          log.add('run $captured');
          return () => log.add('cleanup $captured');
        }, [captured]);
        return const SizedBox();
      })));

      expect(log, ['run 0']);
      key.value = 1;
      await tester.pump();
      await tester.pump();
      expect(log, ['run 0', 'cleanup 0', 'run 1']);
    });

    testWidgets('runs every build when keys is null', (tester) async {
      var runs = 0;
      late StateRef<int> tick;

      await tester.pumpWidget(wrap(Probe((_) {
        tick = useState(0);
        useEffect(() {
          runs++;
          return null;
        });
        return Text('${tick.value}', textDirection: TextDirection.ltr);
      })));

      expect(runs, 1);
      tick.value = 1;
      await tester.pump();
      await tester.pump();
      expect(runs, 2);
    });

    testWidgets('cleanup runs on dispose', (tester) async {
      final log = <String>[];

      await tester.pumpWidget(wrap(Probe((_) {
        useEffect(() {
          log.add('run');
          return () => log.add('cleanup');
        }, const []);
        return const SizedBox();
      })));

      expect(log, ['run']);
      await tester.pumpWidget(wrap(const SizedBox()));
      expect(log, ['run', 'cleanup']);
    });
  });

  group('useMemoized', () {
    testWidgets('recomputes only when keys change', (tester) async {
      var computations = 0;
      late StateRef<int> seed;
      late StateRef<int> noise;

      await tester.pumpWidget(wrap(Probe((_) {
        seed = useState(1);
        noise = useState(0);
        final value = useMemoized(() {
          computations++;
          return seed.value * 2;
        }, [seed.value]);
        return Text('$value/${noise.value}',
            textDirection: TextDirection.ltr);
      })));

      expect(computations, 1);
      expect(find.text('2/0'), findsOneWidget);

      noise.value = 1; // unrelated rebuild
      await tester.pump();
      expect(computations, 1);

      seed.value = 5;
      await tester.pump();
      expect(computations, 2);
      expect(find.text('10/1'), findsOneWidget);
    });
  });

  group('useRef', () {
    testWidgets('holds a value across builds without rebuilding',
        (tester) async {
      var builds = 0;
      late Ref<int> ref;
      late StateRef<int> tick;

      await tester.pumpWidget(wrap(Probe((_) {
        builds++;
        ref = useRef(0);
        tick = useState(0);
        return const SizedBox();
      })));

      ref.value = 99;
      await tester.pump();
      expect(builds, 1, reason: 'mutating a Ref must not rebuild');

      tick.value = 1;
      await tester.pump();
      expect(builds, 2);
      expect(ref.value, 99, reason: 'the Ref survived the rebuild');
    });
  });

  group('useFetch', () {
    testWidgets('goes loading -> data', (tester) async {
      final completer = Completer<String>();

      await tester.pumpWidget(wrap(Probe((_) {
        final result = useFetch(() => completer.future);
        return result.when(
          loading: () =>
              const Text('loading', textDirection: TextDirection.ltr),
          error: (e) => Text('error $e', textDirection: TextDirection.ltr),
          data: (d) => Text(d, textDirection: TextDirection.ltr),
        );
      })));

      expect(find.text('loading'), findsOneWidget);
      completer.complete('done');
      await tester.pumpAndSettle();
      expect(find.text('done'), findsOneWidget);
    });

    testWidgets('surfaces errors', (tester) async {
      await tester.pumpWidget(wrap(Probe((_) {
        final result = useFetch<String>(() async => throw StateError('nope'));
        return result.when(
          loading: () =>
              const Text('loading', textDirection: TextDirection.ltr),
          error: (e) => const Text('failed', textDirection: TextDirection.ltr),
          data: (d) => Text(d, textDirection: TextDirection.ltr),
        );
      })));

      await tester.pumpAndSettle();
      expect(find.text('failed'), findsOneWidget);
    });

    testWidgets('does not set state after the widget is gone',
        (tester) async {
      final completer = Completer<String>();

      await tester.pumpWidget(wrap(Probe((_) {
        final result = useFetch(() => completer.future);
        return Text(result.data ?? 'loading',
            textDirection: TextDirection.ltr);
      })));

      await tester.pumpWidget(wrap(const SizedBox()));
      completer.complete('late');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('useStream', () {
    testWidgets('goes loading -> data as events arrive', (tester) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(wrap(Probe((_) {
        final result = useStream(controller.stream);
        return result.when(
          loading: () =>
              const Text('loading', textDirection: TextDirection.ltr),
          error: (e) => const Text('failed', textDirection: TextDirection.ltr),
          data: (d) => Text(d, textDirection: TextDirection.ltr),
        );
      })));

      expect(find.text('loading'), findsOneWidget);

      controller.add('first');
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);

      controller.add('second');
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
    });

    testWidgets('initialData skips the loading frame', (tester) async {
      final controller = StreamController<int>();
      addTearDown(controller.close);

      await tester.pumpWidget(wrap(Probe((_) {
        final result = useStream(controller.stream, initialData: 7);
        return Text('${result.data}', textDirection: TextDirection.ltr);
      })));

      // A bloc already has a current state; rendering a spinner over it would
      // be a flicker for no reason.
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('surfaces stream errors', (tester) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(wrap(Probe((_) {
        final result = useStream(controller.stream);
        return result.when(
          loading: () =>
              const Text('loading', textDirection: TextDirection.ltr),
          error: (e) => const Text('failed', textDirection: TextDirection.ltr),
          data: (d) => Text(d, textDirection: TextDirection.ltr),
        );
      })));

      controller.addError(StateError('nope'));
      await tester.pumpAndSettle();
      expect(find.text('failed'), findsOneWidget);
    });

    testWidgets('unsubscribes when the widget goes away', (tester) async {
      final controller = StreamController<String>();
      addTearDown(controller.close);

      await tester.pumpWidget(wrap(Probe((_) {
        final result = useStream(controller.stream);
        return Text(result.data ?? 'none', textDirection: TextDirection.ltr);
      })));
      expect(controller.hasListener, isTrue);

      await tester.pumpWidget(wrap(const SizedBox()));
      expect(controller.hasListener, isFalse);

      controller.add('late');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('useStreamValue', () {
    testWidgets('tracks the latest value without AsyncValue', (tester) async {
      final controller = StreamController<int>();
      addTearDown(controller.close);

      await tester.pumpWidget(wrap(Probe((_) {
        final value = useStreamValue(0, controller.stream);
        return Text('$value', textDirection: TextDirection.ltr);
      })));

      expect(find.text('0'), findsOneWidget);
      controller.add(42);
      await tester.pumpAndSettle();
      expect(find.text('42'), findsOneWidget);
    });
  });

  group('useListenable', () {
    testWidgets('rebuilds when the listenable notifies', (tester) async {
      final notifier = ValueNotifier<int>(0);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(wrap(Probe((_) {
        useListenable(notifier);
        return Text('${notifier.value}', textDirection: TextDirection.ltr);
      })));

      expect(find.text('0'), findsOneWidget);
      notifier.value = 42;
      await tester.pump();
      expect(find.text('42'), findsOneWidget);
    });
  });

  group('useTextEditingController', () {
    testWidgets('is stable across builds and disposed with the widget',
        (tester) async {
      late TextEditingController first;
      late TextEditingController second;
      late StateRef<int> tick;
      var builds = 0;

      await tester.pumpWidget(wrap(Probe((_) {
        final controller = useTextEditingController(text: 'hi');
        if (builds == 0) {
          first = controller;
        } else {
          second = controller;
        }
        builds++;
        tick = useState(0);
        return Text('${tick.value}', textDirection: TextDirection.ltr);
      })));

      expect(first.text, 'hi');
      tick.value = 1;
      await tester.pump();
      expect(identical(first, second), isTrue);

      await tester.pumpWidget(wrap(const SizedBox()));
      // A disposed controller throws when touched — that is the assertion.
      expect(() => first.addListener(() {}), throwsFlutterError);
    });
  });

  group('hook discipline', () {
    testWidgets('calling hooks outside build is a readable error', (_) async {
      expect(() => useState(0), throwsA(isA<FlutterError>()));
    });

    testWidgets('dropping a hook between builds is caught', (tester) async {
      late StateRef<bool> full;

      await tester.pumpWidget(wrap(Probe((_) {
        full = useState(true);
        // ignore: unused_local_variable
        if (full.value) useState(0);
        return const SizedBox();
      })));

      full.value = false;
      await tester.pump();
      expect(tester.takeException(), isA<FlutterError>());
    });
  });
}

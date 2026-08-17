import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flx_runtime/flx_runtime.dart';

class Counter {
  int value = 0;
}

class Closable implements Disposable {
  bool closed = false;

  @override
  void dispose() => closed = true;
}

class Greeter {
  Greeter(this.name);
  final String name;
}

class CounterViewModel extends ViewModel {
  int count = 0;

  void increment() {
    count++;
    notify();
  }
}

class Probe extends Composable {
  const Probe(this.body, {super.key});

  final Widget Function(BuildContext context) body;

  @override
  Widget build(BuildContext context) => body(context);
}

void main() {
  group('Injector', () {
    test('singleton returns the same instance every time', () {
      final injector = Injector()..singleton<Counter>((_) => Counter());
      expect(identical(injector.get<Counter>(), injector.get<Counter>()),
          isTrue);
    });

    test('factory returns a new instance every time', () {
      final injector = Injector()..factory<Counter>((_) => Counter());
      expect(identical(injector.get<Counter>(), injector.get<Counter>()),
          isFalse);
    });

    test('value registers a pre-built instance', () {
      final instance = Counter()..value = 9;
      final injector = Injector()..value<Counter>(instance);
      expect(injector.get<Counter>().value, 9);
    });

    test('singletons are built lazily', () {
      var built = 0;
      final injector = Injector()
        ..singleton<Counter>((_) {
          built++;
          return Counter();
        });

      expect(built, 0);
      injector.get<Counter>();
      injector.get<Counter>();
      expect(built, 1);
    });

    test('providers can resolve their own dependencies', () {
      final injector = Injector()
        ..singleton<Counter>((_) => Counter()..value = 3)
        ..singleton<Greeter>((i) => Greeter('n=${i.get<Counter>().value}'));

      expect(injector.get<Greeter>().name, 'n=3');
    });

    test('a child scope falls back to its parent', () {
      final parent = Injector()..singleton<Counter>((_) => Counter());
      final child = Injector(parent: parent);
      expect(identical(child.get<Counter>(), parent.get<Counter>()), isTrue);
    });

    test('a child scope can override its parent', () {
      final parent = Injector()..singleton<Counter>((_) => Counter());
      final child = Injector(parent: parent)
        ..singleton<Counter>((_) => Counter()..value = 100);

      expect(child.get<Counter>().value, 100);
      expect(parent.get<Counter>().value, 0);
    });

    test('has() reports registrations including inherited ones', () {
      final parent = Injector()..singleton<Counter>((_) => Counter());
      final child = Injector(parent: parent);

      expect(child.has<Counter>(), isTrue);
      expect(child.has<Greeter>(), isFalse);
    });

    test('a missing registration throws with instructions', () {
      final injector = Injector();
      expect(
        () => injector.get<Counter>(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('No provider registered for Counter'),
              contains('FlxScope')),
        )),
      );
    });

    test('dispose closes Disposable singletons', () {
      final injector = Injector()..singleton<Closable>((_) => Closable());
      final instance = injector.get<Closable>();

      injector.dispose();
      expect(instance.closed, isTrue);
    });

    test('dispose does not close instances registered with value()', () {
      final instance = Closable();
      final injector = Injector()..value<Closable>(instance);

      injector.dispose();
      expect(instance.closed, isFalse,
          reason: 'whoever constructed it owns its lifetime');
    });
  });

  group('useInject', () {
    testWidgets('resolves from the nearest FlxScope', (tester) async {
      final injector = Injector()
        ..singleton<Greeter>((_) => Greeter('Ada'));

      await tester.pumpWidget(FlxScope(
        injector: injector,
        child: MaterialApp(
          home: Probe((_) {
            final greeter = useInject<Greeter>();
            return Text(greeter.name, textDirection: TextDirection.ltr);
          }),
        ),
      ));

      expect(find.text('Ada'), findsOneWidget);
    });

    testWidgets('a nested scope shadows the outer one', (tester) async {
      final root = Injector()..singleton<Greeter>((_) => Greeter('outer'));
      final inner = Injector(parent: root)
        ..singleton<Greeter>((_) => Greeter('inner'));

      await tester.pumpWidget(FlxScope(
        injector: root,
        child: MaterialApp(
          home: Column(children: [
            Probe((_) => Text(useInject<Greeter>().name,
                textDirection: TextDirection.ltr)),
            FlxScope(
              injector: inner,
              child: Probe((_) => Text(useInject<Greeter>().name,
                  textDirection: TextDirection.ltr)),
            ),
          ]),
        ),
      ));

      expect(find.text('outer'), findsOneWidget);
      expect(find.text('inner'), findsOneWidget);
    });

    testWidgets('missing FlxScope explains how to add one', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Probe((_) => Text(useInject<Greeter>().name,
            textDirection: TextDirection.ltr)),
      ));

      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect('$error', contains('FlxScope'));
    });
  });

  group('ViewModel', () {
    testWidgets('useViewModel rebuilds the screen on notify', (tester) async {
      final injector = Injector()
        ..singleton<CounterViewModel>((_) => CounterViewModel());

      await tester.pumpWidget(FlxScope(
        injector: injector,
        child: MaterialApp(
          home: Probe((_) {
            final vm = useViewModel<CounterViewModel>();
            return Text('${vm.count}', textDirection: TextDirection.ltr);
          }),
        ),
      ));

      expect(find.text('0'), findsOneWidget);
      injector.get<CounterViewModel>().increment();
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('unsubscribes when the screen leaves the tree',
        (tester) async {
      final vm = CounterViewModel();
      final injector = Injector()..value<CounterViewModel>(vm);

      await tester.pumpWidget(FlxScope(
        injector: injector,
        child: MaterialApp(
          home: Probe((_) {
            final model = useViewModel<CounterViewModel>();
            return Text('${model.count}', textDirection: TextDirection.ltr);
          }),
        ),
      ));

      await tester.pumpWidget(FlxScope(
        injector: injector,
        child: const MaterialApp(home: SizedBox()),
      ));

      vm.increment();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    test('a disposed ViewModel stops notifying', () {
      final vm = CounterViewModel();
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.increment();
      expect(notifications, 1);

      vm.dispose();
      vm.increment();
      expect(notifications, 1);
      expect(vm.isDisposed, isTrue);
    });

    test('a listener may remove itself while being notified', () {
      final vm = CounterViewModel();
      late VoidCallback listener;
      var calls = 0;
      listener = () {
        calls++;
        vm.removeListener(listener);
      };
      vm.addListener(listener);

      vm.increment();
      vm.increment();
      expect(calls, 1);
    });
  });
}

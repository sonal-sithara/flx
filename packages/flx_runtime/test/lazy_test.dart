import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flx_runtime/flx_runtime.dart';

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(height: 400, child: child)),
    );

void main() {
  group('LazyColumn', () {
    testWidgets('builds only what is on screen', (tester) async {
      final built = <int>[];
      await tester.pumpWidget(host(LazyColumn<int>(
        items: List.generate(1000, (i) => i),
        itemBuilder: (item, _) {
          built.add(item);
          return SizedBox(height: 50, child: Text('row $item'));
        },
      )));

      expect(find.text('row 0'), findsOneWidget);
      expect(built.length, lessThan(50),
          reason: 'a lazy list must not build all 1000 rows');
    });

    testWidgets('passes the index through', (tester) async {
      await tester.pumpWidget(host(LazyColumn<String>(
        items: const ['a', 'b'],
        itemBuilder: (item, index) => Text('$index:$item'),
      )));

      expect(find.text('0:a'), findsOneWidget);
      expect(find.text('1:b'), findsOneWidget);
    });

    testWidgets('shows the empty widget instead of a blank list',
        (tester) async {
      await tester.pumpWidget(host(LazyColumn<int>(
        items: const [],
        empty: const Text('nothing here'),
        itemBuilder: (item, _) => Text('$item'),
      )));

      expect(find.text('nothing here'), findsOneWidget);
    });

    testWidgets('separates rows by gap', (tester) async {
      await tester.pumpWidget(host(LazyColumn<int>(
        items: const [1, 2, 3],
        gap: 20,
        itemBuilder: (item, _) => SizedBox(height: 50, child: Text('$item')),
      )));

      final first = tester.getTopLeft(find.text('1'));
      final second = tester.getTopLeft(find.text('2'));
      expect(second.dy - first.dy, 70, reason: '50 tall + 20 gap');
    });
  });

  group('onEndReached', () {
    testWidgets('fires once per approach, not once per notification',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(LazyColumn<int>(
        items: List.generate(20, (i) => i),
        itemBuilder: (item, _) => SizedBox(height: 50, child: Text('$item')),
        onEndReached: () => calls++,
      )));

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      // A flick emits dozens of scroll notifications. Calling back on each
      // would load every remaining page in one gesture.
      expect(calls, 1);
    });

    testWidgets('re-arms once the list grows past the threshold',
        (tester) async {
      var calls = 0;
      var items = List.generate(20, (i) => i);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                height: 400,
                child: LazyColumn<int>(
                  items: items,
                  itemBuilder: (item, _) =>
                      SizedBox(height: 50, child: Text('$item')),
                  onEndReached: () {
                    calls++;
                    setState(() {
                      items = List.generate(items.length + 20, (i) => i);
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(items.length, 40);

      // Scrolling to the new end loads the next page, and only that one.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(items.length, 60);
    });

    testWidgets('does not fire when everything already fits', (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(LazyColumn<int>(
        items: const [1, 2],
        itemBuilder: (item, _) => SizedBox(height: 50, child: Text('$item')),
        onEndReached: () => calls++,
      )));
      await tester.pumpAndSettle();

      expect(calls, 0, reason: 'no scrolling happened');
    });
  });

  group('LazyRow', () {
    testWidgets('scrolls horizontally within a bounded height',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LazyRow<int>(
            items: List.generate(50, (i) => i),
            height: 80,
            gap: 8,
            itemBuilder: (item, _) => SizedBox(width: 100, child: Text('$item')),
          ),
        ),
      ));

      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('LazyGrid', () {
    testWidgets('lays out in the requested number of columns', (tester) async {
      await tester.pumpWidget(host(LazyGrid<int>(
        items: List.generate(6, (i) => i),
        columns: 3,
        itemBuilder: (item, _) => Text('$item'),
      )));

      // The first three share a row, so the fourth starts a new one.
      final first = tester.getTopLeft(find.text('0'));
      final second = tester.getTopLeft(find.text('1'));
      final fourth = tester.getTopLeft(find.text('3'));

      expect(second.dy, first.dy);
      expect(fourth.dy, greaterThan(first.dy));
    });
  });

  group('useScrollController', () {
    testWidgets('is stable across builds and disposed with the widget',
        (tester) async {
      final seen = <ScrollController>[];
      late StateRef<int> tick;

      await tester.pumpWidget(host(_Probe((_) {
        seen.add(useScrollController());
        tick = useState(0);
        return Text('${tick.value}');
      })));

      tick.value = 1;
      await tester.pump();

      expect(seen.length, 2);
      expect(identical(seen[0], seen[1]), isTrue);

      await tester.pumpWidget(host(const SizedBox()));
      expect(() => seen.first.position, throwsA(anything),
          reason: 'the controller should have been disposed');
    });
  });
}

class _Probe extends Composable {
  const _Probe(this.body);

  final Widget Function(BuildContext context) body;

  @override
  Widget build(BuildContext context) => body(context);
}

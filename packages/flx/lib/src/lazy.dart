import 'package:flutter/widgets.dart';

import 'core.dart';

/// Builder signature for every lazy list. The index is always passed, so the
/// DSL can bind it (`{ item, i in ... }`) or ignore it (`{ item in ... }`)
/// without the runtime needing two shapes.
typedef ItemBuilder<T> = Widget Function(T item, int index);

/// How close to the end scrolling must get before [onEndReached] fires.
const _endReachedThreshold = 300.0;

/// A vertically scrolling list that builds only what is on screen.
///
/// `for (x in xs) { ... }` in the DSL builds every child eagerly, which is
/// fine for a menu and wrong for a transaction history. This is the lazy
/// counterpart:
///
///   LazyColumn(items: vm.rows, gap: 8, onEndReached: vm.loadMore) { row in
///     TransactionRow(row: row)
///   }
class LazyColumn<T> extends StatelessWidget {
  const LazyColumn({
    required this.items,
    required this.itemBuilder,
    this.gap = 0,
    this.padding = EdgeInsets.zero,
    this.empty,
    this.controller,
    this.onEndReached,
    this.shrinkWrap = false,
    this.physics,
    super.key,
  });

  final List<T> items;
  final ItemBuilder<T> itemBuilder;
  final double gap;
  final EdgeInsets padding;

  /// Shown instead of the list when [items] is empty.
  final Widget? empty;
  final ScrollController? controller;

  /// Fires once per approach to the bottom. The callback is expected to be
  /// idempotent — guard it with an `isLoading` flag in your ViewModel, since
  /// scroll physics can deliver several notifications per fling.
  final VoidCallback? onEndReached;

  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && empty != null) return empty!;

    final list = ListView.separated(
      controller: controller,
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: items.length,
      separatorBuilder: (_, __) => SizedBox(height: gap),
      itemBuilder: (_, index) => itemBuilder(items[index], index),
    );

    if (onEndReached == null) return list;
    return _EndReachedDetector(onEndReached: onEndReached!, child: list);
  }
}

/// The horizontal counterpart of [LazyColumn].
class LazyRow<T> extends StatelessWidget {
  const LazyRow({
    required this.items,
    required this.itemBuilder,
    this.gap = 0,
    this.padding = EdgeInsets.zero,
    this.empty,
    this.controller,
    this.height,
    super.key,
  });

  final List<T> items;
  final ItemBuilder<T> itemBuilder;
  final double gap;
  final EdgeInsets padding;
  final Widget? empty;
  final ScrollController? controller;

  /// A horizontal list inside a Column needs a bounded height.
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && empty != null) return empty!;

    final list = ListView.separated(
      scrollDirection: Axis.horizontal,
      controller: controller,
      padding: padding,
      itemCount: items.length,
      separatorBuilder: (_, __) => SizedBox(width: gap),
      itemBuilder: (_, index) => itemBuilder(items[index], index),
    );

    return height == null ? list : SizedBox(height: height, child: list);
  }
}

/// A lazy grid with a fixed number of columns.
class LazyGrid<T> extends StatelessWidget {
  const LazyGrid({
    required this.items,
    required this.itemBuilder,
    this.columns = 2,
    this.gap = 8,
    this.aspectRatio = 1,
    this.padding = EdgeInsets.zero,
    this.empty,
    this.controller,
    this.shrinkWrap = false,
    super.key,
  });

  final List<T> items;
  final ItemBuilder<T> itemBuilder;
  final int columns;
  final double gap;
  final double aspectRatio;
  final EdgeInsets padding;
  final Widget? empty;
  final ScrollController? controller;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && empty != null) return empty!;

    return GridView.builder(
      controller: controller,
      padding: padding,
      shrinkWrap: shrinkWrap,
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
        childAspectRatio: aspectRatio,
      ),
      itemBuilder: (_, index) => itemBuilder(items[index], index),
    );
  }
}

/// Fires [onEndReached] once per approach to the end of the list.
///
/// A single flick produces dozens of scroll notifications, and every one of
/// them is "near the end". Calling back on each would load every remaining
/// page in one gesture — pagination in name only. An `isLoading` guard in the
/// caller does not help when loading is synchronous, because the flag is set
/// and cleared inside a single callback.
///
/// So the callback is latched: it fires when the list first comes within
/// [_endReachedThreshold] of the end, and re-arms only once the list has
/// scrolled back out of that zone — which is exactly what happens when the
/// newly loaded page extends the content.
class _EndReachedDetector extends StatefulWidget {
  const _EndReachedDetector({required this.onEndReached, required this.child});

  final VoidCallback onEndReached;
  final Widget child;

  @override
  State<_EndReachedDetector> createState() => _EndReachedDetectorState();
}

class _EndReachedDetectorState extends State<_EndReachedDetector> {
  bool _armed = true;

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final metrics = notification.metrics;
          if (!metrics.hasContentDimensions) return false;

          if (metrics.extentAfter >= _endReachedThreshold) {
            _armed = true;
          } else if (_armed) {
            _armed = false;
            widget.onEndReached();
          }
          return false;
        },
        child: widget.child,
      );
}

/// A ScrollController tied to this Composable's lifetime.
ScrollController useScrollController() {
  final controller = useMemoized(ScrollController.new);
  useEffect(() => controller.dispose, [controller]);
  return controller;
}

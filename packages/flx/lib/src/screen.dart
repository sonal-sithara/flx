import 'package:flutter/material.dart';

/// A full screen: app bar, body, optional action button.
///
/// In the DSL a `Screen { ... }` block becomes the `children:` list, which is
/// how a widget tree reaches a named parameter — plain arguments are captured
/// as expression tokens and cannot hold widgets.
///
///   @page("/transactions")
///   composable TransactionsScreen {
///     Screen(title: "Transactions", actionIcon: .add, onAction: vm.create) {
///       SearchField(...)
///       LazyColumn(items: vm.items, expanded: true) { tx in Row { ... } }
///     }
///   }
///
/// A composable whose root is a Screen is not wrapped in a second Scaffold.
class Screen extends StatelessWidget {
  const Screen({
    required this.children,
    this.title = '',
    this.subtitle = '',
    this.padding = const EdgeInsets.all(16),
    this.gap = 12,
    this.scrollable = false,
    this.showBack = true,
    this.actionIcon,
    this.onAction,
    this.actionTooltip = '',
    this.fabIcon,
    this.onFab,
    this.fabLabel = '',
    this.cross = CrossAxisAlignment.stretch,
    super.key,
  });

  final List<Widget> children;
  final String title;

  /// Rendered under the title in the app bar.
  final String subtitle;

  final EdgeInsets padding;
  final double gap;

  /// Wraps the body in a scroll view. Leave false when a child is itself a
  /// lazy list — nesting an unbounded list inside a scroll view is the most
  /// common cause of an "infinite height" layout error.
  final bool scrollable;

  final bool showBack;

  /// A single app-bar action.
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final String actionTooltip;

  /// A floating action button.
  final IconData? fabIcon;
  final VoidCallback? onFab;
  final String fabLabel;

  final CrossAxisAlignment cross;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (gap > 0 && i != children.length - 1) {
        spaced.add(SizedBox(height: gap));
      }
    }

    Widget body = Column(crossAxisAlignment: cross, children: spaced);
    if (scrollable) body = SingleChildScrollView(child: body);
    body = Padding(padding: padding, child: body);

    return Scaffold(
      appBar: title.isEmpty
          ? null
          : AppBar(
              automaticallyImplyLeading: showBack && canPop,
              title: subtitle.isEmpty
                  ? Text(title)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
              actions: [
                if (actionIcon != null)
                  IconButton(
                    icon: Icon(actionIcon),
                    tooltip: actionTooltip.isEmpty ? null : actionTooltip,
                    onPressed: onAction,
                  ),
              ],
            ),
      body: SafeArea(child: body),
      floatingActionButton: fabIcon == null
          ? null
          : fabLabel.isEmpty
              ? FloatingActionButton(
                  onPressed: onFab,
                  child: Icon(fabIcon),
                )
              : FloatingActionButton.extended(
                  onPressed: onFab,
                  icon: Icon(fabIcon),
                  label: Text(fabLabel),
                ),
    );
  }
}

/// A grouped card of children — the sub-screen equivalent of [Screen].
class Panel extends StatelessWidget {
  const Panel({
    required this.children,
    this.title = '',
    this.padding = const EdgeInsets.all(12),
    this.gap = 8,
    this.cross = CrossAxisAlignment.stretch,
    super.key,
  });

  final List<Widget> children;
  final String title;
  final EdgeInsets padding;
  final double gap;
  final CrossAxisAlignment cross;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final spaced = <Widget>[];
    if (title.isNotEmpty) {
      spaced
        ..add(Text(title, style: theme.textTheme.titleSmall))
        ..add(SizedBox(height: gap));
    }
    for (var i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (gap > 0 && i != children.length - 1) {
        spaced.add(SizedBox(height: gap));
      }
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: cross, children: spaced),
      ),
    );
  }
}

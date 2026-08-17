import 'package:flutter/widgets.dart';

List<Widget> _withGap(List<Widget> children, double gap, Axis axis) {
  if (gap <= 0 || children.length < 2) return children;
  final spacer =
      axis == Axis.vertical ? SizedBox(height: gap) : SizedBox(width: gap);
  final out = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    out.add(children[i]);
    if (i != children.length - 1) out.add(spacer);
  }
  return out;
}

/// [a, b, c].column(gap: 12) instead of Column(children: [a, SizedBox...])
extension WidgetListLayout on List<Widget> {
  Widget column({
    double gap = 0,
    MainAxisAlignment main = MainAxisAlignment.start,
    CrossAxisAlignment cross = CrossAxisAlignment.center,
    MainAxisSize size = MainAxisSize.max,
  }) =>
      Column(
        mainAxisAlignment: main,
        crossAxisAlignment: cross,
        mainAxisSize: size,
        children: _withGap(this, gap, Axis.vertical),
      );

  Widget row({
    double gap = 0,
    MainAxisAlignment main = MainAxisAlignment.start,
    CrossAxisAlignment cross = CrossAxisAlignment.center,
    MainAxisSize size = MainAxisSize.max,
  }) =>
      Row(
        mainAxisAlignment: main,
        crossAxisAlignment: cross,
        mainAxisSize: size,
        children: _withGap(this, gap, Axis.horizontal),
      );

  Widget stack({AlignmentGeometry alignment = AlignmentDirectional.topStart}) =>
      Stack(alignment: alignment, children: this);

  Widget wrap({double spacing = 0, double runSpacing = 0}) =>
      Wrap(spacing: spacing, runSpacing: runSpacing, children: this);
}

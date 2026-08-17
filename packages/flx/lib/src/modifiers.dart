import 'package:flutter/material.dart';

/// Compose-style modifier chains for any widget.
/// Text('Hi').padding(16).background(Colors.blue, radius: 12).center()
extension WidgetModifiers on Widget {
  Widget padding(double all) =>
      Padding(padding: EdgeInsets.all(all), child: this);

  Widget paddingOnly({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) =>
      Padding(
        padding:
            EdgeInsets.only(left: left, top: top, right: right, bottom: bottom),
        child: this,
      );

  Widget paddingSymmetric({double h = 0, double v = 0}) => Padding(
        padding: EdgeInsets.symmetric(horizontal: h, vertical: v),
        child: this,
      );

  Widget background(Color color, {double radius = 0}) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: this,
      );

  Widget center() => Center(child: this);

  Widget align(Alignment alignment) =>
      Align(alignment: alignment, child: this);

  Widget expanded([int flex = 1]) => Expanded(flex: flex, child: this);

  Widget size({double? width, double? height}) =>
      SizedBox(width: width, height: height, child: this);

  Widget rounded(double radius) =>
      ClipRRect(borderRadius: BorderRadius.circular(radius), child: this);

  Widget onTap(VoidCallback action) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action,
        child: this,
      );

  Widget opacity(double value) => Opacity(opacity: value, child: this);

  Widget scrollable() => SingleChildScrollView(child: this);

  Widget safeArea() => SafeArea(child: this);

  Widget card({double elevation = 1, double radius = 12}) => Material(
        elevation: elevation,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: this,
      );
}

/// Text-specific chains: Text('hi').bold().fontSize(20).color(Colors.red)
extension TextModifiers on Text {
  Text _merge(TextStyle patch) => Text(
        data ?? '',
        key: key,
        style: (style ?? const TextStyle()).merge(patch),
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );

  Text bold() => _merge(const TextStyle(fontWeight: FontWeight.bold));
  Text italic() => _merge(const TextStyle(fontStyle: FontStyle.italic));
  Text color(Color c) => _merge(TextStyle(color: c));
  Text fontSize(double s) => _merge(TextStyle(fontSize: s));
  Text styled(TextStyle s) => _merge(s);
}

import 'package:flutter/material.dart';

/// A tappable row: leading mark, title, optional subtitle, trailing value.
///
/// The workhorse of list-heavy apps, so it is a first-class widget rather
/// than something every screen reassembles out of Rows.
class Tile extends StatelessWidget {
  const Tile({
    required this.title,
    this.subtitle = '',
    this.trailing = '',
    this.trailingColor,
    this.leading,
    this.onTap,
    this.dense = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final Color? trailingColor;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      dense: dense,
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing.isEmpty
          ? null
          : Text(
              trailing,
              style: theme.textTheme.titleSmall?.copyWith(
                color: trailingColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
    );
  }
}

/// A small coloured dot, used to mark a category in a list.
class Dot extends StatelessWidget {
  const Dot(this.color, {this.size = 12, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// A rounded label.
///
/// Named `Pill` rather than `Badge` because every generated screen imports
/// both `package:flutter/material.dart` and `package:flx_runtime/flx_runtime.dart`, and
/// Material already exports a `Badge`.
class Pill extends StatelessWidget {
  const Pill(this.label, {this.color, super.key});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = color ?? theme.colorScheme.secondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: ThemeData.estimateBrightnessForColor(background) ==
                  Brightness.dark
              ? Colors.white
              : Colors.black87,
        ),
      ),
    );
  }
}

/// A labelled progress bar, used for budgets.
class ProgressBar extends StatelessWidget {
  const ProgressBar(
    this.fraction, {
    this.color,
    this.height = 8,
    this.overColor,
    this.isOver = false,
    super.key,
  });

  /// 0..1. Values outside the range are clamped rather than overflowing.
  final double fraction;
  final Color? color;
  final Color? overColor;
  final double height;
  final bool isOver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = isOver
        ? (overColor ?? theme.colorScheme.error)
        : (color ?? theme.colorScheme.primary);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: fraction.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(fill),
      ),
    );
  }
}

/// Shown when a list has nothing in it — a blank screen reads as a bug.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    this.subtitle = '',
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// A titled section with optional trailing action.
class Section extends StatelessWidget {
  const Section({
    required this.title,
    required this.child,
    this.action,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: theme.textTheme.titleSmall),
            ),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// A headline figure with a caption, for dashboards.
class Stat extends StatelessWidget {
  const Stat({
    required this.value,
    required this.label,
    this.color,
    super.key,
  });

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }
}

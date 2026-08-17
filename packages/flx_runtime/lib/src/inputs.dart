import 'package:flutter/material.dart';

import 'core.dart';

/// A TextEditingController that also rebuilds the Composable on every
/// keystroke.
///
/// This is what makes live validation work in the DSL without lambdas:
///
///   val amount = useTextField()
///   ...
///   Field(controller: amount, label: "Amount", error: vm.amountError)
TextEditingController useTextField({String text = ''}) {
  final controller = useTextEditingController(text: text);
  useListenable(controller);
  return controller;
}

/// A labelled text input with inline error display.
class Field extends StatelessWidget {
  const Field({
    required this.controller,
    this.label = '',
    this.hint = '',
    this.error,
    this.keyboard,
    this.prefix,
    this.suffix,
    this.maxLines = 1,
    this.autofocus = false,
    this.enabled = true,
    this.obscure = false,
    this.focusNode,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  /// Non-null shows the message and turns the field red.
  final String? error;

  final TextInputType? keyboard;
  final String? prefix;
  final Widget? suffix;
  final int maxLines;
  final bool autofocus;
  final bool enabled;
  final bool obscure;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboard,
        maxLines: obscure ? 1 : maxLines,
        autofocus: autofocus,
        enabled: enabled,
        obscureText: obscure,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label.isEmpty ? null : label,
          hintText: hint.isEmpty ? null : hint,
          errorText: error,
          prefixText: prefix,
          suffixIcon: suffix,
          border: const OutlineInputBorder(),
        ),
      );
}

/// A search box with a clear button.
class SearchField extends StatelessWidget {
  const SearchField(
    this.controller,
    this.onChanged, {
    this.hint = 'Search',
    super.key,
  });

  final TextEditingController controller;

  /// Positional so the DSL's trailing block binds to it:
  ///   SearchField(query) { text -> vm.search(text) }
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      );
}

/// A labelled on/off switch.
class Toggle extends StatelessWidget {
  const Toggle(this.value, this.onChanged, {this.label = '', super.key});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => label.isEmpty
      ? Switch(value: value, onChanged: onChanged)
      : SwitchListTile(
          value: value,
          onChanged: onChanged,
          title: Text(label),
          contentPadding: EdgeInsets.zero,
        );
}

/// A single-choice segmented control.
///
///   Segmented(vm.kind, TxKind.values, labelOf: kindLabel) { kind ->
///     vm.setKind(kind)
///   }
class Segmented<T> extends StatelessWidget {
  const Segmented(
    this.value,
    this.options,
    this.onChanged, {
    this.labelOf,
    super.key,
  });

  final T value;
  final List<T> options;
  final ValueChanged<T> onChanged;

  /// Defaults to `toString()`, which is right for enums with a good name.
  final String Function(T option)? labelOf;

  @override
  Widget build(BuildContext context) => SegmentedButton<T>(
        segments: [
          for (final option in options)
            ButtonSegment<T>(
              value: option,
              label: Text(labelOf?.call(option) ?? '$option'),
            ),
        ],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => onChanged(selection.first),
      );
}

/// A dropdown for choosing one of [options].
class Picker<T> extends StatelessWidget {
  const Picker(
    this.value,
    this.options,
    this.onChanged, {
    required this.labelOf,
    this.label = '',
    this.error,
    super.key,
  });

  final T? value;
  final List<T> options;
  final ValueChanged<T> onChanged;
  final String Function(T option) labelOf;
  final String label;
  final String? error;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label.isEmpty ? null : label,
          errorText: error,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final option in options)
            DropdownMenuItem<T>(
              value: option,
              child: Text(labelOf(option), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
      );
}

/// A read-only field that opens the platform date picker when tapped.
class DateField extends StatelessWidget {
  const DateField(
    this.value,
    this.onChanged, {
    this.label = 'Date',
    this.firstDate,
    this.lastDate,
    super.key,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: firstDate ?? DateTime(2000),
            lastDate: lastDate ?? DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
          ),
          child: Text(formatDate(value)),
        ),
      );
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `3 Mar 2026` — short, unambiguous, and free of locale dependencies.
String formatDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

/// `Today`, `Yesterday`, or the short date.
String formatRelativeDate(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final justDate = DateTime(date.year, date.month, date.day);
  final justToday = DateTime(today.year, today.month, today.day);
  final days = justToday.difference(justDate).inDays;

  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < 7) return '$days days ago';
  return formatDate(date);
}

import 'package:flutter/material.dart';

/// Context-free text styles backing the DSL's `.title` shorthands.
/// Roadmap: make these theme-aware via an inherited Styles widget.
class Styles {
  static const TextStyle title =
      TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  static const TextStyle subtitle =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  static const TextStyle body = TextStyle(fontSize: 16);
  static const TextStyle caption =
      TextStyle(fontSize: 12, color: Color(0xFF8E8E93));
}

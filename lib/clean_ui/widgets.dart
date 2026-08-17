import 'package:flutter/material.dart';

/// Compose-style Button: Button('Tap me', () => count.value++)
class Button extends StatelessWidget {
  const Button(this.label, this.onPressed, {super.key});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      FilledButton(onPressed: onPressed, child: Text(label));
}

/// Avatar(url, size: 64) — shows a person icon when url is null
class Avatar extends StatelessWidget {
  const Avatar(this.url, {this.size = 40, super.key});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: size / 2,
        backgroundImage: url != null ? NetworkImage(url!) : null,
        child: url == null ? Icon(Icons.person, size: size * 0.6) : null,
      );
}

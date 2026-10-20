import 'package:flutter/material.dart';

/// A number that counts up from [from] to [value] when it first shows (a
/// game's answer being revealed). Shows [value] straight away with
/// reduced motion. [format] turns the running number into text.
class CountUp extends StatelessWidget {
  final int value;
  final int from;
  final TextStyle? style;
  final String Function(int n)? format;
  final Duration duration;

  const CountUp({
    super.key,
    required this.value,
    this.from = 0,
    this.style,
    this.format,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final show = format ?? (n) => '$n';
    if (reduce) return Text(show(value), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: from.toDouble(), end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(show(v.round()), style: style),
    );
  }
}

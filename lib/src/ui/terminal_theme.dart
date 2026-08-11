import 'package:flutter/widgets.dart';

class TerminalTheme {
  const TerminalTheme({
    required this.cursor,
    required this.selection,
    required this.foreground,
    required this.background,
    required this.black,
    required this.white,
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.magenta,
    required this.cyan,
    required this.brightBlack,
    required this.brightRed,
    required this.brightGreen,
    required this.brightYellow,
    required this.brightBlue,
    required this.brightMagenta,
    required this.brightCyan,
    required this.brightWhite,
    required this.searchHitBackground,
    required this.searchHitBackgroundCurrent,
    required this.searchHitForeground,
    this.minimumContrastRatio = 1,
  });

  final Color cursor;
  final Color selection;

  final Color foreground;
  final Color background;

  final Color black;
  final Color red;
  final Color green;
  final Color yellow;
  final Color blue;
  final Color magenta;
  final Color cyan;
  final Color white;

  final Color brightBlack;
  final Color brightRed;
  final Color brightGreen;
  final Color brightYellow;
  final Color brightBlue;
  final Color brightMagenta;
  final Color brightCyan;
  final Color brightWhite;

  final Color searchHitBackground;
  final Color searchHitBackgroundCurrent;
  final Color searchHitForeground;

  /// Minimum contrast ratio applied to cell foreground colors.
  ///
  /// A value of 1 disables adjustment. WCAG AA normal text uses 4.5.
  final double minimumContrastRatio;
}

Color ensureTerminalContrast(
  Color foreground,
  Color background,
  double minimumContrastRatio,
) {
  final minimum = minimumContrastRatio.clamp(1.0, 21.0);
  if (minimum <= 1 ||
      terminalContrastRatio(foreground, background) >= minimum) {
    return foreground;
  }

  final black = const Color(0xFF000000);
  final white = const Color(0xFFFFFFFF);
  final target = terminalContrastRatio(black, background) >
          terminalContrastRatio(white, background)
      ? black
      : white;

  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 8; i++) {
    final amount = (low + high) / 2;
    final candidate = Color.lerp(foreground, target, amount)!;
    if (terminalContrastRatio(candidate, background) >= minimum) {
      high = amount;
    } else {
      low = amount;
    }
  }
  return Color.lerp(foreground, target, high)!;
}

double terminalContrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter =
      firstLuminance > secondLuminance ? firstLuminance : secondLuminance;
  final darker =
      firstLuminance > secondLuminance ? secondLuminance : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

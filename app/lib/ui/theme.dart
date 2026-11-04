import 'package:flutter/material.dart';

import '../parser/confidence.dart';

const brand = Color(0xFFB4532A);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFFAF6F0) : null,
    cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// Background for fields the parser wasn't sure about. High confidence gets no highlight.
Color confidenceColor(Confidence c) => switch (c) {
      Confidence.high => Colors.transparent,
      Confidence.medium => const Color(0x55FFD54F),
      Confidence.low => const Color(0x66FF8A65),
    };

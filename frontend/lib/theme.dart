import 'package:flutter/material.dart';

const lsuPurple = Color(0xFF461D7C);
const lsuGold = Color(0xFFFDD023);

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: lsuPurple,
        brightness: brightness,
      ).copyWith(
        primary: isDark ? const Color(0xFFCDB8F0) : lsuPurple,
        onPrimary: isDark ? const Color(0xFF2A0F52) : Colors.white,
        secondary: lsuGold,
        onSecondary: Colors.black,
      );

  return ThemeData(
    colorScheme: colorScheme,
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? colorScheme.surfaceContainer : lsuPurple,
      foregroundColor: isDark ? colorScheme.onSurface : Colors.white,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: lsuGold.withValues(alpha: isDark ? 0.35 : 0.6),
    ),
    cardTheme: const CardThemeData(elevation: 0.5),
  );
}

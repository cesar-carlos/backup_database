import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' hide Typography;
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  static FluentThemeData get lightFluentTheme {
    final montserratTextTheme = GoogleFonts.montserratTextTheme();
    final theme = FluentThemeData.light();
    return theme.copyWith(
      extensions: const [AppSemanticColors.light],
      accentColor: AccentColor('normal', const {
        'normal': AppPalette.primary,
        'dark': AppPalette.primaryDark,
        'light': AppPalette.primaryLight,
      }),
      typography: Typography.raw(
        caption: montserratTextTheme.bodySmall,
        body: montserratTextTheme.bodyMedium,
        bodyLarge: montserratTextTheme.bodyLarge,
        bodyStrong: montserratTextTheme.titleMedium,
        subtitle: montserratTextTheme.titleSmall,
        title: montserratTextTheme.titleMedium,
        titleLarge: montserratTextTheme.headlineSmall,
        display: montserratTextTheme.headlineMedium,
      ),
    );
  }

  static FluentThemeData get darkFluentTheme {
    final montserratTextTheme = GoogleFonts.montserratTextTheme(
      ThemeData.dark().textTheme,
    );
    final theme = FluentThemeData.dark();
    return theme.copyWith(
      extensions: const [AppSemanticColors.dark],
      accentColor: AccentColor('normal', const {
        'normal': AppPalette.primary,
        'dark': AppPalette.primaryDark,
        'light': AppPalette.primaryLight,
      }),
      typography: Typography.raw(
        caption: montserratTextTheme.bodySmall,
        body: montserratTextTheme.bodyMedium,
        bodyLarge: montserratTextTheme.bodyLarge,
        bodyStrong: montserratTextTheme.titleMedium,
        subtitle: montserratTextTheme.titleSmall,
        title: montserratTextTheme.titleMedium,
        titleLarge: montserratTextTheme.headlineSmall,
        display: montserratTextTheme.headlineMedium,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      extensions: const [AppSemanticColors.light],
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppPalette.primary,
      ),
      textTheme: GoogleFonts.montserratTextTheme(),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppPalette.primary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        labelType: NavigationRailLabelType.all,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      extensions: const [AppSemanticColors.dark],
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppPalette.primary,
        brightness: Brightness.dark,
      ),
      textTheme: GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        labelType: NavigationRailLabelType.all,
      ),
    );
  }
}

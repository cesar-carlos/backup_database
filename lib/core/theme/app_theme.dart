import 'package:flutter/material.dart' hide Typography;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static FluentThemeData get lightFluentTheme {
    final montserratTextTheme = GoogleFonts.montserratTextTheme();
    final theme = FluentThemeData.light();
    return theme.copyWith(
      accentColor: AccentColor('normal', {
        'normal': AppColors.primary,
        'dark': AppColors.primaryDark,
        'light': AppColors.primaryLight,
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
    final montserratTextTheme = GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme);
    final theme = FluentThemeData.dark();
    return theme.copyWith(
      accentColor: AccentColor('normal', {
        'normal': AppColors.primary,
        'dark': AppColors.primaryDark,
        'light': AppColors.primaryLight,
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
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      textTheme: GoogleFonts.montserratTextTheme(),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
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
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
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


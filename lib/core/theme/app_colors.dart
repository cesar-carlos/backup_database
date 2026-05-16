import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:flutter/material.dart';

/// Legacy facade over AppPalette. Prefer AppPalette or
/// context.appSemanticColors in new code.
class AppColors {
  AppColors._();

  static const Color primary = AppPalette.primary;
  static const Color primaryLight = AppPalette.primaryLight;
  static const Color primaryDark = AppPalette.primaryDark;

  static const Color secondary = AppPalette.secondary;
  static const Color secondaryLight = AppPalette.secondaryLight;
  static const Color secondaryDark = AppPalette.secondaryDark;

  static const Color success = AppPalette.success;
  static const Color warning = AppPalette.warning;
  static const Color error = AppPalette.error;
  static const Color info = AppPalette.info;

  static const Color backgroundLight = AppPalette.backgroundLight;
  static const Color backgroundDark = AppPalette.backgroundDark;

  static const Color surfaceLight = AppPalette.surfaceLight;
  static const Color surfaceDark = AppPalette.surfaceDark;

  static const Color textPrimaryLight = AppPalette.textPrimaryLight;
  static const Color textSecondaryLight = AppPalette.textSecondaryLight;
  static const Color textPrimaryDark = AppPalette.textPrimaryDark;
  static const Color textSecondaryDark = AppPalette.textSecondaryDark;

  static const Color delete = AppPalette.delete;
  static const Color deleteBackground = AppPalette.deleteBackground;
  static const Color deleteText = AppPalette.deleteText;

  static const Color successIcon = AppPalette.successIcon;
  static const Color errorIcon = AppPalette.errorIcon;
  static const Color warningIcon = AppPalette.warningIcon;

  static const Color errorBackground = AppPalette.errorBackground;
  static const Color errorBorder = AppPalette.errorBorder;
  static const Color errorText = AppPalette.errorText;

  static const Color grey300 = AppPalette.grey300;
  static const Color grey600 = AppPalette.grey600;

  static const Color scheduleDaily = AppPalette.scheduleDaily;
  static const Color scheduleWeekly = AppPalette.scheduleWeekly;
  static const Color scheduleMonthly = AppPalette.scheduleMonthly;
  static const Color scheduleInterval = AppPalette.scheduleInterval;

  static const Color databaseSqlServer = AppPalette.databaseSqlServer;
  static const Color databaseSybase = AppPalette.databaseSybase;
  static const Color databasePostgresql = AppPalette.databasePostgresql;
  static const Color databaseFirebird = AppPalette.databaseFirebird;

  static const Color destinationLocal = AppPalette.destinationLocal;
  static const Color destinationFtp = AppPalette.destinationFtp;
  static const Color destinationGoogleDrive = AppPalette.destinationGoogleDrive;
  static const Color destinationDropbox = AppPalette.destinationDropbox;
  static const Color destinationNextcloud = AppPalette.destinationNextcloud;

  static const Color statsBackups = AppPalette.statsBackups;
  static const Color statsFailed = AppPalette.statsFailed;
  static const Color statsActive = AppPalette.statsActive;

  static const Color backupSuccess = AppPalette.backupSuccess;
  static const Color backupError = AppPalette.backupError;
  static const Color backupWarning = AppPalette.backupWarning;
  static const Color backupRunning = AppPalette.backupRunning;

  static const Color logDebug = AppPalette.logDebug;
  static const Color logWarning = AppPalette.logWarning;

  static const Color googleDriveSignedIn = AppPalette.googleDriveSignedIn;
  static const Color googleDriveSignedInBackground =
      AppPalette.googleDriveSignedInBackground;
  static const Color googleDriveSignedInBorder =
      AppPalette.googleDriveSignedInBorder;

  static const Color buttonTextOnColored = AppPalette.buttonTextOnColored;
}

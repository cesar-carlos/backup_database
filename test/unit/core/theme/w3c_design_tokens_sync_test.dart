import 'package:backup_database/core/theme/tokens/app_duration.dart';
import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:backup_database/core/theme/tokens/app_radius.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/core/theme/tokens/generated/w3c_token_snapshot.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('W3C token snapshot vs runtime token classes', () {
    test('spacing doubles match AppSpacing', () {
      expect(W3cTokenSpacing.xs, AppSpacing.xs);
      expect(W3cTokenSpacing.sm, AppSpacing.sm);
      expect(W3cTokenSpacing.md, AppSpacing.md);
      expect(W3cTokenSpacing.lg, AppSpacing.lg);
      expect(W3cTokenSpacing.xl, AppSpacing.xl);
      expect(W3cTokenSpacing.xxl, AppSpacing.xxl);
    });

    test('radius doubles match AppRadius', () {
      expect(W3cTokenRadius.sm, AppRadius.sm);
      expect(W3cTokenRadius.md, AppRadius.md);
      expect(W3cTokenRadius.lg, AppRadius.lg);
      expect(W3cTokenRadius.xl, AppRadius.xl);
      expect(W3cTokenRadius.pill, AppRadius.pill);
    });

    test('motion durations match AppDuration', () {
      expect(W3cTokenMotion.fast, AppDuration.fast);
      expect(W3cTokenMotion.normal, AppDuration.normal);
      expect(W3cTokenMotion.slow, AppDuration.slow);
    });

    test('palette colors match AppPalette', () {
      expect(W3cTokenPalette.primary, AppPalette.primary);
      expect(W3cTokenPalette.primaryLight, AppPalette.primaryLight);
      expect(W3cTokenPalette.primaryDark, AppPalette.primaryDark);
      expect(W3cTokenPalette.secondary, AppPalette.secondary);
      expect(W3cTokenPalette.secondaryLight, AppPalette.secondaryLight);
      expect(W3cTokenPalette.secondaryDark, AppPalette.secondaryDark);
      expect(W3cTokenPalette.success, AppPalette.success);
      expect(W3cTokenPalette.warning, AppPalette.warning);
      expect(W3cTokenPalette.error, AppPalette.error);
      expect(W3cTokenPalette.info, AppPalette.info);
      expect(W3cTokenPalette.backgroundLight, AppPalette.backgroundLight);
      expect(W3cTokenPalette.backgroundDark, AppPalette.backgroundDark);
      expect(W3cTokenPalette.surfaceLight, AppPalette.surfaceLight);
      expect(W3cTokenPalette.surfaceDark, AppPalette.surfaceDark);
      expect(W3cTokenPalette.textPrimaryLight, AppPalette.textPrimaryLight);
      expect(
        W3cTokenPalette.textSecondaryLight,
        AppPalette.textSecondaryLight,
      );
      expect(W3cTokenPalette.textPrimaryDark, AppPalette.textPrimaryDark);
      expect(
        W3cTokenPalette.textSecondaryDark,
        AppPalette.textSecondaryDark,
      );
      expect(W3cTokenPalette.delete, AppPalette.delete);
      expect(W3cTokenPalette.deleteBackground, AppPalette.deleteBackground);
      expect(W3cTokenPalette.deleteText, AppPalette.deleteText);
      expect(W3cTokenPalette.successIcon, AppPalette.successIcon);
      expect(W3cTokenPalette.errorIcon, AppPalette.errorIcon);
      expect(W3cTokenPalette.warningIcon, AppPalette.warningIcon);
      expect(W3cTokenPalette.errorBackground, AppPalette.errorBackground);
      expect(W3cTokenPalette.errorBorder, AppPalette.errorBorder);
      expect(W3cTokenPalette.errorText, AppPalette.errorText);
      expect(W3cTokenPalette.grey300, AppPalette.grey300);
      expect(W3cTokenPalette.grey600, AppPalette.grey600);
      expect(W3cTokenPalette.scheduleDaily, AppPalette.scheduleDaily);
      expect(W3cTokenPalette.scheduleWeekly, AppPalette.scheduleWeekly);
      expect(W3cTokenPalette.scheduleMonthly, AppPalette.scheduleMonthly);
      expect(W3cTokenPalette.scheduleInterval, AppPalette.scheduleInterval);
      expect(W3cTokenPalette.databaseSqlServer, AppPalette.databaseSqlServer);
      expect(W3cTokenPalette.databaseSybase, AppPalette.databaseSybase);
      expect(
        W3cTokenPalette.databasePostgresql,
        AppPalette.databasePostgresql,
      );
      expect(W3cTokenPalette.databaseFirebird, AppPalette.databaseFirebird);
      expect(W3cTokenPalette.destinationLocal, AppPalette.destinationLocal);
      expect(W3cTokenPalette.destinationFtp, AppPalette.destinationFtp);
      expect(
        W3cTokenPalette.destinationGoogleDrive,
        AppPalette.destinationGoogleDrive,
      );
      expect(W3cTokenPalette.destinationDropbox, AppPalette.destinationDropbox);
      expect(
        W3cTokenPalette.destinationNextcloud,
        AppPalette.destinationNextcloud,
      );
      expect(W3cTokenPalette.statsBackups, AppPalette.statsBackups);
      expect(W3cTokenPalette.statsFailed, AppPalette.statsFailed);
      expect(W3cTokenPalette.statsActive, AppPalette.statsActive);
      expect(W3cTokenPalette.backupSuccess, AppPalette.backupSuccess);
      expect(W3cTokenPalette.backupError, AppPalette.backupError);
      expect(W3cTokenPalette.backupWarning, AppPalette.backupWarning);
      expect(W3cTokenPalette.backupRunning, AppPalette.backupRunning);
      expect(W3cTokenPalette.logDebug, AppPalette.logDebug);
      expect(W3cTokenPalette.logWarning, AppPalette.logWarning);
      expect(
        W3cTokenPalette.googleDriveSignedIn,
        AppPalette.googleDriveSignedIn,
      );
      expect(
        W3cTokenPalette.googleDriveSignedInBackground,
        AppPalette.googleDriveSignedInBackground,
      );
      expect(
        W3cTokenPalette.googleDriveSignedInBorder,
        AppPalette.googleDriveSignedInBorder,
      );
      expect(
        W3cTokenPalette.buttonTextOnColored,
        AppPalette.buttonTextOnColored,
      );
    });
  });
}

import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/license_trial_constants.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LicenseTrialPolicy {
  LicenseTrialPolicy({
    DateTime Function()? clock,
    DateTime? endsAtExclusive,
    bool? forceEnded,
  }) : _clock = clock ?? DateTime.now,
       _endsAtExclusive = endsAtExclusive ?? _endsAtFromDebugEnv(),
       _forceEnded = forceEnded ?? _forceEndedFromDebugEnv();

  final DateTime Function() _clock;
  final DateTime _endsAtExclusive;
  final bool _forceEnded;

  DateTime get endsAtExclusive => _endsAtExclusive;

  static DateTime _endsAtFromDebugEnv() {
    if (!kDebugMode) {
      return LicenseTrialConstants.trialEndsExclusive;
    }
    final raw = _readEnv(LicenseTrialConstants.envEndsAt);
    if (raw == null || raw.isEmpty) {
      return LicenseTrialConstants.trialEndsExclusive;
    }
    try {
      return DateTime.parse(raw).toUtc();
    } on Object {
      LoggerService.warning(
        'LICENSE_TRIAL_ENDS_AT inválido ($raw) — usando corte padrão.',
      );
      return LicenseTrialConstants.trialEndsExclusive;
    }
  }

  static bool _forceEndedFromDebugEnv() {
    if (!kDebugMode) return false;
    final raw = _readEnv(LicenseTrialConstants.envForceEnded);
    if (raw == null) return false;
    return raw.toLowerCase() == 'true' || raw == '1';
  }

  static String? _readEnv(String key) {
    try {
      final value = dotenv.env[key];
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } on Object {
      return null;
    }
  }

  bool isActive([DateTime? now]) {
    if (_forceEnded) return false;
    final instant = (now ?? _clock()).toUtc();
    return instant.isBefore(_endsAtExclusive);
  }

  bool get isReminderWindow {
    if (!isActive()) return false;
    final remaining = _endsAtExclusive.difference(_clock().toUtc());
    return remaining <= LicenseTrialConstants.trialReminderLead &&
        remaining > Duration.zero;
  }

  License syntheticLicense({required String deviceKey}) {
    final createdAt = DateTime.utc(2026);
    return License(
      id: LicenseTrialConstants.trialLicenseId,
      deviceKey: deviceKey,
      licenseKey: LicenseTrialConstants.trialLicenseKey,
      allowedFeatures: List<String>.unmodifiable(LicenseFeatures.allFeatures),
      expiresAt: _endsAtExclusive,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  void logBootStatus() {
    if (isActive()) {
      LoggerService.info(
        'event=license_trial_active until=${_endsAtExclusive.toIso8601String()}',
      );
    } else {
      LoggerService.info('event=license_trial_ended');
    }
  }
}

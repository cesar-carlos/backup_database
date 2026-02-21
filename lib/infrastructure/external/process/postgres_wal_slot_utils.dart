import 'package:backup_database/domain/entities/postgres_config.dart';

class PostgresWalSlotUtils {
  static const String walSlotEnabledEnv = 'BACKUP_DATABASE_PG_LOG_USE_SLOT';
  static const String walSlotNameEnv = 'BACKUP_DATABASE_PG_LOG_SLOT_NAME';

  static bool isWalSlotEnabled({Map<String, String>? environment}) {
    final env = environment ?? const <String, String>{};
    final raw = env[walSlotEnabledEnv];
    if (raw == null) {
      return false;
    }

    final normalized = raw.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  }

  static String resolveWalSlotName({
    required PostgresConfig config,
    Map<String, String>? environment,
  }) {
    final env = environment ?? const <String, String>{};
    final customSlot = env[walSlotNameEnv]?.trim();
    if (customSlot != null && customSlot.isNotEmpty) {
      return sanitizeSlotName(customSlot);
    }

    final seed = 'bd_wal_${config.id}';
    return sanitizeSlotName(seed);
  }

  static String sanitizeSlotName(String slotName) {
    final lowered = slotName.toLowerCase();
    final sanitized = lowered.replaceAll(RegExp('[^a-z0-9_]'), '_');
    final normalized = sanitized.startsWith(RegExp('[a-z_]'))
        ? sanitized
        : 'bd_$sanitized';

    if (normalized.length <= 63) {
      return normalized;
    }

    return normalized.substring(0, 63);
  }
}

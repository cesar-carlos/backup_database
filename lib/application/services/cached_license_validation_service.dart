import 'package:backup_database/application/services/i_license_cache_invalidator.dart';
import 'package:backup_database/core/constants/license_cache_constants.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _CacheEntry {
  _CacheEntry(this.result, this.expiresAt);
  final rd.Result<License> result;
  final DateTime expiresAt;
}

class CachedLicenseValidationService
    implements ILicenseValidationService, ILicenseCacheInvalidator {
  CachedLicenseValidationService({
    required ILicenseValidationService delegate,
    Duration ttl = LicenseCacheConstants.ttl,
  }) : _delegate = delegate,
       _ttl = ttl;

  final ILicenseValidationService _delegate;
  final Duration _ttl;

  /// Sentinela do cache. Esta camada existe para 1 dispositivo por
  /// instância — não há ganho real em chavear o cache por `deviceKey`.
  /// Antes do refactor, cada `getCurrentLicense()` invocava
  /// `_deviceKeyService.getDeviceKey()` (custo: 2-3 process spawns +
  /// registry + volume info, mesmo com cache quente). Agora o cache é
  /// consultado primeiro; `getDeviceKey()` só é chamado quando ele
  /// estiver realmente vencido.
  _CacheEntry? _entry;

  @override
  Future<rd.Result<License>> getCurrentLicense() async {
    final now = DateTime.now();
    final cached = _entry;
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return cached.result;
    }
    final result = await _delegate.getCurrentLicense();
    _entry = _CacheEntry(result, now.add(_ttl));
    return result;
  }

  @override
  Future<rd.Result<bool>> isFeatureAllowed(String feature) async {
    final licenseResult = await getCurrentLicense();
    return licenseResult.fold(
      (license) => rd.Success(license.hasFeature(feature)),
      (_) => const rd.Success(false),
    );
  }

  @override
  Future<rd.Result<License>> getStoredLicense() async {
    return _delegate.getStoredLicense();
  }

  @override
  void invalidateLicenseCache() {
    _entry = null;
  }
}

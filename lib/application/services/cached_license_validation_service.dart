import 'package:backup_database/application/services/i_license_cache_invalidator.dart';
import 'package:backup_database/core/constants/license_cache_constants.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/services/i_device_key_service.dart';
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
    required IDeviceKeyService deviceKeyService,
    Duration ttl = LicenseCacheConstants.ttl,
  })  : _delegate = delegate,
        _deviceKeyService = deviceKeyService,
        _ttl = ttl;

  final ILicenseValidationService _delegate;
  final IDeviceKeyService _deviceKeyService;
  final Duration _ttl;

  final Map<String, _CacheEntry> _cache = {};

  @override
  Future<rd.Result<License>> getCurrentLicense() async {
    final deviceKeyResult = await _deviceKeyService.getDeviceKey();
    return deviceKeyResult.fold(
      (deviceKey) async {
        final now = DateTime.now();
        final entry = _cache[deviceKey];
        if (entry != null && entry.expiresAt.isAfter(now)) {
          return entry.result;
        }
        final result = await _delegate.getCurrentLicense();
        _cache[deviceKey] = _CacheEntry(
          result,
          now.add(_ttl),
        );
        return result;
      },
      rd.Failure.new,
    );
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
  Future<rd.Result<bool>> validateLicense(
    String licenseKey,
    String deviceKey,
  ) async {
    return _delegate.validateLicense(licenseKey, deviceKey);
  }

  @override
  void invalidateLicenseCache() {
    _cache.clear();
  }
}

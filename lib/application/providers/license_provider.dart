import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart' as core;
import '../../domain/entities/license.dart';
import '../../domain/repositories/i_license_repository.dart';
import '../../domain/services/i_device_key_service.dart';
import '../../domain/services/i_license_validation_service.dart';
import '../services/license_generation_service.dart';

class LicenseProvider extends ChangeNotifier {
  final ILicenseValidationService _validationService;
  final LicenseGenerationService _generationService;
  final ILicenseRepository _licenseRepository;
  final IDeviceKeyService _deviceKeyService;

  License? _currentLicense;
  bool _isLoading = false;
  String? _error;
  String? _deviceKey;

  LicenseProvider({
    required ILicenseValidationService validationService,
    required LicenseGenerationService generationService,
    required ILicenseRepository licenseRepository,
    required IDeviceKeyService deviceKeyService,
  }) : _validationService = validationService,
       _generationService = generationService,
       _licenseRepository = licenseRepository,
       _deviceKeyService = deviceKeyService {
    loadDeviceKey();
    loadLicense();
  }

  License? get currentLicense => _currentLicense;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get deviceKey => _deviceKey;
  bool get hasValidLicense =>
      _currentLicense != null && _currentLicense!.isValid;

  Future<void> loadDeviceKey() async {
    try {
      final deviceKeyResult = await _deviceKeyService.getDeviceKey();
      deviceKeyResult.fold(
        (key) {
          _deviceKey = key;
        },
        (failure) {
          if (failure is core.Failure) {
            _error = failure.message;
          } else {
            _error = failure.toString();
          }
        },
      );
      notifyListeners();
    } catch (e) {
      _error = 'Erro ao obter chave do dispositivo: $e';
      notifyListeners();
    }
  }

  Future<void> loadLicense() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final licenseResult = await _validationService.getCurrentLicense();
      licenseResult.fold(
        (license) {
          _currentLicense = license;
          _error = null;
        },
        (failure) {
          _currentLicense = null;
          // NotFoundFailure significa que não há licença, não é um erro
          if (failure is core.NotFoundFailure) {
            _error = null;
          } else if (failure is core.Failure) {
            _error = failure.message;
          } else {
            _error = failure.toString();
          }
        },
      );
    } catch (e) {
      _currentLicense = null;
      _error = 'Erro ao carregar licença: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> validateAndSaveLicense(String licenseKey) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (_deviceKey == null) {
        _error = 'Chave do dispositivo não disponível';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final createResult = await _generationService.createLicenseFromKey(
        licenseKey: licenseKey,
        deviceKey: _deviceKey!,
      );

      return createResult.fold(
        (license) async {
          final saveResult = await _licenseRepository.create(license);
          return saveResult.fold(
            (_) {
              _currentLicense = license;
              _error = null;
              _isLoading = false;
              notifyListeners();
              return true;
            },
            (failure) {
              if (failure is core.Failure) {
                _error = failure.message;
              } else {
                _error = failure.toString();
              }
              _isLoading = false;
              notifyListeners();
              return false;
            },
          );
        },
        (failure) {
          if (failure is core.Failure) {
            _error = failure.message;
          } else {
            _error = failure.toString();
          }
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = 'Erro ao validar licença: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> isFeatureAllowed(String feature) async {
    try {
      final result = await _validationService.isFeatureAllowed(feature);
      return result.fold((allowed) => allowed, (_) => false);
    } catch (e) {
      return false;
    }
  }

  void setDeviceKey(String deviceKey) {
    _deviceKey = deviceKey;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<String?> generateLicense({
    required String deviceKey,
    DateTime? expiresAt,
    required List<String> allowedFeatures,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final generateResult = await _generationService.generateLicenseKey(
        deviceKey: deviceKey,
        expiresAt: expiresAt,
        allowedFeatures: allowedFeatures,
      );

      return generateResult.fold(
        (licenseKey) {
          _isLoading = false;
          _error = null;
          notifyListeners();
          return licenseKey;
        },
        (failure) {
          if (failure is core.Failure) {
            _error = failure.message;
          } else {
            _error = failure.toString();
          }
          _isLoading = false;
          notifyListeners();
          return null;
        },
      );
    } catch (e) {
      _error = 'Erro ao gerar licença: $e';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }
}

import 'package:backup_database/domain/entities/license.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class ILicenseValidationService {
  Future<rd.Result<License>> getCurrentLicense();
  Future<rd.Result<bool>> isFeatureAllowed(String feature);
  Future<rd.Result<bool>> validateLicense(String licenseKey, String deviceKey);
}

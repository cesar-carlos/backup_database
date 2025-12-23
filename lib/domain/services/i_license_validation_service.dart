import 'package:result_dart/result_dart.dart' as rd;

import '../entities/license.dart';

abstract class ILicenseValidationService {
  Future<rd.Result<License>> getCurrentLicense();
  Future<rd.Result<bool>> isFeatureAllowed(String feature);
  Future<rd.Result<bool>> validateLicense(String licenseKey, String deviceKey);
}

import 'dart:io';

import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';

class OsVersionChecker {
  static bool isCompatible() {
    if (!Platform.isWindows) {
      LoggerService.warning(
        'Sistema operacional não é Windows. Plataforma detectada: ${Platform.operatingSystem}',
      );
      return false;
    }

    try {
      final osVersion = Platform.operatingSystemVersion;
      LoggerService.debug('Versão bruta do SO detectada: $osVersion');

      final majorVersion = _extractMajorVersion(osVersion);
      final minorVersion = _extractMinorVersion(osVersion);

      LoggerService.debug(
        'Versão extraída: Major=$majorVersion, Minor=$minorVersion',
      );

      if (majorVersion == null) {
        LoggerService.warning(
          'Não foi possível extrair versão major do SO: $osVersion. Assumindo compatibilidade.',
        );
        return true;
      }

      final versionName = _getVersionName(majorVersion, minorVersion);
      LoggerService.debug('Nome da versão identificada: $versionName');

      final isCompatible = _checkCompatibility(majorVersion, minorVersion);

      if (!isCompatible) {
        LoggerService.warning(
          '⚠️ SO não compatível: Windows $majorVersion.$minorVersion ($versionName)',
        );
        LoggerService.warning(
          'Requisito mínimo: Windows 8.1 (6.3) / Server 2012 R2 ou superior',
        );
        LoggerService.warning(
          'O aplicativo pode não funcionar corretamente nesta versão.',
        );
      } else {
        LoggerService.debug(
          '✅ SO compatível: Windows $majorVersion.$minorVersion ($versionName)',
        );
      }

      return isCompatible;
    } catch (e, stackTrace) {
      // Retornar true em caso de erro para não bloquear execução
      // Alguns ambientes podem funcionar mesmo sem detecção precisa da versão
      LoggerService.error(
        'Erro ao verificar versão do SO. Assumindo compatibilidade para continuar.',
        e,
        stackTrace,
      );
      return true;
    }
  }

  static rd.Result<OsVersionInfo> getVersionInfo() {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(message: 'Sistema operacional não é Windows'),
      );
    }

    try {
      final osVersion = Platform.operatingSystemVersion;
      final majorVersion = _extractMajorVersion(osVersion);
      final minorVersion = _extractMinorVersion(osVersion);

      if (majorVersion == null) {
        return rd.Failure(
          ValidationFailure(
            message: 'Não foi possível extrair versão do SO: $osVersion',
          ),
        );
      }

      final versionName = _getVersionName(majorVersion, minorVersion);
      final isCompatible = _checkCompatibility(majorVersion, minorVersion);

      LoggerService.debug(
        'Informações de versão obtidas: $versionName ($majorVersion.${minorVersion ?? 0}), Compatível: $isCompatible',
      );

      return rd.Success(
        OsVersionInfo(
          majorVersion: majorVersion,
          minorVersion: minorVersion ?? 0,
          versionName: versionName,
          isCompatible: isCompatible,
          rawVersion: osVersion,
        ),
      );
    } catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao obter informações detalhadas da versão do SO',
        e,
        stackTrace,
      );
      return rd.Failure(
        ServerFailure(
          message: 'Erro ao obter informações da versão do SO: $e',
          originalError: e,
        ),
      );
    }
  }

  static int? _extractMajorVersion(String osVersion) {
    final match = RegExp(r'(\d+)\.(\d+)').firstMatch(osVersion);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1) ?? '');
    }
    return null;
  }

  static int? _extractMinorVersion(String osVersion) {
    final match = RegExp(r'(\d+)\.(\d+)').firstMatch(osVersion);
    if (match != null && match.groupCount >= 2) {
      return int.tryParse(match.group(2) ?? '');
    }
    return null;
  }

  static bool _checkCompatibility(int majorVersion, int? minorVersion) {
    if (majorVersion > 6) {
      return true;
    }

    if (majorVersion == 6) {
      return (minorVersion ?? 0) >= 3;
    }

    return false;
  }

  static String _getVersionName(int majorVersion, int? minorVersion) {
    final minor = minorVersion ?? 0;

    if (majorVersion >= 10) {
      if (majorVersion >= 11 || (majorVersion == 10 && minor >= 22000)) {
        return 'Windows 11';
      }
      return 'Windows 10';
    }

    if (majorVersion == 6) {
      switch (minor) {
        case 3:
          return 'Windows 8.1 / Server 2012 R2';
        case 2:
          return 'Windows 8 / Server 2012';
        case 1:
          return 'Windows 7 / Server 2008 R2';
        case 0:
          return 'Windows Vista / Server 2008';
        default:
          return 'Windows $majorVersion.$minor';
      }
    }

    if (majorVersion == 5) {
      switch (minor) {
        case 2:
          return 'Windows XP 64-bit / Server 2003';
        case 1:
          return 'Windows XP';
        default:
          return 'Windows $majorVersion.$minor';
      }
    }

    return 'Windows $majorVersion.$minor';
  }
}

class OsVersionInfo {
  final int majorVersion;
  final int minorVersion;
  final String versionName;
  final bool isCompatible;
  final String rawVersion;

  const OsVersionInfo({
    required this.majorVersion,
    required this.minorVersion,
    required this.versionName,
    required this.isCompatible,
    required this.rawVersion,
  });

  String get minimumRequired => 'Windows 8.1 (6.3) / Server 2012 R2';

  @override
  String toString() {
    return 'OsVersionInfo('
        'version: $majorVersion.$minorVersion, '
        'name: $versionName, '
        'compatible: $isCompatible, '
        'raw: $rawVersion'
        ')';
  }
}

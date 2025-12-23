import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:win32/win32.dart';

import '../../../core/errors/failure.dart' as core;
import '../../../core/utils/logger_service.dart';
import '../../../domain/services/i_device_key_service.dart';

class DeviceKeyService implements IDeviceKeyService {
  DeviceKeyService();

  @override
  Future<rd.Result<String>> getDeviceKey() async {
    if (!Platform.isWindows) {
      return rd.Failure(
        core.ValidationFailure(
          message: 'Device key generation is only supported on Windows',
        ),
      );
    }

    try {
      LoggerService.info(
        'Obtendo informações do sistema para gerar chave do dispositivo...',
      );

      // Tentar múltiplos métodos para obter identificadores únicos
      String? machineGuid;
      String? computerName;
      String? volumeSerial;

      // Método 1: Machine GUID do Windows Registry (mais confiável)
      final guidResult = _getMachineGuidFromRegistry();
      guidResult.fold((guid) {
        if (guid.isNotEmpty) {
          machineGuid = guid;
          LoggerService.info('Machine GUID obtido do registro: $machineGuid');
        }
      }, (_) {});

      // Método 2: Computer Name (nome do computador)
      try {
        final name = _getComputerName();
        if (name.isNotEmpty) {
          computerName = name;
          LoggerService.info('Computer Name obtido: $computerName');
        }
      } catch (e) {
        LoggerService.warning('Erro ao obter Computer Name: $e');
      }

      // Método 3: Volume Serial Number do disco C:
      try {
        final serial = _getVolumeSerialNumber('C:\\');
        if (serial.isNotEmpty) {
          volumeSerial = serial;
          LoggerService.info('Volume Serial Number obtido: $volumeSerial');
        }
      } catch (e) {
        LoggerService.warning('Erro ao obter Volume Serial Number: $e');
      }

      // Combinar todos os identificadores disponíveis para criar uma chave única
      final identifiers = <String>[];
      if (machineGuid != null) identifiers.add('GUID:$machineGuid');
      if (computerName != null) identifiers.add('COMP:$computerName');
      if (volumeSerial != null) identifiers.add('VOL:$volumeSerial');

      if (identifiers.isEmpty) {
        LoggerService.warning('Nenhum identificador do sistema foi obtido');
        return rd.Failure(
          core.NotFoundFailure(
            message:
                'Não foi possível obter informações do sistema para gerar a chave do dispositivo',
          ),
        );
      }

      // Gerar hash SHA-256 dos identificadores combinados
      final combinedString = identifiers.join('|');
      final bytes = utf8.encode(combinedString);
      final hash = sha256.convert(bytes);
      final deviceKey = hash.toString().toUpperCase();

      LoggerService.info('Chave do dispositivo gerada com sucesso');
      return rd.Success(deviceKey);
    } catch (e, stackTrace) {
      LoggerService.error(
        'Erro inesperado ao obter chave do dispositivo',
        e,
        stackTrace,
      );
      return rd.Failure(
        core.ServerFailure(
          message: 'Erro inesperado ao obter chave do dispositivo: $e',
          originalError: e,
        ),
      );
    }
  }

  rd.Result<String> _getMachineGuidFromRegistry() {
    try {
      final hKey = HKEY_LOCAL_MACHINE;
      final subKey = TEXT(r'SOFTWARE\Microsoft\Cryptography');
      final valueName = TEXT('MachineGuid');

      Pointer<HKEY> phkResult = calloc<HKEY>();
      final result = RegOpenKeyEx(hKey, subKey, 0, KEY_READ, phkResult);

      if (result != ERROR_SUCCESS) {
        calloc.free(phkResult);
        return rd.Failure(
          core.ServerFailure(
            message: 'Erro ao abrir chave do registro: $result',
          ),
        );
      }

      try {
        final dataType = calloc<DWORD>();
        final dataSize = calloc<DWORD>()..value = 1024;
        final data = calloc<CHAR>(dataSize.value);

        final queryResult = RegQueryValueEx(
          phkResult.value,
          valueName,
          nullptr,
          dataType,
          data.cast<Uint8>(),
          dataSize,
        );

        if (queryResult != ERROR_SUCCESS) {
          calloc.free(dataType);
          calloc.free(dataSize);
          calloc.free(data);
          return rd.Failure(
            core.NotFoundFailure(
              message: 'Machine GUID não encontrado no registro',
            ),
          );
        }

        final guid = data.cast<Utf8>().toDartString();
        calloc.free(dataType);
        calloc.free(dataSize);
        calloc.free(data);

        if (guid.isEmpty) {
          return rd.Failure(
            core.NotFoundFailure(message: 'Machine GUID está vazio'),
          );
        }

        return rd.Success(guid);
      } finally {
        RegCloseKey(phkResult.value);
        calloc.free(phkResult);
      }
    } catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao ler Machine GUID do registro',
        e,
        stackTrace,
      );
      return rd.Failure(
        core.ServerFailure(
          message: 'Erro ao ler Machine GUID do registro: $e',
          originalError: e,
        ),
      );
    }
  }

  String _getComputerName() {
    try {
      final bufferSize = calloc<DWORD>()..value = 256;
      final buffer = calloc<Uint16>(bufferSize.value).cast<Utf16>();

      try {
        final result = GetComputerNameEx(
          ComputerNameNetBIOS,
          buffer,
          bufferSize,
        );

        if (result == 0) {
          final error = GetLastError();
          LoggerService.warning('Erro ao obter Computer Name: $error');
          return '';
        }

        return buffer.toDartString();
      } finally {
        calloc.free(bufferSize);
        calloc.free(buffer.cast<Uint16>());
      }
    } catch (e) {
      LoggerService.warning('Erro ao obter Computer Name: $e');
      return '';
    }
  }

  String _getVolumeSerialNumber(String rootPath) {
    try {
      final volumeNameBuffer = calloc<Uint16>(260).cast<Utf16>();
      final fileSystemNameBuffer = calloc<Uint16>(260).cast<Utf16>();
      final volumeSerialNumber = calloc<DWORD>();
      final maxComponentLength = calloc<DWORD>();
      final fileSystemFlags = calloc<DWORD>();

      try {
        final rootPathPtr = rootPath.toNativeUtf16();
        final result = GetVolumeInformation(
          rootPathPtr,
          volumeNameBuffer,
          260,
          volumeSerialNumber,
          maxComponentLength,
          fileSystemFlags,
          fileSystemNameBuffer,
          260,
        );

        calloc.free(rootPathPtr);

        if (result == 0) {
          final error = GetLastError();
          LoggerService.warning('Erro ao obter Volume Serial Number: $error');
          return '';
        }

        return volumeSerialNumber.value
            .toRadixString(16)
            .toUpperCase()
            .padLeft(8, '0');
      } finally {
        calloc.free(volumeNameBuffer.cast<Uint16>());
        calloc.free(fileSystemNameBuffer.cast<Uint16>());
        calloc.free(volumeSerialNumber);
        calloc.free(maxComponentLength);
        calloc.free(fileSystemFlags);
      }
    } catch (e) {
      LoggerService.warning('Erro ao obter Volume Serial Number: $e');
      return '';
    }
  }
}

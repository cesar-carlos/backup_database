import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:crypto/crypto.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:win32/win32.dart';

import '../../../core/errors/failure.dart' as core;
import '../../../core/utils/logger_service.dart';
import '../../../domain/services/i_device_key_service.dart';

enum VirtualizationPlatform { none, vmware, virtualbox, hyperv, unknown }

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

      final virtualizationPlatform = await _detectVirtualization();
      if (virtualizationPlatform != VirtualizationPlatform.none) {
        LoggerService.info(
          'Ambiente virtualizado detectado: ${virtualizationPlatform.name}',
        );
      }

      String? biosUuid;
      String? machineGuid;
      String? macAddress;
      String? volumeSerial;

      final biosUuidResult = await _getBiosUuid();
      biosUuidResult.fold((uuid) {
        if (uuid.isNotEmpty) {
          biosUuid = uuid;
          LoggerService.info('BIOS UUID obtido: $biosUuid');
        }
      }, (_) {});

      final guidResult = _getMachineGuidFromRegistry();
      guidResult.fold((guid) {
        if (guid.isNotEmpty) {
          machineGuid = guid;
          LoggerService.info('Machine GUID obtido do registro: $machineGuid');
        }
      }, (_) {});

      final macResult = await _getMacAddress();
      macResult.fold((mac) {
        if (mac.isNotEmpty) {
          macAddress = mac;
          LoggerService.info('MAC Address obtido: $macAddress');
        }
      }, (_) {});

      try {
        final serial = _getVolumeSerialNumber('C:\\');
        if (serial.isNotEmpty) {
          volumeSerial = serial;
          LoggerService.info('Volume Serial Number obtido: $volumeSerial');
        }
      } catch (e) {
        LoggerService.warning('Erro ao obter Volume Serial Number: $e');
      }

      final identifiers = <String>[];
      if (biosUuid != null) identifiers.add('BIOS:$biosUuid');
      if (machineGuid != null) identifiers.add('GUID:$machineGuid');
      if (macAddress != null) identifiers.add('MAC:$macAddress');
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

      if (virtualizationPlatform != VirtualizationPlatform.none) {
        identifiers.add('VM:${virtualizationPlatform.name}');
      }

      final combinedString = identifiers.join('|');
      final bytes = utf8.encode(combinedString);
      final hash = sha256.convert(bytes);
      final deviceKey = hash.toString().toUpperCase();

      LoggerService.info(
        'Chave do dispositivo gerada com sucesso (${identifiers.length} identificadores)',
      );
      if (virtualizationPlatform != VirtualizationPlatform.none) {
        LoggerService.info(
          '⚠️ Ambiente virtualizado: Licença vinculada a esta VM específica',
        );
      }
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

  Future<rd.Result<String>> _getBiosUuid() async {
    try {
      final result = await Process.run('wmic', [
        'path',
        'Win32_ComputerSystemProduct',
        'get',
        'UUID',
        '/format:value',
      ], runInShell: true);

      if (result.exitCode != 0) {
        return rd.Failure(
          core.ServerFailure(
            message:
                'Erro ao executar WMIC para obter BIOS UUID: ${result.stderr}',
          ),
        );
      }

      final output = result.stdout.toString();
      final lines = output.split('\n');

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('UUID=')) {
          final uuid = trimmed.substring(5).trim();
          if (uuid.isNotEmpty &&
              uuid != '{}' &&
              uuid.toLowerCase() != 'ffffffff-ffff-ffff-ffff-ffffffffffff') {
            return rd.Success(uuid.toUpperCase());
          }
        }
      }

      return rd.Failure(
        core.NotFoundFailure(message: 'BIOS UUID não encontrado ou inválido'),
      );
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao obter BIOS UUID via WMI', e, stackTrace);
      return rd.Failure(
        core.ServerFailure(
          message: 'Erro ao obter BIOS UUID: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<String>> _getMacAddress() async {
    try {
      final result = await Process.run('wmic', [
        'path',
        'Win32_NetworkAdapter',
        'where',
        'NetConnectionStatus=2',
        'get',
        'MACAddress',
        '/format:value',
      ], runInShell: true);

      if (result.exitCode != 0) {
        return rd.Failure(
          core.ServerFailure(
            message:
                'Erro ao executar WMIC para obter MAC Address: ${result.stderr}',
          ),
        );
      }

      final output = result.stdout.toString();
      final lines = output.split('\n');

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('MACAddress=')) {
          final mac = trimmed.substring(11).trim();
          if (mac.isNotEmpty &&
              mac != '00:00:00:00:00:00' &&
              !mac.startsWith('00:00:00:00:00:0')) {
            return rd.Success(mac.replaceAll(':', '').toUpperCase());
          }
        }
      }

      return rd.Failure(
        core.NotFoundFailure(message: 'MAC Address não encontrado ou inválido'),
      );
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao obter MAC Address via WMI', e, stackTrace);
      return rd.Failure(
        core.ServerFailure(
          message: 'Erro ao obter MAC Address: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<VirtualizationPlatform> _detectVirtualization() async {
    try {
      final registryChecks = _checkVirtualizationRegistry();
      if (registryChecks != VirtualizationPlatform.none) {
        return registryChecks;
      }

      final wmiResult = await _checkVirtualizationWmi();
      if (wmiResult != VirtualizationPlatform.none) {
        return wmiResult;
      }

      return VirtualizationPlatform.none;
    } catch (e) {
      LoggerService.warning('Erro ao detectar virtualização: $e');
      return VirtualizationPlatform.none;
    }
  }

  VirtualizationPlatform _checkVirtualizationRegistry() {
    try {
      final vmwareKey = TEXT(r'SOFTWARE\VMware, Inc.\VMware Tools');
      Pointer<HKEY> phkResult = calloc<HKEY>();
      final result = RegOpenKeyEx(
        HKEY_LOCAL_MACHINE,
        vmwareKey,
        0,
        KEY_READ,
        phkResult,
      );
      if (result == ERROR_SUCCESS) {
        RegCloseKey(phkResult.value);
        calloc.free(phkResult);
        return VirtualizationPlatform.vmware;
      }
      calloc.free(phkResult);

      final vboxKey = TEXT(r'SOFTWARE\Oracle\VirtualBox Guest Additions');
      phkResult = calloc<HKEY>();
      final vboxResult = RegOpenKeyEx(
        HKEY_LOCAL_MACHINE,
        vboxKey,
        0,
        KEY_READ,
        phkResult,
      );
      if (vboxResult == ERROR_SUCCESS) {
        RegCloseKey(phkResult.value);
        calloc.free(phkResult);
        return VirtualizationPlatform.virtualbox;
      }
      calloc.free(phkResult);

      final hypervKey = TEXT(
        r'SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters',
      );
      phkResult = calloc<HKEY>();
      final hypervResult = RegOpenKeyEx(
        HKEY_LOCAL_MACHINE,
        hypervKey,
        0,
        KEY_READ,
        phkResult,
      );
      if (hypervResult == ERROR_SUCCESS) {
        RegCloseKey(phkResult.value);
        calloc.free(phkResult);
        return VirtualizationPlatform.hyperv;
      }
      calloc.free(phkResult);

      return VirtualizationPlatform.none;
    } catch (e) {
      LoggerService.warning(
        'Erro ao verificar registro para virtualização: $e',
      );
      return VirtualizationPlatform.none;
    }
  }

  Future<VirtualizationPlatform> _checkVirtualizationWmi() async {
    try {
      final result = await Process.run('wmic', [
        'path',
        'Win32_ComputerSystem',
        'get',
        'Manufacturer',
        '/format:value',
      ], runInShell: true);

      if (result.exitCode != 0) {
        return VirtualizationPlatform.none;
      }

      final output = result.stdout.toString().toLowerCase();

      if (output.contains('vmware')) {
        return VirtualizationPlatform.vmware;
      } else if (output.contains('virtualbox') || output.contains('innotek')) {
        return VirtualizationPlatform.virtualbox;
      } else if (output.contains('microsoft corporation') &&
          output.contains('virtual')) {
        return VirtualizationPlatform.hyperv;
      } else if (output.contains('qemu') ||
          output.contains('xen') ||
          output.contains('parallels')) {
        return VirtualizationPlatform.unknown;
      }

      return VirtualizationPlatform.none;
    } catch (e) {
      LoggerService.warning('Erro ao verificar WMI para virtualização: $e');
      return VirtualizationPlatform.none;
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

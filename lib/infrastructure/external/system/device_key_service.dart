import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:backup_database/core/errors/failure.dart' as core;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_device_key_service.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:win32/win32.dart';

enum VirtualizationPlatform { none, vmware, virtualbox, hyperv, unknown }

class DeviceKeyService implements IDeviceKeyService {
  DeviceKeyService();

  /// `getDeviceKey` é determinístico para uma dada máquina e cada chamada
  /// dispara 2-3 `wmic` (Process.run) + leitura de registro + GetVolumeInformation.
  /// Esse processo pode levar 1-3s a frio. Como o resultado não muda em
  /// runtime, memoizamos via um único [Future] (race-free entre chamadas
  /// concorrentes — o segundo caller aguarda o mesmo future do primeiro).
  ///
  /// Para invalidar (apenas testes / cenários de troca de hardware "online"),
  /// chame [resetCacheForTesting].
  Future<rd.Result<String>>? _cachedDeviceKeyFuture;

  @override
  Future<rd.Result<String>> getDeviceKey() {
    final cached = _cachedDeviceKeyFuture;
    if (cached != null) return cached;
    final future = _computeDeviceKey();
    _cachedDeviceKeyFuture = future;
    // Se falhou, não cache permanentemente — permite retry em chamadas
    // futuras (ex.: WMI degradado temporariamente no boot).
    future.then((result) {
      if (result.isError()) {
        _cachedDeviceKeyFuture = null;
      }
    }).ignore();
    return future;
  }

  /// Para testes apenas. Não usar em código de produção.
  @visibleForTesting
  void resetCacheForTesting() {
    _cachedDeviceKeyFuture = null;
  }

  Future<rd.Result<String>> _computeDeviceKey() async {
    if (!Platform.isWindows) {
      return const rd.Failure(
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
        final serial = _getVolumeSerialNumber(r'C:\');
        if (serial.isNotEmpty) {
          volumeSerial = serial;
          LoggerService.info('Volume Serial Number obtido: $volumeSerial');
        }
      } on Object catch (e) {
        LoggerService.warning('Erro ao obter Volume Serial Number: $e');
      }

      final identifiers = <String>[];
      if (biosUuid != null) identifiers.add('BIOS:$biosUuid');
      if (machineGuid != null) identifiers.add('GUID:$machineGuid');
      if (macAddress != null) identifiers.add('MAC:$macAddress');
      if (volumeSerial != null) identifiers.add('VOL:$volumeSerial');

      if (identifiers.isEmpty) {
        LoggerService.warning('Nenhum identificador do sistema foi obtido');
        return const rd.Failure(
          core.NotFoundFailure(
            message: 'Não foi possível obter informações do sistema para gerar a chave do dispositivo',
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
    } on Object catch (e, stackTrace) {
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
      return using((arena) {
        final subKey = arena.pcwstr(r'SOFTWARE\Microsoft\Cryptography');
        final valueName = arena.pcwstr('MachineGuid');
        final openKeyPtr = arena<Pointer>();
        final result = RegOpenKeyEx(
          HKEY_LOCAL_MACHINE,
          subKey,
          0,
          KEY_READ,
          openKeyPtr,
        );

        if (result != ERROR_SUCCESS) {
          return rd.Failure(
            core.ServerFailure(
              message: 'Erro ao abrir chave do registro: $result',
            ),
          );
        }

        final hkey = HKEY(openKeyPtr.value);
        try {
          const bufferBytes = 1024;
          final dataType = arena<DWORD>();
          final dataSize = arena<DWORD>()..value = bufferBytes;
          final data = arena<BYTE>(bufferBytes);
          final queryResult = RegQueryValueEx(
            hkey,
            valueName,
            dataType,
            data,
            dataSize,
          );

          if (queryResult != ERROR_SUCCESS) {
            return const rd.Failure(
              core.NotFoundFailure(
                message: 'Machine GUID não encontrado no registro',
              ),
            );
          }

          final guid = data.cast<Utf16>().toDartString();
          if (guid.isEmpty) {
            return const rd.Failure(
              core.NotFoundFailure(message: 'Machine GUID está vazio'),
            );
          }

          return rd.Success(guid);
        } finally {
          RegCloseKey(hkey);
        }
      });
    } on Object catch (e, stackTrace) {
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

      return const rd.Failure(
        core.NotFoundFailure(message: 'BIOS UUID não encontrado ou inválido'),
      );
    } on Object catch (e, stackTrace) {
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

      return const rd.Failure(
        core.NotFoundFailure(message: 'MAC Address não encontrado ou inválido'),
      );
    } on Object catch (e, stackTrace) {
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
    } on Object catch (e) {
      LoggerService.warning('Erro ao detectar virtualização: $e');
      return VirtualizationPlatform.none;
    }
  }

  VirtualizationPlatform _checkVirtualizationRegistry() {
    try {
      if (_registryKeyExists(r'SOFTWARE\VMware, Inc.\VMware Tools')) {
        return VirtualizationPlatform.vmware;
      }
      if (_registryKeyExists(
        r'SOFTWARE\Oracle\VirtualBox Guest Additions',
      )) {
        return VirtualizationPlatform.virtualbox;
      }
      if (_registryKeyExists(
        r'SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters',
      )) {
        return VirtualizationPlatform.hyperv;
      }
      return VirtualizationPlatform.none;
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao verificar registro para virtualização: $e',
      );
      return VirtualizationPlatform.none;
    }
  }

  bool _registryKeyExists(String subKeyPath) {
    return using((arena) {
      final subKey = arena.pcwstr(subKeyPath);
      final openKeyPtr = arena<Pointer>();
      final result = RegOpenKeyEx(
        HKEY_LOCAL_MACHINE,
        subKey,
        0,
        KEY_READ,
        openKeyPtr,
      );
      if (result != ERROR_SUCCESS) {
        return false;
      }
      RegCloseKey(HKEY(openKeyPtr.value));
      return true;
    });
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
    } on Object catch (e) {
      LoggerService.warning('Erro ao verificar WMI para virtualização: $e');
      return VirtualizationPlatform.none;
    }
  }

  String _getVolumeSerialNumber(String rootPath) {
    try {
      return using((arena) {
        const bufferLength = 260;
        final volumeNameBuffer = PWSTR(arena<WCHAR>(bufferLength).cast());
        final fileSystemNameBuffer = PWSTR(arena<WCHAR>(bufferLength).cast());
        final volumeSerialNumber = arena<DWORD>();
        final maxComponentLength = arena<DWORD>();
        final fileSystemFlags = arena<DWORD>();
        final result = GetVolumeInformation(
          arena.pcwstr(rootPath),
          volumeNameBuffer,
          bufferLength,
          volumeSerialNumber,
          maxComponentLength,
          fileSystemFlags,
          fileSystemNameBuffer,
          bufferLength,
        );

        if (!result.value) {
          LoggerService.warning(
            'Erro ao obter Volume Serial Number: ${result.error}',
          );
          return '';
        }

        return volumeSerialNumber.value
            .toRadixString(16)
            .toUpperCase()
            .padLeft(8, '0');
      });
    } on Object catch (e) {
      LoggerService.warning('Erro ao obter Volume Serial Number: $e');
      return '';
    }
  }
}

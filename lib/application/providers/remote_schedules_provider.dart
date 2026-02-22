import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/utils/error_mapper.dart'
    show mapExceptionToMessage;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:flutter/foundation.dart';

class RemoteSchedulesProvider extends ChangeNotifier {
  RemoteSchedulesProvider(
    this._connectionManager, {
    RemoteFileTransferProvider? transferProvider,
    TempDirectoryService? tempDirectoryService,
  }) : _transferProvider = transferProvider,
       _tempDirectoryService =
           tempDirectoryService ?? getIt<TempDirectoryService>();

  final ConnectionManager _connectionManager;
  final RemoteFileTransferProvider? _transferProvider;
  final TempDirectoryService _tempDirectoryService;

  List<Schedule> _schedules = [];
  bool _isLoading = false;
  bool _isUpdating = false;
  bool _isExecuting = false;
  String? _error;
  String? _updatingScheduleId;
  String? _executingScheduleId;

  String? _backupStep;
  String? _backupMessage;
  double? _backupProgress;

  // Transfer progress fields
  String? _transferStep;
  String? _transferMessage;
  double? _transferProgress;
  bool _isTransferringFile = false;

  List<Schedule> get schedules => _schedules;
  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  bool get isExecuting => _isExecuting;
  String? get error => _error;
  bool get isConnected => _connectionManager.isConnected;
  String? get updatingScheduleId => _updatingScheduleId;
  String? get executingScheduleId => _executingScheduleId;
  String? get backupStep => _backupStep;
  String? get backupMessage => _backupMessage;
  double? get backupProgress => _backupProgress;
  String? get transferStep => _transferStep;
  String? get transferMessage => _transferMessage;
  double? get transferProgress => _transferProgress;
  bool get isTransferringFile => _isTransferringFile;

  Future<void> loadSchedules() async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para ver os agendamentos.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _connectionManager.listSchedules();

    result.fold(
      (list) {
        _schedules = list;
        _isLoading = false;
      },
      (exception) {
        _error = mapExceptionToMessage(exception);
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<bool> updateSchedule(Schedule schedule) async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para atualizar agendamentos.';
      notifyListeners();
      return false;
    }

    _isUpdating = true;
    _updatingScheduleId = schedule.id;
    _error = null;
    notifyListeners();

    final result = await _connectionManager.updateSchedule(schedule);

    return result.fold(
      (updated) {
        final index = _schedules.indexWhere((s) => s.id == updated.id);
        if (index >= 0) {
          _schedules = List<Schedule>.from(_schedules)..[index] = updated;
        }
        _error = null;
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        return true;
      },
      (exception) {
        _error = mapExceptionToMessage(exception);
        _isUpdating = false;
        _updatingScheduleId = null;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> executeSchedule(String scheduleId) async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para executar agendamentos.';
      notifyListeners();
      return false;
    }

    _isExecuting = true;
    _executingScheduleId = scheduleId;
    _error = null;
    _backupStep = null;
    _backupMessage = null;
    _backupProgress = null;
    _transferStep = null;
    _transferMessage = null;
    _transferProgress = null;
    _isTransferringFile = false;
    notifyListeners();

    // Validar permissão na pasta de downloads antes de iniciar o backup no servidor
    _backupStep = 'Validando configurações';
    _backupMessage = 'Verificando permissões na pasta temporária...';
    notifyListeners();

    final hasPermission = await _tempDirectoryService
        .validateDownloadsDirectory();
    if (!hasPermission) {
      final downloadsDir = await _tempDirectoryService.getDownloadsDirectory();
      _error =
          'Sem permissão de escrita na pasta temporária:\n${downloadsDir.path}\n\n'
          'Execute o aplicativo como Administrador ou configure outra pasta em Configurações > Geral.';
      _isExecuting = false;
      _executingScheduleId = null;
      _backupStep = null;
      _backupMessage = null;
      _backupProgress = null;
      _transferStep = null;
      _transferMessage = null;
      _transferProgress = null;
      _isTransferringFile = false;
      notifyListeners();
      return false;
    }

    LoggerService.info('✓ Pasta de downloads validada com sucesso');

    final result = await _connectionManager.executeSchedule(
      scheduleId,
      onProgress: (step, message, progress) {
        _backupStep = step;
        _backupMessage = message;
        _backupProgress = progress;
        notifyListeners();
      },
    );

    return result.fold(
      (backupPath) async {
        LoggerService.info('===== BACKUP CONCLUÍDO NO SERVIDOR =====');
        LoggerService.info('BackupPath recebido: "$backupPath"');
        LoggerService.info('BackupPath está vazio? ${backupPath.isEmpty}');
        LoggerService.info(
          '_transferProvider é null? ${_transferProvider == null}',
        );

        if (backupPath.isEmpty || _transferProvider == null) {
          LoggerService.warning(
            '⚠️ DOWNLOAD CANCELADO: backupPath.isEmpty=${backupPath.isEmpty}, _transferProvider==null=${_transferProvider == null}',
          );
          _error = null;
          _isExecuting = false;
          _executingScheduleId = null;
          _backupStep = null;
          _backupMessage = null;
          _backupProgress = null;
          notifyListeners();
          return true;
        }

        // Backup concluído no servidor, agora baixar o arquivo
        LoggerService.info('===== INICIANDO DOWNLOAD DO ARQUIVO =====');
        _backupStep = 'Baixando arquivo';
        _backupMessage = 'Transferindo backup do servidor...';
        _backupProgress = null;
        notifyListeners();

        final downloadSuccess = await _transferProvider.transferCompletedBackupToClient(
          scheduleId,
          backupPath,
          onTransferProgress: (step, message, progress) {
            // Atualizar progresso da transferência
            // CORREÇÃO: Atualizar também os campos de backup para que a UI (Card) exiba o progresso
            _backupStep = step;
            _backupMessage = message;
            _backupProgress = progress;

            // Manter campos específicos de transferência atualizados por compatibilidade
            _transferStep = step;
            _transferMessage = message;
            _transferProgress = progress;

            _isTransferringFile = true;
            notifyListeners();
            LoggerService.debug(
              '[TransferProgress] $step: ${(progress * 100).toStringAsFixed(1)}%',
            );
          },
        );

        _isTransferringFile = false;
        LoggerService.info('===== DOWNLOAD FINALIZADO =====');
        LoggerService.info('DownloadSuccess: $downloadSuccess');

        _error = null;
        _isExecuting = false;
        _executingScheduleId = null;
        _backupStep = null;
        _backupMessage = null;
        _backupProgress = null;
        _transferStep = null;
        _transferMessage = null;
        _transferProgress = null;
        notifyListeners();

        return downloadSuccess;
      },
      (exception) {
        _error = mapExceptionToMessage(exception);
        _isExecuting = false;
        _executingScheduleId = null;
        _backupStep = null;
        _backupMessage = null;
        _backupProgress = null;
        _transferStep = null;
        _transferMessage = null;
        _transferProgress = null;
        _isTransferringFile = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> cancelSchedule() async {
    if (!_connectionManager.isConnected) {
      _error = 'Conecte-se a um servidor para cancelar agendamentos.';
      notifyListeners();
      return false;
    }

    if (_executingScheduleId == null) {
      _error = 'Nenhum backup em execução para cancelar.';
      notifyListeners();
      return false;
    }

    final result = await _connectionManager.cancelSchedule(
      _executingScheduleId!,
    );

    return result.fold(
      (_) {
        _isExecuting = false;
        _executingScheduleId = null;
        _backupStep = null;
        _backupMessage = null;
        _backupProgress = null;
        _transferStep = null;
        _transferMessage = null;
        _transferProgress = null;
        _isTransferringFile = false;
        _error = null;
        notifyListeners();
        return true;
      },
      (exception) {
        _error = mapExceptionToMessage(exception);
        notifyListeners();
        return false;
      },
    );
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  static const String _connectionLostMessage =
      'Conexão perdida; o backup pode ter continuado no servidor.';

  void clearExecutionStateOnDisconnect() {
    if (_executingScheduleId == null) return;
    _isExecuting = false;
    _executingScheduleId = null;
    _backupStep = null;
    _backupMessage = null;
    _backupProgress = null;
    _transferStep = null;
    _transferMessage = null;
    _transferProgress = null;
    _isTransferringFile = false;
    _error = _connectionLostMessage;
    notifyListeners();
  }
}

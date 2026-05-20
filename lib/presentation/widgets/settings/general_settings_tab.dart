import 'dart:async';

import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/machine_storage_settings_section.dart';
import 'package:backup_database/presentation/widgets/settings/updates_settings_section.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';

class GeneralSettingsTab extends StatefulWidget {
  const GeneralSettingsTab({super.key});

  @override
  State<GeneralSettingsTab> createState() => _GeneralSettingsTabState();
}

class _GeneralSettingsTabState extends State<GeneralSettingsTab> {
  String? _tempDownloadsPath;
  bool _isLoadingTempPath = false;

  final TempDirectoryService _tempService = getIt<TempDirectoryService>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadTempPath());
  }

  Future<void> _loadTempPath() async {
    if (!mounted) return;
    setState(() => _isLoadingTempPath = true);
    try {
      final dir = await _tempService.getDownloadsDirectory();
      if (mounted) {
        setState(() {
          _tempDownloadsPath = dir.path;
          _isLoadingTempPath = false;
        });
      }
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar pasta temporÃ¡ria', e, s);
      if (mounted) {
        setState(() => _isLoadingTempPath = false);
      }
    }
  }

  Future<void> _changeTempPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: appLocaleString(
        context,
        'Selecionar pasta temporÃ¡ria de downloads',
        'Select temporary downloads folder',
      ),
    );
    if (result != null && mounted) {
      setState(() => _isLoadingTempPath = true);
      final success = await _tempService.setCustomTempPath(result);
      if (mounted) {
        setState(() => _isLoadingTempPath = false);
        if (!success) {
          unawaited(
            MessageModal.showError(
              context,
              message: appLocaleString(
                context,
                'NÃ£o foi possÃ­vel definir a pasta temporÃ¡ria. Verifique se tem permissÃ£o de escrita.',
                'Could not set temporary folder. Check write permissions.',
              ),
            ),
          );
          return;
        }
        await _loadTempPath();
        if (!mounted) {
          return;
        }
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: appLocaleString(
              context,
              'Pasta temporÃ¡ria alterada com sucesso!',
              'Temporary folder changed successfully!',
            ),
          ),
        );
      }
    }
  }

  Future<void> _resetTempPath() async {
    final confirmed = await MessageModal.showConfirm(
      context,
      title: appLocaleString(context, 'Confirmar', 'Confirm'),
      message: appLocaleString(
        context,
        'Deseja voltar a usar a pasta temporÃ¡ria padrÃ£o do sistema?',
        'Do you want to use the system default temporary folder again?',
      ),
      confirmLabel: appLocaleString(context, 'Confirmar', 'Confirm'),
      confirmIcon: FluentIcons.refresh,
    );
    if (confirmed && mounted) {
      await _tempService.clearCustomTempPath();
      await _loadTempPath();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UpdatesSettingsSection(),
          const SizedBox(height: 24),
          if (currentAppMode == AppMode.client) ...[
            _buildClientDownloadsSection(context),
            const SizedBox(height: 24),
          ],
          const MachineStorageSettingsSection(),
        ],
      ),
    );
  }

  Widget _buildClientDownloadsSection(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(
        context,
        'Pasta temporÃ¡ria de downloads',
        'Temporary downloads folder',
      ),
      description: appLocaleString(
        context,
        'Arquivos recebidos do servidor passam por esta pasta antes do envio final.',
        'Files received from the server pass through this folder before final delivery.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appLocaleString(context, 'Pasta atual', 'Current folder'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (_isLoadingTempPath)
                      Text(
                        appLocaleString(context, 'Carregando...', 'Loading...'),
                      )
                    else
                      SelectableText(
                        _tempDownloadsPath ??
                            appLocaleString(context, 'Desconhecida', 'Unknown'),
                        style: FluentTheme.of(context).typography.caption
                            ?.copyWith(
                              fontFamily: 'Consolas',
                            ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  FilledButton(
                    onPressed: _isLoadingTempPath
                        ? null
                        : () => unawaited(_changeTempPath()),
                    child: Text(
                      appLocaleString(
                        context,
                        'Alterar pasta',
                        'Change folder',
                      ),
                    ),
                  ),
                  Button(
                    onPressed: _isLoadingTempPath
                        ? null
                        : () => unawaited(_resetTempPath()),
                    child: Text(
                      appLocaleString(
                        context,
                        'Usar padrÃ£o do sistema',
                        'Use system default',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(FluentIcons.refresh),
                    onPressed: _isLoadingTempPath
                        ? null
                        : () => unawaited(_loadTempPath()),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

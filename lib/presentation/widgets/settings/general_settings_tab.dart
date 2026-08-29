import 'dart:async';

import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/machine_storage_settings_section.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
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
      LoggerService.warning('Erro ao carregar pasta temporária', e, s);
      if (mounted) {
        setState(() => _isLoadingTempPath = false);
      }
    }
  }

  Future<void> _changeTempPath() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: appLocaleString(
        context,
        'Selecionar pasta temporária de downloads',
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
                'Não foi possível definir a pasta temporária. Verifique se tem permissão de escrita.',
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
              'Pasta temporária alterada com sucesso!',
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
        'Deseja voltar a usar a pasta temporária padrão do sistema?',
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
      padding: AppSpacing.paddingLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UpdatesSettingsSection(),
          AppSpacing.gapLg,
          if (currentAppMode == AppMode.client) ...[
            _buildClientDownloadsSection(context),
            AppSpacing.gapLg,
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
        'Pasta temporária de downloads',
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
                      style: FluentTheme.of(context).typography.bodyStrong,
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
                  AppButton.primary(
                    label: appLocaleString(
                      context,
                      'Alterar pasta',
                      'Change folder',
                    ),
                    onPressed: _isLoadingTempPath
                        ? null
                        : () => unawaited(_changeTempPath()),
                  ),
                  AppButton(
                    label: appLocaleString(
                      context,
                      'Usar padrão do sistema',
                      'Use system default',
                    ),
                    onPressed: _isLoadingTempPath
                        ? null
                        : () => unawaited(_resetTempPath()),
                  ),
                  SettingsIconAction(
                    label: appLocaleString(
                      context,
                      'Atualizar pasta atual',
                      'Refresh current folder',
                    ),
                    icon: FluentIcons.refresh,
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

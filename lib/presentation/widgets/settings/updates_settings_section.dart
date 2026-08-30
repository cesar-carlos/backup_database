import 'dart:async';
import 'dart:io' show Platform;

import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/updates/update_actions_row.dart';
import 'package:backup_database/presentation/widgets/settings/updates/update_diagnostics_expander.dart';
import 'package:backup_database/presentation/widgets/settings/updates/update_status_banners.dart';
import 'package:backup_database/presentation/widgets/settings/updates/update_summary_surface.dart';
import 'package:backup_database/presentation/widgets/settings/updates/update_uac_banner.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdatesSettingsSection extends StatefulWidget {
  const UpdatesSettingsSection({super.key});

  @override
  State<UpdatesSettingsSection> createState() => _UpdatesSettingsSectionState();
}

class _UpdatesSettingsSectionState extends State<UpdatesSettingsSection> {
  late final ClipboardService _clipboardService;

  @override
  void initState() {
    super.initState();
    _clipboardService = getIt<ClipboardService>();
  }

  Future<void> _copyValue(
    String value, {
    required String successMessage,
    required String errorMessage,
  }) async {
    final success = await _clipboardService.copyToClipboard(value);
    if (!mounted) {
      return;
    }
    if (success) {
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: successMessage,
      );
      return;
    }
    await MessageModal.showError(context, message: errorMessage);
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null) {
      await MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'URL invalida para abertura externa.',
          'Invalid URL for external launch.',
        ),
      );
      return;
    }
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || opened) {
      return;
    }
    await FluentInfoBarFeedback.showWarning(
      context,
      message: appLocaleString(
        context,
        'Nao foi possivel abrir o link.',
        'Could not open the link.',
      ),
    );
  }

  Future<void> _openParentDirectory(String filePath) async {
    final directoryPath = p.dirname(filePath);
    final uri = Uri.directory(directoryPath, windows: Platform.isWindows);
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || opened) {
      return;
    }
    await FluentInfoBarFeedback.showWarning(
      context,
      message: appLocaleString(
        context,
        'Nao foi possivel abrir a pasta.',
        'Could not open the folder.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final autoUpdateProvider = Provider.of<AutoUpdateProvider>(context);
    final features = getIt<FeatureAvailabilityService>();
    final lastCheckLabel = autoUpdateProvider.lastCheckDate != null
        ? appLocaleLastUpdateCheckSubtitle(
            context,
            autoUpdateProvider.lastCheckDate!,
          )
        : appLocaleString(context, 'Nunca verificado', 'Never checked');

    return AppSectionCard(
      title: appLocaleString(context, 'Atualizacoes', 'Updates'),
      description: appLocaleString(
        context,
        'Resumo do updater, acoes rapidas e diagnosticos tecnicos.',
        'Updater summary, quick actions and technical diagnostics.',
      ),
      banner: !features.isAutoUpdateEnabled
          ? InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Atualizacoes automaticas indisponiveis',
                  'Automatic updates unavailable',
                ),
              ),
              content: Text(
                localizeCompatibilityReason(
                  context,
                  reason: features.autoUpdateDisabledReason,
                  fallbackPt: 'Nao suportado nesta versao do Windows.',
                  fallbackEn: 'Not supported on this Windows version.',
                ),
              ),
              severity: InfoBarSeverity.warning,
              isLong: true,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UpdateSummarySurface(
            provider: autoUpdateProvider,
            lastCheckLabel: lastCheckLabel,
          ),
          const SizedBox(height: AppSpacing.md),
          UpdateActionsRow(
            provider: autoUpdateProvider,
            onCheckUpdates: autoUpdateProvider.checkForUpdates,
            onOpenConfigFolder: () => unawaited(
              _openParentDirectory(autoUpdateProvider.configFilePath),
            ),
            onCopyFeed: () {
              final feedUrl = autoUpdateProvider.feedUrl;
              if (feedUrl == null) return;
              unawaited(
                _copyValue(
                  feedUrl,
                  successMessage: appLocaleString(
                    context,
                    'Feed copiado para a area de transferencia.',
                    'Feed copied to the clipboard.',
                  ),
                  errorMessage: appLocaleString(
                    context,
                    'Nao foi possivel copiar o feed.',
                    'Could not copy the feed.',
                  ),
                ),
              );
            },
            onOpenFeed: () {
              final feedUrl = autoUpdateProvider.feedUrl;
              if (feedUrl == null) return;
              unawaited(_openUrl(feedUrl));
            },
          ),
          if (autoUpdateProvider.isBlockedByUacPolicy) ...[
            const SizedBox(height: AppSpacing.md),
            UpdateUacBanner(
              provider: autoUpdateProvider,
              onUpdateNow: autoUpdateProvider.checkForUpdates,
            ),
          ],
          UpdateStatusBanners(provider: autoUpdateProvider),
          const SizedBox(height: AppSpacing.md),
          UpdateDiagnosticsExpander(
            provider: autoUpdateProvider,
            onCopyFeed: () => unawaited(
              _copyValue(
                autoUpdateProvider.feedUrl!,
                successMessage: appLocaleString(
                  context,
                  'Feed copiado para a area de transferencia.',
                  'Feed copied to the clipboard.',
                ),
                errorMessage: appLocaleString(
                  context,
                  'Nao foi possivel copiar o feed.',
                  'Could not copy the feed.',
                ),
              ),
            ),
            onOpenFeed: () => unawaited(_openUrl(autoUpdateProvider.feedUrl!)),
            onCopyContextPath: () => unawaited(
              _copyValue(
                autoUpdateProvider.updateContextPath,
                successMessage: appLocaleString(
                  context,
                  'Caminho copiado para a area de transferencia.',
                  'Path copied to the clipboard.',
                ),
                errorMessage: appLocaleString(
                  context,
                  'Nao foi possivel copiar o caminho.',
                  'Could not copy the path.',
                ),
              ),
            ),
            onOpenContextFolder: () => unawaited(
              _openParentDirectory(autoUpdateProvider.updateContextPath),
            ),
            onCopyDiagnosticsPath: () => unawaited(
              _copyValue(
                autoUpdateProvider.diagnosticsPath,
                successMessage: appLocaleString(
                  context,
                  'Caminho copiado para a area de transferencia.',
                  'Path copied to the clipboard.',
                ),
                errorMessage: appLocaleString(
                  context,
                  'Nao foi possivel copiar o caminho.',
                  'Could not copy the path.',
                ),
              ),
            ),
            onOpenDiagnosticsFolder: () => unawaited(
              _openParentDirectory(autoUpdateProvider.diagnosticsPath),
            ),
            onCopyLockPath: () => unawaited(
              _copyValue(
                autoUpdateProvider.lockFilePath,
                successMessage: appLocaleString(
                  context,
                  'Caminho copiado para a area de transferencia.',
                  'Path copied to the clipboard.',
                ),
                errorMessage: appLocaleString(
                  context,
                  'Nao foi possivel copiar o caminho.',
                  'Could not copy the path.',
                ),
              ),
            ),
            onOpenLockFolder: () => unawaited(
              _openParentDirectory(autoUpdateProvider.lockFilePath),
            ),
          ),
        ],
      ),
    );
  }
}

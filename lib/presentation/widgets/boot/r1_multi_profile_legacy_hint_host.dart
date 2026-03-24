import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/bootstrap/machine_scope_r1_legacy_paths_hint.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:fluent_ui/fluent_ui.dart';

class R1MultiProfileLegacyHintHost extends StatefulWidget {
  const R1MultiProfileLegacyHintHost({required this.child, super.key});

  final Widget child;

  @override
  State<R1MultiProfileLegacyHintHost> createState() =>
      _R1MultiProfileLegacyHintHostState();
}

class _R1MultiProfileLegacyHintHostState
    extends State<R1MultiProfileLegacyHintHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showHintIfNeeded());
    });
  }

  Future<void> _showHintIfNeeded() async {
    if (!Platform.isWindows || !mounted) {
      return;
    }
    final hint = getIt<MachineScopeR1LegacyPathsHint>();
    if (!hint.hasDetectedOtherProfiles) {
      return;
    }
    final prefs = getIt<IUserPreferencesRepository>();
    final lastSig = await prefs
        .getR1MultiProfileLegacyHintLastDismissedSignature();
    if (lastSig == hint.dismissalSignature) {
      return;
    }
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ContentDialog(
          title: Text(
            appLocaleString(
              dialogContext,
              'Outros perfis Windows com dados antigos',
              'Other Windows profiles with legacy data',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  appLocaleString(
                    dialogContext,
                    'Foram detetadas pastas de dados do Backup Database noutros '
                        'utilizadores deste PC. A migração automática só usou o perfil '
                        'atual. Se precisar de dados de outro perfil, copie manualmente '
                        'os ficheiros .db para a pasta de dados em ProgramData (ou '
                        'peça suporte). Caminhos detetados:',
                    'Legacy Backup Database folders were found under other Windows '
                        'user profiles on this PC. Automatic migration only used the '
                        'current profile. If you need data from another profile, copy '
                        'the .db files manually to the ProgramData data folder (or '
                        'contact support). Detected paths:',
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  hint.otherProfilesLegacySqlitePaths.join('\n'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () async {
                await prefs.setR1MultiProfileLegacyHintLastDismissedSignature(
                  hint.dismissalSignature,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text(
                appLocaleString(dialogContext, 'Entendi', 'OK'),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

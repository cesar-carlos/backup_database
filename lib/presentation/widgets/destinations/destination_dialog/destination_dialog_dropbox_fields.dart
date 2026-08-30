import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — Dropbox auth status, OAuth setup and folder fields.
class DropboxDestinationFields extends StatelessWidget {
  const DropboxDestinationFields({
    required this.authStatus,
    required this.folderFields,
    super.key,
    this.oauthAvailabilityWarning,
    this.oauthConfigSection,
    this.notSignedInWarning,
  });

  final Widget? oauthAvailabilityWarning;
  final Widget authStatus;
  final Widget? oauthConfigSection;
  final Widget folderFields;
  final Widget? notSignedInWarning;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (oauthAvailabilityWarning != null) ...[
          oauthAvailabilityWarning!,
          const SizedBox(height: AppSpacing.md),
        ],
        authStatus,
        if (oauthConfigSection != null) ...[
          const SizedBox(height: AppSpacing.md),
          oauthConfigSection!,
        ],
        const SizedBox(height: AppSpacing.md),
        folderFields,
        if (notSignedInWarning != null) ...[
          const SizedBox(height: AppSpacing.md),
          notSignedInWarning!,
        ],
      ],
    );
  }
}

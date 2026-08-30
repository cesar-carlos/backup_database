import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — OAuth signed-in/out status with connect or disconnect.
class OAuthStatusCard extends StatelessWidget {
  const OAuthStatusCard({
    required this.isSignedIn,
    required this.isLoading,
    required this.isConfigured,
    required this.signedInBackgroundColor,
    required this.signedInBorderColor,
    required this.signedInIconColor,
    required this.signedInLabel,
    required this.signedOutLabel,
    required this.disconnectLabel,
    required this.connectLabel,
    required this.connectingLabel,
    required this.onDisconnect,
    super.key,
    this.errorMessage,
    this.onConnect,
  });

  final bool isSignedIn;
  final bool isLoading;
  final bool isConfigured;
  final Color signedInBackgroundColor;
  final Color signedInBorderColor;
  final Color signedInIconColor;
  final String signedInLabel;
  final String signedOutLabel;
  final String disconnectLabel;
  final String connectLabel;
  final String connectingLabel;
  final String? errorMessage;
  final VoidCallback onDisconnect;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final neutralColor = FluentTheme.of(
      context,
    ).resources.controlStrokeColorDefault;

    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: isSignedIn
            ? signedInBackgroundColor
            : FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        borderRadius: AppRadius.circularMd,
        border: Border.all(
          color: isSignedIn
              ? signedInBorderColor
              : neutralColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSignedIn
                    ? FluentIcons.check_mark
                    : FluentIcons.cloud_download,
                color: isSignedIn ? signedInIconColor : neutralColor,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isSignedIn ? signedInLabel : signedOutLabel,
                  style: FluentTheme.of(
                    context,
                  ).typography.body?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isSignedIn)
            AppButton.icon(
              icon: FluentIcons.sign_out,
              label: disconnectLabel,
              onPressed: isLoading ? null : onDisconnect,
            )
          else if (isConfigured)
            AppButton(
              label: isLoading ? connectingLabel : connectLabel,
              onPressed: isLoading ? null : onConnect,
              leading: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.signin, size: 18),
            ),
          if (errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              errorMessage!,
              style: FluentTheme.of(
                context,
              ).typography.caption?.copyWith(color: context.colors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

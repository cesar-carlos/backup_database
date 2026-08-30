import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — warning when external-browser OAuth is unavailable.
class OAuthAvailabilityWarning extends StatelessWidget {
  const OAuthAvailabilityWarning({
    required this.labelBuilder,
    super.key,
  });

  final DestinationDialogLabelBuilder labelBuilder;

  static Widget? maybeOf({
    required BuildContext context,
    required DestinationDialogLabelBuilder labelBuilder,
  }) {
    final features = getIt<FeatureAvailabilityService>();
    if (features.isExternalBrowserOAuthEnabled) {
      return null;
    }
    return OAuthAvailabilityWarning(labelBuilder: labelBuilder);
  }

  @override
  Widget build(BuildContext context) {
    final features = getIt<FeatureAvailabilityService>();
    return AppCallout(
      tone: AppCalloutTone.warning,
      message:
          '${labelBuilder('Inicio de sessao OAuth', 'OAuth sign-in')}. '
          '${localizeCompatibilityReason(
            context,
            reason: features.externalBrowserOAuthDisabledReason,
            fallbackPt: 'Não disponível nesta versão do Windows.',
            fallbackEn: 'Not available on this Windows version.',
          )}',
    );
  }
}

import 'package:backup_database/core/constants/integrity_ui_strings.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/presentation/widgets/common/message_modal.dart';
import 'package:flutter/widgets.dart';

class IntegrityErrorModalHelper {
  IntegrityErrorModalHelper._();

  static void showExecutionErrorModal({
    required BuildContext context,
    required String? failureCode,
    required String message,
    String Function(Locale locale)? defaultErrorTitleBuilder,
  }) {
    final locale = Localizations.localeOf(context);

    if (failureCode == FailureCodes.integrityValidationInconclusive ||
        failureCode == FailureCodes.ftpIntegrityValidationInconclusive) {
      MessageModal.showWarning(
        context,
        title: IntegrityUiStrings.integrityInconclusiveTitle(locale),
        message: IntegrityUiStrings.integrityInconclusiveMessage(
          locale,
          message,
        ),
      );
      return;
    }

    if (failureCode == FailureCodes.integrityValidationFailed ||
        failureCode == FailureCodes.ftpIntegrityValidationFailed) {
      MessageModal.showError(
        context,
        title: IntegrityUiStrings.integrityFailedTitle(locale),
        message: IntegrityUiStrings.integrityFailedMessage(
          locale,
          message,
        ),
      );
      return;
    }

    MessageModal.showError(
      context,
      title: defaultErrorTitleBuilder?.call(locale),
      message: message,
    );
  }
}

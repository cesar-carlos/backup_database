import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:flutter/widgets.dart';

typedef DestinationDialogLabelBuilder = String Function(
  String ptBr,
  String enUs,
);

String destinationDialogLabel(
  BuildContext context,
  String ptBr,
  String enUs,
) => appLocaleString(context, ptBr, enUs);

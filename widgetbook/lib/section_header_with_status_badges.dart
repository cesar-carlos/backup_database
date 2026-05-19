import 'package:backup_database/presentation/widgets/molecules/section_header_with_status_badges.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(
  name: 'With active and inactive',
  type: SectionHeaderWithStatusBadges,
)
Widget buildSectionHeaderWithStatusBadgesDefaultUseCase(BuildContext context) {
  return const SectionHeaderWithStatusBadges(
    label: 'All configurations',
    count: 12,
    activeCount: 9,
    inactiveCount: 3,
  );
}

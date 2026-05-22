import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/atoms/app_shimmer.dart';
import 'package:backup_database/presentation/widgets/molecules/skeleton_card.dart';
import 'package:flutter/widgets.dart';

/// **Organism** — mimics database config stacked sections while loading.
class SkeletonDatabaseConfigBody extends StatelessWidget {
  const SkeletonDatabaseConfigBody({
    super.key,
    this.sectionCount = 4,
  });

  final int sectionCount;

  @override
  Widget build(BuildContext context) {
    final titleFill = context.colors.outline;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < sectionCount; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.lg),
              ClipRRect(
                borderRadius: AppRadius.circularSm,
                child: SizedBox(
                  width: 220,
                  height: 18,
                  child: ColoredBox(color: titleFill),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const SkeletonCard(lineCount: 4, minHeight: 120),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:backup_database/core/theme/tokens/tokens.dart';
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

  static const Color _titleFill = Color(0xFFBDBDBD);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < sectionCount; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.lg),
              const ClipRRect(
                borderRadius: AppRadius.circularSm,
                child: SizedBox(
                  width: 220,
                  height: 18,
                  child: ColoredBox(color: _titleFill),
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

import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/atoms/app_shimmer.dart';
import 'package:flutter/widgets.dart';

/// **Organism** — three-column stat placeholders for dashboard initial load.
class SkeletonDashboardMetrics extends StatelessWidget {
  const SkeletonDashboardMetrics({super.key});

  @override
  Widget build(BuildContext context) {
    final fill = context.colors.outline.withValues(alpha: 0.35);
    return AppShimmer(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List<Widget>.generate(3, (_) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: ClipRRect(
                borderRadius: AppRadius.circularLg,
                child: SizedBox(
                  height: 112,
                  child: ColoredBox(color: fill),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

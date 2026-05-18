import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/atoms/app_shimmer.dart';
import 'package:flutter/widgets.dart';

/// **Organism** — three-column stat placeholders for dashboard initial load.
class SkeletonDashboardMetrics extends StatelessWidget {
  const SkeletonDashboardMetrics({super.key});

  static const Color _fill = Color(0xFFBDBDBD);

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List<Widget>.generate(3, (_) {
          return const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: ClipRRect(
                borderRadius: AppRadius.circularLg,
                child: SizedBox(
                  height: 112,
                  child: ColoredBox(color: _fill),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

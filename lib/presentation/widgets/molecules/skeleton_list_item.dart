import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:flutter/widgets.dart';

/// **Molecule** — single-row placeholder for list-like skeletons.
class SkeletonListItem extends StatelessWidget {
  const SkeletonListItem({
    super.key,
    this.leadingSize = 40,
  });

  final double leadingSize;

  static const Color _fill = Color(0xFFBDBDBD);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadius.circularMd,
            child: SizedBox(
              width: leadingSize,
              height: leadingSize,
              child: const ColoredBox(color: _fill),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: AppRadius.circularSm,
                  child: SizedBox(
                    height: 12,
                    width: double.infinity,
                    child: ColoredBox(color: _fill),
                  ),
                ),
                SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: AppRadius.circularSm,
                  child: SizedBox(
                    height: 10,
                    width: 160,
                    child: ColoredBox(color: _fill),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

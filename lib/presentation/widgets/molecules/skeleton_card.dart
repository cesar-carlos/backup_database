import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:flutter/widgets.dart';

/// **Molecule** — block placeholder resembling a compact card body.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.lineCount = 3,
    this.minHeight = 96,
  });

  final int lineCount;
  final double minHeight;

  static const Color _fill = Color(0xFFBDBDBD);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: ClipRRect(
        borderRadius: AppRadius.circularLg,
        child: ColoredBox(
          color: _fill.withValues(alpha: 0.35),
          child: Padding(
            padding: AppSpacing.paddingMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < lineCount; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: AppRadius.circularSm,
                    child: SizedBox(
                      height: i == 0 ? 14 : 10,
                      width: i == lineCount - 1 ? 120 : double.infinity,
                      child: const ColoredBox(color: _fill),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

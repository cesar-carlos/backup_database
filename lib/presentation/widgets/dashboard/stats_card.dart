import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';

class StatsCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData? icon;
  final String? iconSvg;
  final Color? color;

  const StatsCard({
    super.key,
    required this.title,
    required this.value,
    this.icon,
    this.iconSvg,
    this.color,
  }) : assert(
         icon != null || iconSvg != null,
         'Either icon or iconSvg must be provided',
       );

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? AppColors.primary;

    return Card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: iconSvg != null
                    ? SvgPicture.asset(
                        iconSvg!,
                        width: 28,
                        height: 28,
                        colorFilter: ColorFilter.mode(
                          cardColor,
                          BlendMode.srcIn,
                        ),
                      )
                    : Icon(icon, color: cardColor, size: 28),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: FluentTheme.of(context).typography.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: FluentTheme.of(context).typography.body,
          ),
        ],
      ),
    );
  }
}

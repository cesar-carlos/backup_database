import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _factTileMinWidth = 180;
const double _factTileMaxWidth = 280;

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    required this.title,
    required this.value,
    super.key,
    this.description,
    this.onChanged,
    this.disabledReason,
  });

  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final typography = FluentTheme.of(context).typography;
    final captionStyle = typography.caption;
    final titleStyle = typography.body?.copyWith(fontWeight: FontWeight.w600);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: titleStyle),
                  if (description != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(description!, style: captionStyle),
                  ],
                  if (disabledReason != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      disabledReason!,
                      style: captionStyle?.copyWith(
                        color: context.colors.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            ToggleSwitch(
              checked: value,
              onChanged: onChanged,
              semanticLabel: title,
            ),
          ],
        ),
      ],
    );
  }
}

class SettingsTechnicalItem extends StatelessWidget {
  const SettingsTechnicalItem({
    required this.title,
    required this.value,
    super.key,
    this.description,
    this.onCopy,
    this.onOpen,
    this.openTooltip,
  });

  final String title;
  final String value;
  final String? description;
  final VoidCallback? onCopy;
  final VoidCallback? onOpen;
  final String? openTooltip;

  @override
  Widget build(BuildContext context) {
    final typography = FluentTheme.of(context).typography;
    final captionStyle = typography.caption;
    final titleStyle = typography.body?.copyWith(fontWeight: FontWeight.w600);
    final valueStyle = captionStyle?.copyWith(
      fontFamily: 'Consolas',
      height: 1.35,
    );
    final borderColor = context.colors.outline.withValues(alpha: 0.24);
    final backgroundColor = context.colors.outline.withValues(alpha: 0.08);
    final copyLabel = appLocaleString(context, 'Copiar', 'Copy');
    final openLabel = openTooltip ?? appLocaleString(context, 'Abrir', 'Open');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: titleStyle),
                  if (description != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(description!, style: captionStyle),
                  ],
                ],
              ),
            ),
            if (onCopy != null)
              _SettingsIconAction(
                label: copyLabel,
                icon: FluentIcons.copy,
                onPressed: onCopy,
              ),
            if (onOpen != null)
              _SettingsIconAction(
                label: openLabel,
                icon: FluentIcons.open_file,
                onPressed: onOpen,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: AppRadius.circularMd,
            border: Border.all(color: borderColor),
          ),
          child: SelectableText(value, style: valueStyle),
        ),
      ],
    );
  }
}

class _SettingsIconAction extends StatelessWidget {
  const _SettingsIconAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: IconButton(
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class SettingsFactTile extends StatelessWidget {
  const SettingsFactTile({
    required this.label,
    required this.value,
    super.key,
    this.caption,
    this.expandToFit = false,
  });

  final String label;
  final String value;
  final String? caption;
  final bool expandToFit;

  @override
  Widget build(BuildContext context) {
    final captionStyle = FluentTheme.of(context).typography.caption;
    final borderColor = context.colors.outline.withValues(alpha: 0.22);
    final backgroundColor = context.colors.outline.withValues(alpha: 0.08);

    return Container(
      width: expandToFit ? double.infinity : null,
      constraints: expandToFit
          ? const BoxConstraints(minWidth: _factTileMinWidth)
          : const BoxConstraints(
              minWidth: _factTileMinWidth,
              maxWidth: _factTileMaxWidth,
            ),
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.circularMd,
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: captionStyle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: FluentTheme.of(context).typography.subtitle,
          ),
          if (caption != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(caption!, style: captionStyle),
          ],
        ],
      ),
    );
  }
}

import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// **Atom** — labeled text field with semantic error color.
class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.label,
    super.key,
    this.hint,
    this.controller,
    this.initialValue,
    this.validator,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.suffixIcon,
    this.prefixIcon,
    this.enabled = true,
    this.inputFormatters,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? initialValue;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int maxLines;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;

  Widget? _buildPrefixIcon() {
    if (prefixIcon == null) return null;

    if (prefixIcon is Icon) {
      final icon = prefixIcon! as Icon;
      return Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: Icon(icon.icon, size: 18, color: icon.color),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: prefixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    String? errorText;
    if (validator != null && controller != null) {
      errorText = validator!(controller!.text);
    }

    final textBox = TextBox(
      controller: controller,
      placeholder: hint,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      suffix: suffixIcon,
      prefix: _buildPrefixIcon(),
    );

    if (errorText != null) {
      return Semantics(
        textField: true,
        label: label,
        hint: hint,
        child: InfoLabel(
          label: label,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textBox,
              const SizedBox(height: AppSpacing.xs, width: AppSpacing.xs),
              Text(
                errorText,
                style: FluentTheme.of(
                  context,
                ).typography.caption?.copyWith(color: context.colors.danger),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      textField: true,
      label: label,
      hint: hint,
      child: InfoLabel(label: label, child: textBox),
    );
  }
}

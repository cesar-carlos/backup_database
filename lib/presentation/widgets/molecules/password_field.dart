import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/atoms/app_text_field.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — password entry with show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    this.label = 'Senha',
    this.hint,
    this.controller,
    this.validator,
    this.onChanged,
    this.enabled = true,
  });
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint ?? 'Digite a senha',
      obscureText: _obscureText,
      validator:
          widget.validator ??
          (value) {
            if (value == null || value.trim().isEmpty) {
              return '${widget.label} é obrigatória';
            }
            return null;
          },
      onChanged: widget.onChanged,
      enabled: widget.enabled,
      prefixIcon: const ExcludeSemantics(
        child: Icon(FluentIcons.lock),
      ),
      suffixIcon: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppTargetSize.comfortable,
          minHeight: AppTargetSize.comfortable,
        ),
        child: Semantics(
          button: true,
          label: _obscureText
              ? appLocaleString(context, 'Mostrar senha', 'Show password')
              : appLocaleString(context, 'Ocultar senha', 'Hide password'),
          child: Tooltip(
            message: _obscureText
                ? appLocaleString(context, 'Mostrar senha', 'Show password')
                : appLocaleString(context, 'Ocultar senha', 'Hide password'),
            child: IconButton(
              onPressed: widget.enabled
                  ? () {
                      setState(() {
                        _obscureText = !_obscureText;
                      });
                    }
                  : null,
              icon: AnimatedSwitcher(
                duration: AppDuration.fast,
                child: Icon(
                  _obscureText ? FluentIcons.view : FluentIcons.hide,
                  key: ValueKey<bool>(_obscureText),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

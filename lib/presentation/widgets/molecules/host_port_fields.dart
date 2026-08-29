import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/presentation/widgets/atoms/app_text_field.dart';
import 'package:backup_database/presentation/widgets/molecules/numeric_field.dart';
import 'package:fluent_ui/fluent_ui.dart';

const int _defaultMinPort = 1;
const int _defaultMaxPort = 65535;
const int _hostFlex = 3;

/// **Molecule** — host/server field beside a numeric port field.
class HostPortFields extends StatelessWidget {
  const HostPortFields({
    required this.hostController,
    required this.portController,
    required this.hostLabel,
    required this.portLabel,
    super.key,
    this.hostHint,
    this.portHint,
    this.hostValidator,
    this.portValidator,
    this.hostPrefixIcon = FluentIcons.server,
    this.portPrefixIcon = FluentIcons.number_field,
    this.hostEnabled = true,
  });

  final TextEditingController hostController;
  final TextEditingController portController;
  final String hostLabel;
  final String portLabel;
  final String? hostHint;
  final String? portHint;
  final String? Function(String?)? hostValidator;
  final String? Function(String?)? portValidator;
  final IconData hostPrefixIcon;
  final IconData portPrefixIcon;
  final bool hostEnabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: _hostFlex,
          child: AppTextField(
            controller: hostController,
            label: hostLabel,
            hint: hostHint,
            validator: hostValidator,
            enabled: hostEnabled,
            prefixIcon: Icon(hostPrefixIcon),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: NumericField(
            controller: portController,
            label: portLabel,
            hint: portHint,
            validator: portValidator,
            prefixIcon: portPrefixIcon,
            minValue: _defaultMinPort,
            maxValue: _defaultMaxPort,
          ),
        ),
      ],
    );
  }
}

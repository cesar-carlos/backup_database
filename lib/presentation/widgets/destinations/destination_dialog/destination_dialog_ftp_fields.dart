import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

const int _ftpMinPort = 1;
const int _ftpMaxPort = 65535;

/// **Molecule** — FTP host, port, credentials and remote path.
class FtpConnectionFields extends StatelessWidget {
  const FtpConnectionFields({
    required this.hostController,
    required this.portController,
    required this.usernameController,
    required this.passwordController,
    required this.remotePathController,
    required this.labelBuilder,
    super.key,
  });

  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController remotePathController;
  final DestinationDialogLabelBuilder labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HostPortFields(
          hostController: hostController,
          portController: portController,
          hostLabel: labelBuilder('Servidor FTP', 'FTP server'),
          portLabel: labelBuilder('Porta', 'Port'),
          hostHint: 'ftp.exemplo.com',
          portHint: '21',
          hostValidator: (String? value) {
            if (value == null || value.trim().isEmpty) {
              return labelBuilder(
                'Servidor é obrigatório',
                'Server is required',
              );
            }
            return null;
          },
          portValidator: (String? value) {
            if (value == null || value.trim().isEmpty) {
              return labelBuilder('Porta é obrigatória', 'Port is required');
            }
            final number = int.tryParse(value);
            if (number == null) {
              return labelBuilder('Valor inválido', 'Invalid value');
            }
            if (number < _ftpMinPort || number > _ftpMaxPort) {
              return labelBuilder(
                'Use um valor entre $_ftpMinPort e $_ftpMaxPort',
                'Use a value between $_ftpMinPort and $_ftpMaxPort',
              );
            }
            return null;
          },
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: usernameController,
          label: labelBuilder('Usuário', 'Username'),
          hint: 'usuario_ftp',
          prefixIcon: const Icon(FluentIcons.contact),
          validator: (String? value) {
            if (value == null || value.trim().isEmpty) {
              return labelBuilder(
                'Usuário é obrigatório',
                'Username is required',
              );
            }
            return null;
          },
        ),
        const SizedBox(height: AppSpacing.md),
        PasswordField(
          controller: passwordController,
          label: labelBuilder('Senha FTP', 'FTP password'),
          hint: labelBuilder('Senha do FTP', 'FTP password'),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: remotePathController,
          label: labelBuilder('Caminho remoto', 'Remote path'),
          hint: '/backups',
          prefixIcon: const Icon(FluentIcons.folder),
          validator: (String? value) {
            if (value == null || value.trim().isEmpty) {
              return labelBuilder(
                'Caminho remoto é obrigatório',
                'Remote path is required',
              );
            }
            return null;
          },
        ),
      ],
    );
  }
}

import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DestinationDialogTypeMeta {
  DestinationDialogTypeMeta._();

  static IconData iconOf(DestinationType type) {
    return switch (type) {
      DestinationType.local => FluentIcons.folder,
      DestinationType.ftp => FluentIcons.cloud_upload,
      DestinationType.googleDrive => FluentIcons.cloud,
      DestinationType.dropbox => FluentIcons.cloud,
      DestinationType.nextcloud => FluentIcons.cloud,
    };
  }

  static Color colorOf(DestinationType type) {
    return switch (type) {
      DestinationType.local => AppPalette.destinationLocal,
      DestinationType.ftp => AppPalette.destinationFtp,
      DestinationType.googleDrive => AppPalette.destinationGoogleDrive,
      DestinationType.dropbox => AppPalette.destinationDropbox,
      DestinationType.nextcloud => AppPalette.destinationNextcloud,
    };
  }

  static String nameOf(
    DestinationType type,
    DestinationDialogLabelBuilder label,
  ) {
    return switch (type) {
      DestinationType.local => label('Pasta local', 'Local folder'),
      DestinationType.ftp => label('Servidor FTP', 'FTP server'),
      DestinationType.googleDrive => 'Google Drive',
      DestinationType.dropbox => 'Dropbox',
      DestinationType.nextcloud => 'Nextcloud',
    };
  }

  static String sectionTitle(
    DestinationType type,
    DestinationDialogLabelBuilder label,
  ) {
    return switch (type) {
      DestinationType.local => label('Pasta local', 'Local folder'),
      DestinationType.ftp => label('Configuracao FTP', 'FTP configuration'),
      DestinationType.googleDrive => label(
        'Configuracao do Google Drive',
        'Google Drive configuration',
      ),
      DestinationType.dropbox => label(
        'Configuracao do Dropbox',
        'Dropbox configuration',
      ),
      DestinationType.nextcloud => label(
        'Configuracao do Nextcloud',
        'Nextcloud configuration',
      ),
    };
  }

  static String sectionDescription(
    DestinationType type,
    DestinationDialogLabelBuilder label,
  ) {
    return switch (type) {
      DestinationType.local => label(
        'Escolha a pasta onde os backups serao gravados nesta maquina.',
        'Choose the folder where backups will be stored on this machine.',
      ),
      DestinationType.ftp => label(
        'Informe acesso, caminho remoto e preferências de transferência segura.',
        'Provide access, remote path and secure transfer preferences.',
      ),
      DestinationType.googleDrive => label(
        'Conecte a conta Google e defina a pasta que recebera os backups.',
        'Connect a Google account and define which folder will receive backups.',
      ),
      DestinationType.dropbox => label(
        'Conecte o Dropbox e configure a pasta de publicacao dos backups.',
        'Connect Dropbox and configure the folder used to publish backups.',
      ),
      DestinationType.nextcloud => label(
        'Configure URL, credenciais e pasta remota do seu servidor Nextcloud.',
        'Configure URL, credentials and remote folder for your Nextcloud server.',
      ),
    };
  }
}

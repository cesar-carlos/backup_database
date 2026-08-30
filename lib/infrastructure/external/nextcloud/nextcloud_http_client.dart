import 'dart:convert';
import 'dart:io';

import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class NextcloudHttpClient {
  const NextcloudHttpClient();

  Dio create({
    required NextcloudDestinationConfig config,
    required String password,
  }) {
    // Nota: Tanto appPassword quanto userPassword usam Basic Auth no Nextcloud WebDAV.
    // O campo authMode é mantido para documentação e possível validação futura.
    // appPassword: Senha de aplicativo gerada no Nextcloud (recomendado para segurança)
    // userPassword: Senha do usuário (menos seguro, mas suportado)
    final base64Auth = base64Encode(
      utf8.encode('${config.username}:$password'),
    );

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
        headers: {'Authorization': 'Basic $base64Auth'},
      ),
    );

    if (config.allowInvalidCertificates) {
      final adapter = dio.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.badCertificateCallback = (
            X509Certificate cert,
            String host,
            int port,
          ) => true;
          return client;
        };
      }
    }

    return dio;
  }
}

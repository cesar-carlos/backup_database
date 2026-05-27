import 'dart:io';

import 'package:backup_database/application/services/auto_update_service.dart'
    show AppcastRelease;
import 'package:intl/intl.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:xml/xml.dart';

/// Parser do XML do **Sparkle Appcast** usado pelo `AutoUpdateService`.
///
/// Extraído do `auto_update_service.dart` (que tinha ~2138 linhas
/// misturando modelos, parser XML, decisão de release, lock global,
/// telemetria e pipeline de download) para reduzir o tamanho do
/// orquestrador e isolar a parte de parsing — que é uma função pura,
/// testável sem nenhum side-effect.
///
/// O método estático original `AutoUpdateService.parseAppcast` foi
/// mantido como façade `@visibleForTesting` que delega para
/// [AppcastParser.parse], preservando os testes existentes.
abstract final class AppcastParser {
  static const String _sparkleNamespace =
      'http://www.andymatuschak.org/xml-namespaces/sparkle';

  /// Parseia `xmlContent` e retorna as releases válidas para Windows,
  /// deduplicadas por versão (mantendo a de `pubDate` mais recente) e
  /// ordenadas em ordem decrescente de versão (mais novas primeiro).
  ///
  /// Releases sem `sha256`, sem `length` válido, ou sem versão
  /// parseável são silenciosamente ignoradas — refletem entradas
  /// inválidas no feed do publisher, não merecem disparar erro.
  static List<AppcastRelease> parse(String xmlContent) {
    final document = XmlDocument.parse(xmlContent);
    final items = document.findAllElements('item');
    final byVersion = <String, AppcastRelease>{};

    for (final item in items) {
      final release = _parseItem(item);
      if (release == null) continue;

      final key = release.version.toString();
      final existing = byVersion[key];
      if (existing == null ||
          release.publishedAt.isAfter(existing.publishedAt)) {
        byVersion[key] = release;
      }
    }

    final releases = byVersion.values.toList()
      ..sort((a, b) {
        final versionComparison = b.version.compareTo(a.version);
        if (versionComparison != 0) {
          return versionComparison;
        }
        return b.publishedAt.compareTo(a.publishedAt);
      });
    return releases;
  }

  static AppcastRelease? _parseItem(XmlElement item) {
    final enclosure = item.getElement('enclosure');
    if (enclosure == null) return null;

    final os = _attr(enclosure, 'os');
    if ((os ?? '').toLowerCase() != 'windows') return null;

    final versionRaw = _attr(enclosure, 'version');
    final url = enclosure.getAttribute('url');
    final lengthRaw = enclosure.getAttribute('length');
    final sha256 =
        enclosure.getAttribute('sha256') ?? _attr(enclosure, 'sha256');
    if (versionRaw == null ||
        url == null ||
        lengthRaw == null ||
        sha256 == null ||
        sha256.trim().isEmpty) {
      return null;
    }

    final version = tryParseVersion(versionRaw);
    final length = int.tryParse(lengthRaw);
    if (version == null || length == null || length <= 0) return null;

    final title =
        item.getElement('title')?.innerText.trim() ?? 'Version $version';
    final description = item.getElement('description')?.innerText.trim() ?? '';
    final publishedAt =
        tryParsePubDate(item.getElement('pubDate')?.innerText) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    final minSupported = tryParseVersion(
      _attr(enclosure, 'minSupportedAppVersion'),
    );

    int? rolloutPercentage;
    final rolloutRaw = _attr(enclosure, 'rolloutPercentage');
    if (rolloutRaw != null) {
      final parsed = int.tryParse(rolloutRaw);
      if (parsed != null) {
        rolloutPercentage = parsed.clamp(0, 100);
      }
    }

    return AppcastRelease(
      version: version,
      downloadUrl: url,
      fileSizeBytes: length,
      sha256: sha256.toLowerCase(),
      publishedAt: publishedAt,
      title: title,
      description: description,
      minSupportedAppVersion: minSupported,
      rolloutPercentage: rolloutPercentage,
    );
  }

  /// Atributo do `enclosure` que pode aparecer com namespace `sparkle:`
  /// (mais comum em feeds modernos do Sparkle) ou com prefixo plain
  /// `sparkle:` (feeds gerados manualmente). Aceita as duas formas.
  static String? _attr(XmlElement element, String name) {
    return element.getAttribute(name, namespace: _sparkleNamespace) ??
        element.getAttribute('sparkle:$name');
  }

  /// Parser tolerante de `Version` (semver). Aceita prefixo `v`
  /// opcional (`v3.0.1` ou `3.0.1`). Retorna `null` em entrada vazia
  /// ou formato inválido.
  static Version? tryParseVersion(String? raw) {
    final normalized = raw?.trim();
    if (normalized == null || normalized.isEmpty) return null;

    final withoutPrefix = normalized.startsWith('v')
        ? normalized.substring(1)
        : normalized;
    try {
      return Version.parse(withoutPrefix);
    } on FormatException {
      return null;
    }
  }

  /// Parser tolerante de RFC 1123 / RFC 822 (formatos comuns em
  /// `<pubDate>`). Tenta primeiro `HttpDate.parse` (mais rápido) e
  /// cai num parse via `intl` quando falha.
  static DateTime? tryParsePubDate(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;

    try {
      return HttpDate.parse(value).toUtc();
    } on Object {
      try {
        return DateFormat(
          'EEE, dd MMM yyyy HH:mm:ss Z',
          'en_US',
        ).parseUtc(value);
      } on Object {
        return null;
      }
    }
  }
}

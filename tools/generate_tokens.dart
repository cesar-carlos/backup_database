import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final bool checkOnly = args.contains('--check');
  final Directory root = Directory.current;
  final String outPath =
      'lib/core/theme/tokens/generated/w3c_token_snapshot.g.dart';
  final StringBuffer sink = StringBuffer();
  sink.writeln(
    '// GENERATED FILE — run from repo root: '
    'dart run tools/generate_tokens.dart',
  );
  sink.writeln(
    '// ignore_for_file: public_member_api_docs, prefer_int_literals',
  );
  sink.writeln();
  sink.writeln("import 'package:flutter/material.dart';");
  sink.writeln();
  sink.writeln(_emitSpacing(root));
  sink.writeln(_emitRadius(root));
  sink.writeln(_emitMotion(root));
  sink.writeln(_emitPalette(root));
  final String nextRaw = sink.toString();
  final String next = _dartFormatSource(root, nextRaw);
  final File out = File('${root.path}/$outPath');
  if (checkOnly) {
    if (!out.existsSync()) {
      stderr.writeln('Missing $outPath (run generator without --check).');
      exitCode = 1;
      return;
    }
    final String existingRaw = out.readAsStringSync();
    final String existing = _dartFormatSource(root, existingRaw);
    if (existing != next) {
      stderr.writeln(
        '$outPath is out of date. Run: dart run tools/generate_tokens.dart',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln('OK: $outPath matches design-tokens/*.tokens.json');
    return;
  }
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(next);
  stdout.writeln('Wrote ${out.path}');
}

String _dartFormatSource(Directory root, String source) {
  final Directory dartTool = Directory('${root.path}/.dart_tool');
  dartTool.createSync(recursive: true);
  final File tmp = File('${dartTool.path}/w3c_token_snapshot_format.tmp.dart');
  tmp.writeAsStringSync(source);
  try {
    final ProcessResult r = Process.runSync(
      Platform.resolvedExecutable,
      <String>['format', tmp.path],
      workingDirectory: root.path,
    );
    if (r.exitCode != 0) {
      stderr.writeln(r.stderr);
      stderr.writeln(r.stdout);
      throw StateError('dart format failed with exit ${r.exitCode}');
    }
    return tmp.readAsStringSync();
  } finally {
    if (tmp.existsSync()) {
      tmp.deleteSync();
    }
  }
}

String _emitSpacing(Directory root) {
  final Map<String, dynamic> json = _readJson(
    root,
    'design-tokens/spacing.tokens.json',
  );
  final Map<String, dynamic> group = _singleGroup(json, 'spacing');
  final List<String> lines = <String>[];
  for (final String name in _sortedKeys(group)) {
    final double px = _parseDimension(_tokenLeaf(group[name]!, name));
    lines.add('  static const double $name = ${_formatDouble(px)};');
  }
  return 'abstract final class W3cTokenSpacing {\n${lines.join('\n')}\n}\n';
}

String _emitRadius(Directory root) {
  final Map<String, dynamic> json = _readJson(
    root,
    'design-tokens/radius.tokens.json',
  );
  final Map<String, dynamic> group = _singleGroup(json, 'radius');
  final List<String> lines = <String>[];
  for (final String name in _sortedKeys(group)) {
    final double px = _parseDimension(_tokenLeaf(group[name]!, name));
    lines.add('  static const double $name = ${_formatDouble(px)};');
  }
  return 'abstract final class W3cTokenRadius {\n${lines.join('\n')}\n}\n';
}

String _emitMotion(Directory root) {
  final Map<String, dynamic> json = _readJson(
    root,
    'design-tokens/motion.tokens.json',
  );
  final Map<String, dynamic> group = _singleGroup(json, 'duration');
  final List<String> lines = <String>[];
  for (final String name in _sortedKeys(group)) {
    final int ms = _parseDurationMs(_tokenLeaf(group[name]!, name));
    lines.add(
      '  static const Duration $name = Duration(milliseconds: $ms);',
    );
  }
  return 'abstract final class W3cTokenMotion {\n${lines.join('\n')}\n}\n';
}

String _emitPalette(Directory root) {
  final Map<String, dynamic> json = _readJson(
    root,
    'design-tokens/colors.tokens.json',
  );
  final Map<String, dynamic> group = _singleGroup(json, 'palette');
  final List<String> lines = <String>[];
  for (final String name in _sortedKeys(group)) {
    final int argb = _parseColorArgb(_tokenLeaf(group[name]!, name));
    final String hex = argb.toRadixString(16).padLeft(8, '0').toUpperCase();
    lines.add('  static const Color $name = Color(0x$hex);');
  }
  return 'abstract final class W3cTokenPalette {\n${lines.join('\n')}\n}\n';
}

Map<String, dynamic> _readJson(Directory root, String relativePath) {
  final File f = File('${root.path}/$relativePath');
  final Object? decoded = jsonDecode(f.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected object at root: $relativePath');
  }
  return decoded;
}

Map<String, dynamic> _singleGroup(Map<String, dynamic> json, String expected) {
  if (json.length != 1 || json[expected] is! Map<String, dynamic>) {
    throw FormatException(
      'Expected a single top-level group "$expected" in JSON',
    );
  }
  return json[expected]! as Map<String, dynamic>;
}

List<String> _sortedKeys(Map<String, dynamic> map) {
  final List<String> keys = map.keys.toList()..sort();
  return keys;
}

Map<String, String> _tokenLeaf(Object? node, String path) {
  if (node is! Map<String, dynamic>) {
    throw FormatException('Expected object at $path');
  }
  final String? type = node[r'$type'] as String?;
  final String? value = node[r'$value'] as String?;
  if (type == null || value == null) {
    throw FormatException('Missing \$type or \$value at $path');
  }
  return <String, String>{'type': type, 'value': value};
}

double _parseDimension(Map<String, String> leaf) {
  if (leaf['type'] != 'dimension') {
    throw FormatException('Expected dimension, got ${leaf['type']}');
  }
  final String raw = leaf['value']!.trim();
  if (!raw.endsWith('px')) {
    throw FormatException('Expected dimension in px, got $raw');
  }
  return double.parse(raw.substring(0, raw.length - 2));
}

int _parseDurationMs(Map<String, String> leaf) {
  if (leaf['type'] != 'duration') {
    throw FormatException('Expected duration, got ${leaf['type']}');
  }
  final String raw = leaf['value']!.trim();
  if (!raw.endsWith('ms')) {
    throw FormatException('Expected duration in ms, got $raw');
  }
  return int.parse(raw.substring(0, raw.length - 2));
}

int _parseColorArgb(Map<String, String> leaf) {
  if (leaf['type'] != 'color') {
    throw FormatException('Expected color, got ${leaf['type']}');
  }
  String raw = leaf['value']!.trim();
  if (raw.startsWith('#')) {
    raw = raw.substring(1);
  }
  if (raw.length == 6) {
    return int.parse('FF$raw', radix: 16);
  }
  if (raw.length == 8) {
    return int.parse(raw, radix: 16);
  }
  throw FormatException('Expected #RRGGBB or #AARRGGBB, got #${leaf['value']}');
}

String _formatDouble(double d) {
  if (d == d.roundToDouble()) {
    return d.toInt().toString();
  }
  return d.toString();
}

/// Minimal parser for `installer/setup.iss` static contracts.
///
/// Inno Setup scripts are a mix of INI-like sections (`[Tasks]`,
/// `[Icons]`, `[Files]`) and Pascal procedures in `[Code]`. Tests in
/// this repo only need to assert presence and shape of a handful of
/// entries — not full evaluation. This helper trades full fidelity for
/// resilience against trivial whitespace / ordering changes in the
/// underlying `.iss` file.
///
/// `SetupIssParser.fromFile(...)` follows Inno's `#include "..."`
/// preprocessor directive recursively so tests can run against a
/// modularized `setup.iss` (e.g. `#include "code/icons.iss"`) without
/// needing to know the physical layout.
///
/// Scope: query helpers only. Anything more complex (full AST,
/// evaluator) belongs in a separate library, not here.
library;

import 'dart:io';

class SetupIssParser {
  SetupIssParser(this._source);

  /// Loads a `.iss` file and expands `#include "<path>"` directives
  /// recursively, resolving each path relative to the file that
  /// declares it. Mirrors Inno Setup's compile-time behaviour closely
  /// enough for static contract tests.
  factory SetupIssParser.fromFile(File file) {
    return SetupIssParser(_expandIncludes(file.readAsStringSync(), file.parent));
  }

  static String _expandIncludes(String source, Directory baseDir) {
    return source.replaceAllMapped(
      RegExp(r'^#include\s+"([^"]+)"\s*$', multiLine: true),
      (match) {
        final relative = match.group(1)!;
        final included = File('${baseDir.path}${Platform.pathSeparator}$relative');
        if (!included.existsSync()) return match.group(0)!;
        return _expandIncludes(
          included.readAsStringSync(),
          included.parent,
        );
      },
    );
  }

  final String _source;

  /// Returns the body of a `[Section]` block, without the section
  /// header line. Empty string if the section is missing. Trailing
  /// whitespace is preserved so callers can do `contains` checks.
  String section(String name) {
    final pattern = RegExp(
      r'^\[' + RegExp.escape(name) + r'\]\s*\r?\n(.*?)(?=^\[|\Z)',
      multiLine: true,
      dotAll: true,
    );
    final match = pattern.firstMatch(_source);
    if (match == null) return '';
    return match.group(1) ?? '';
  }

  /// Returns the body of a Pascal procedure or function inside `[Code]`.
  ///
  /// Bounds the routine using the **next top-level `procedure`/`function`
  /// declaration** as the terminator (or end-of-file). This avoids the
  /// `begin`/`end;` depth counting trap caused by `case ... end;` blocks
  /// in Inno Pascal (no matching `begin`). Inno Setup does not nest
  /// routines, so a top-level routine declaration is always at column 0
  /// of a line — that's a reliable cut.
  ///
  /// Returns null when the routine is not found.
  ///
  /// Skips matches that are forward declarations (`...; forward;`).
  String? routineBody(String name) {
    final header = RegExp(
      r'(?:^|\n)(?:function|procedure)\s+' +
          RegExp.escape(name) +
          r'\s*\([^)]*\)(?:\s*:\s*\w+)?\s*;(?!\s*forward\s*;)',
      multiLine: true,
    );
    for (final headerMatch in header.allMatches(_source)) {
      final afterHeader = _source.substring(headerMatch.end);
      // Acha o proximo cabecalho top-level (em coluna 0 da linha). Inno
      // Setup nao aninha rotinas, entao esse e o final natural da rotina
      // atual. Se nada vier depois, vai ate o EOF.
      final nextHeader = RegExp(
        r'(?:\n)(?:function|procedure)\s+\w+\s*\(',
      ).firstMatch(afterHeader);
      final end = nextHeader?.start ?? afterHeader.length;
      return afterHeader.substring(0, end);
    }
    return null;
  }

  /// True when the routine exists and its body contains [needle].
  bool routineContains(String name, String needle) {
    final body = routineBody(name);
    return body != null && body.contains(needle);
  }

  /// True when the routine is declared as a forward declaration in
  /// the `[Code]` prelude (`procedure Foo(); forward;`).
  bool hasForwardDeclaration(String name) {
    final pattern = RegExp(
      r'^\s*(?:procedure|function)\s+' +
          RegExp.escape(name) +
          r'\s*\([^)]*\)(?:\s*:\s*\w+)?\s*;\s*forward\s*;',
      multiLine: true,
    );
    return pattern.hasMatch(_source);
  }

  /// True when [name] appears as a `Name:` entry in `[Tasks]`. The
  /// optional [hasFlag] verifies that a given `Flags:` value appears on
  /// the same line (e.g. `checked`).
  bool hasTask(String name, {String? hasFlag}) {
    final tasks = section('Tasks');
    final pattern = RegExp(
      r'^Name:\s*"' + RegExp.escape(name) + r'"[^\r\n]*$',
      multiLine: true,
    );
    final match = pattern.firstMatch(tasks);
    if (match == null) return false;
    if (hasFlag == null) return true;
    final line = match.group(0)!;
    return RegExp(r'Flags:\s*[^;]*\b' + RegExp.escape(hasFlag) + r'\b')
        .hasMatch(line);
  }

  /// Returns the first `[Icons]` entry whose `Name:` matches [name],
  /// or `null` when no match exists.
  String? iconEntry(String name) {
    final icons = section('Icons');
    final pattern = RegExp(
      r'^Name:\s*"' + RegExp.escape(name) + r'"[^\r\n]*$',
      multiLine: true,
    );
    return pattern.firstMatch(icons)?.group(0);
  }

  /// Returns true when the raw source contains [needle]. Convenience
  /// helper so callers don't need to pass `_source` around.
  bool contains(String needle) => _source.contains(needle);
}

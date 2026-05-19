import 'dart:io';

const String _designSystemRoot = 'lib/presentation/widgets';

/// WCAG 2.1 AA / desktop guideline for minimum interactive target (logical px).
const double _minInteractiveTarget = 44;

final List<_Rule> _rules = <_Rule>[
  _Rule(
    id: 'prefer_app_spacing',
    pattern: RegExp(
      r'SizedBox\s*\(\s*(?:height|width)\s*:\s*(?!AppSpacing\.)\d',
    ),
    message: 'Use AppSpacing tokens instead of literal SizedBox dimensions.',
  ),
  _Rule(
    id: 'prefer_app_radius',
    pattern: RegExp(r'BorderRadius\.circular\s*\(\s*\d'),
    message: 'Use AppRadius.circular* instead of BorderRadius.circular(N).',
  ),
  _Rule(
    id: 'prefer_app_duration',
    pattern: RegExp(r'Duration\s*\(\s*milliseconds\s*:\s*\d'),
    message: 'Use AppDuration.* instead of inline Duration(milliseconds: N).',
  ),
  _Rule(
    id: 'prefer_app_palette',
    pattern: RegExp(r'\bAppColors\.'),
    message: 'Use AppPalette or context.colors instead of legacy AppColors.',
  ),
  _Rule(
    id: 'prefer_app_breakpoints',
    pattern: RegExp(
      r'MediaQuery\.of\s*\(\s*context\s*\)\.size\.width\s*>\s*\d',
    ),
    message:
        'Use context.isCompactWindow / AppBreakpoints instead of width literals.',
  ),
  _Rule(
    id: 'atomic_doc_comment',
    pattern: RegExp(r'\*\*(Atom|Molecule|Organism)\*\*'),
    message:
        'Document atomic level with /// **Atom|Molecule|Organism** in the file.',
    matchRequired: true,
  ),
];

final RegExp _interactiveFileHint = RegExp(r'\bonPressed\b|\bonTap\b');

final RegExp _minDimensionPattern = RegExp(
  r'(?:minHeight|minWidth)\s*:\s*(?!AppTargetSize\.)([0-9]+(?:\.[0-9]+)?)',
);

final RegExp _minimumSizePattern = RegExp(
  r'minimumSize\s*:\s*(?:const\s+)?Size(?:\.square)?\s*\(\s*([0-9]+(?:\.[0-9]+)?)'
  r'(?:\s*,\s*([0-9]+(?:\.[0-9]+)?))?',
);

void main(List<String> args) {
  final bool failOnFindings = args.contains('--fail-on-findings');
  final bool enforceTargetSize = args.contains('--enforce-target-size');
  final List<String> roots = <String>[
    '$_designSystemRoot/atoms',
    '$_designSystemRoot/molecules',
    '$_designSystemRoot/organisms',
  ];

  final List<_Finding> findings = <_Finding>[];
  for (final String root in roots) {
    final Directory dir = Directory(root);
    if (!dir.existsSync()) {
      stderr.writeln('Missing directory: $root');
      exitCode = 1;
      return;
    }
    for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (entity.uri.pathSegments.last.endsWith('.dart') &&
          entity.uri.pathSegments.last.contains('.')) {
        final String name = entity.uri.pathSegments.last;
        if (name == 'atoms.dart' ||
            name == 'molecules.dart' ||
            name == 'organisms.dart') {
          continue;
        }
        findings.addAll(
          _scanFile(entity, enforceTargetSize: enforceTargetSize),
        );
      }
    }
  }

  if (findings.isEmpty) {
    stdout.writeln(
      'OK: design system guard — no findings in atoms/molecules/organisms.',
    );
    return;
  }

  for (final _Finding finding in findings) {
    stderr.writeln(
      '${finding.path}:${finding.line}: [${finding.ruleId}] ${finding.message}',
    );
  }
  stderr.writeln('${findings.length} design system guard finding(s).');
  if (failOnFindings) {
    exitCode = 1;
  }
}

List<_Finding> _scanFile(
  File file, {
  required bool enforceTargetSize,
}) {
  final String relative = file.path.replaceAll(r'\', '/').split('lib/').last;
  final String path = 'lib/$relative';
  final List<String> lines = file.readAsLinesSync();
  final String content = lines.join('\n');
  final List<_Finding> out = <_Finding>[];

  for (final _Rule rule in _rules) {
    if (rule.matchRequired) {
      if (!rule.pattern.hasMatch(content)) {
        out.add(
          _Finding(
            path: path,
            line: 1,
            ruleId: rule.id,
            message: rule.message,
          ),
        );
      }
      continue;
    }
    for (var i = 0; i < lines.length; i++) {
      final String line = lines[i];
      if (line.trim().startsWith('//')) {
        continue;
      }
      if (rule.pattern.hasMatch(line)) {
        out.add(
          _Finding(
            path: path,
            line: i + 1,
            ruleId: rule.id,
            message: rule.message,
          ),
        );
      }
    }
  }

  if (enforceTargetSize) {
    out.addAll(_scanTargetSize(path, lines, content));
  }

  return out;
}

List<_Finding> _scanTargetSize(
  String path,
  List<String> lines,
  String content,
) {
  if (!_interactiveFileHint.hasMatch(content)) {
    return const <_Finding>[];
  }

  final List<_Finding> out = <_Finding>[];
  for (var i = 0; i < lines.length; i++) {
    final String line = lines[i];
    if (line.trim().startsWith('//')) {
      continue;
    }
    if (line.contains('guard-ignore-enforce-target-size')) {
      continue;
    }
    if (_isDecorativeDimensionLine(line)) {
      continue;
    }

    final RegExpMatch? dim = _minDimensionPattern.firstMatch(line);
    if (dim != null) {
      final double value = double.parse(dim.group(1)!);
      if (value < _minInteractiveTarget) {
        out.add(
          _Finding(
            path: path,
            line: i + 1,
            ruleId: 'enforce_target_size',
            message:
                'Interactive widget min dimension $value is below $_minInteractiveTarget; '
                'use AppTargetSize.minimum or AppTargetSize.comfortable.',
          ),
        );
      }
      continue;
    }

    final RegExpMatch? size = _minimumSizePattern.firstMatch(line);
    if (size != null) {
      final double w = double.parse(size.group(1)!);
      final double h = size.group(2) != null ? double.parse(size.group(2)!) : w;
      if (w < _minInteractiveTarget || h < _minInteractiveTarget) {
        out.add(
          _Finding(
            path: path,
            line: i + 1,
            ruleId: 'enforce_target_size',
            message:
                'minimumSize (${w}x$h) is below $_minInteractiveTarget; '
                'use AppTargetSize.minimum or AppTargetSize.comfortable.',
          ),
        );
      }
    }
  }
  return out;
}

bool _isDecorativeDimensionLine(String line) {
  const List<String> skipHints = <String>[
    'ProgressRing',
    'ProgressBar',
    'CircularProgress',
    'strokeWidth',
    'Skeleton',
    'shimmer',
  ];
  for (final String hint in skipHints) {
    if (line.contains(hint)) {
      return true;
    }
  }
  return false;
}

class _Rule {
  const _Rule({
    required this.id,
    required this.pattern,
    required this.message,
    this.matchRequired = false,
  });

  final String id;
  final RegExp pattern;
  final String message;
  final bool matchRequired;
}

class _Finding {
  const _Finding({
    required this.path,
    required this.line,
    required this.ruleId,
    required this.message,
  });

  final String path;
  final int line;
  final String ruleId;
  final String message;
}

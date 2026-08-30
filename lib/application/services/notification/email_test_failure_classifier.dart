import 'package:backup_database/core/errors/failure.dart';

class EmailTestFailureClassifier {
  const EmailTestFailureClassifier({
    required this.category,
    required this.keywords,
  });

  final String category;
  final List<String> keywords;

  static String? classify(Object? failure) {
    if (failure == null) {
      return null;
    }

    final text = failureUserMessage(failure).toLowerCase();
    for (final entry in _classifiers) {
      if (entry.keywords.any(text.contains)) {
        return entry.category;
      }
    }
    return 'unknown';
  }

  static const List<EmailTestFailureClassifier> _classifiers = [
    EmailTestFailureClassifier(
      category: 'authentication',
      keywords: ['autenticacao', 'authentication', '535'],
    ),
    EmailTestFailureClassifier(
      category: 'connectivity',
      keywords: ['timeout', 'socket', 'conectar'],
    ),
    EmailTestFailureClassifier(
      category: 'smtp_rejection',
      keywords: ['rejeitou', 'rejected'],
    ),
    EmailTestFailureClassifier(
      category: 'validation',
      keywords: ['invalido', 'validation', 'destino'],
    ),
  ];
}

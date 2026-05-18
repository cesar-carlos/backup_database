/// Campos opcionais de correlacao em eventos de backup (F2.17).
Map<String, dynamic> backupEventCorrelationFields({
  String? eventId,
  int? sequence,
}) {
  return <String, dynamic>{
    ...?(eventId != null && eventId.isNotEmpty ? {'eventId': eventId} : null),
    ...?(sequence != null ? {'sequence': sequence} : null),
  };
}

String? getEventIdFromBackupPayload(Map<String, dynamic> payload) {
  final raw = payload['eventId'];
  if (raw is String && raw.isNotEmpty) return raw;
  return null;
}

int? getSequenceFromBackupPayload(Map<String, dynamic> payload) {
  final raw = payload['sequence'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

enum SybaseToolStatus {
  ok,
  warning,
  missing,
}

class SybaseToolsStatus {
  const SybaseToolsStatus({
    required this.dbisql,
    required this.dbbackup,
    required this.dbvalid,
    required this.dbverify,
  });

  final SybaseToolStatus dbisql;
  final SybaseToolStatus dbbackup;
  final SybaseToolStatus dbvalid;
  final SybaseToolStatus dbverify;

  bool get canRunBackup =>
      dbisql == SybaseToolStatus.ok || dbbackup == SybaseToolStatus.ok;

  bool get hasAllTools =>
      dbisql == SybaseToolStatus.ok &&
      dbbackup == SybaseToolStatus.ok &&
      dbvalid == SybaseToolStatus.ok;
}

class MachineScopeR1LegacyPathsHint {
  const MachineScopeR1LegacyPathsHint({
    required this.otherProfilesLegacySqlitePaths,
  });

  final List<String> otherProfilesLegacySqlitePaths;

  bool get hasDetectedOtherProfiles =>
      otherProfilesLegacySqlitePaths.isNotEmpty;

  String get dismissalSignature {
    if (otherProfilesLegacySqlitePaths.isEmpty) {
      return '';
    }
    final sorted = List<String>.from(otherProfilesLegacySqlitePaths)..sort();
    return sorted.join('\n');
  }
}

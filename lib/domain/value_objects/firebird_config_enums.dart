enum FirebirdServerVersionHint {
  auto,
  v25,
  v30,
  v40,
  ;

  static FirebirdServerVersionHint parse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'v25':
      case '2.5':
        return FirebirdServerVersionHint.v25;
      case 'v30':
      case '3.0':
        return FirebirdServerVersionHint.v30;
      case 'v40':
      case '4.0':
        return FirebirdServerVersionHint.v40;
      case 'auto':
      default:
        return FirebirdServerVersionHint.auto;
    }
  }

  String get wireValue => name;
}

enum FirebirdServiceManagerMode {
  auto,
  always,
  never,
  ;

  static FirebirdServiceManagerMode parse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'always':
        return FirebirdServiceManagerMode.always;
      case 'never':
        return FirebirdServiceManagerMode.never;
      case 'auto':
      default:
        return FirebirdServiceManagerMode.auto;
    }
  }

  String get wireValue => name;
}

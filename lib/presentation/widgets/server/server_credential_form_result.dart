class ServerCredentialFormResult {
  const ServerCredentialFormResult({
    required this.serverId,
    required this.name,
    required this.isActive,
    this.plainPassword,
    this.description,
  });

  final String serverId;
  final String name;
  final bool isActive;
  final String? plainPassword;
  final String? description;
}

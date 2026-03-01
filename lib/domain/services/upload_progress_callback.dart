/// Callback para reportar progresso de upload
/// [progress] valor de 0.0 a 1.0 representando o progresso atual
/// [stepOverride] quando fornecido, substitui o step padrão (ex: "Retomando de 63%")
typedef UploadProgressCallback = void Function(
  double progress, [
  String? stepOverride,
]);

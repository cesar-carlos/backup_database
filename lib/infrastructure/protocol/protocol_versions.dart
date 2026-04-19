/// Versoes do protocolo socket.
///
/// Implementacao parcial de ADR-003 (`docs/adr/003-versionamento-protocolo.md`).
/// Define dois niveis de versionamento:
///
/// 1. **Wire version** ([kCurrentWireVersion]): formato binario do
///    `MessageHeader`. Bumpado **somente** quando o layout do header,
///    do envelope basico ou o checksum mudar. Mudancas em payloads
///    individuais NAO bumpam wire version.
///
/// 2. **Protocol version logica** ([kCurrentProtocolVersion]): conjunto
///    de features suportado pelo servidor. Bumpado a cada PR principal
///    (ver tabela em ADR-003). Cliente le via `getServerCapabilities`
///    no handshake e usa como gate de feature.
///
/// Centralizar essas constantes evita ter o numero magico `0x01`
/// espalhado em `binary_protocol.dart`, `client_handler.dart` e outros
/// pontos de validacao. Quando bump for necessario, basta atualizar aqui
/// e adicionar ADR superseder.
library;

/// Versao atual do **wire format** do `MessageHeader`.
///
/// Formato `v1` (atual):
/// - 16 bytes de header
/// - magic `0xFA000000`
/// - version `uint8` nesta posicao
/// - length `uint32`
/// - type `uint8`
/// - requestId `uint32`
/// - flags `uint8 x 2`
/// - payload (`length` bytes)
/// - checksum CRC32 `uint32`
///
/// Bump requer ADR especifico que detalhe migracao.
const int kCurrentWireVersion = 0x01;

/// Lista de wire versions que o servidor atual aceita ler.
///
/// Hoje so `[1]`. No futuro, durante janela de transicao para `v2`,
/// podera ser `[1, 2]` para o servidor aceitar peers em ambas as
/// versoes ate o cliente ser atualizado em campo.
const Set<int> kSupportedWireVersions = {kCurrentWireVersion};

/// Versao logica do protocolo refletindo o conjunto de features
/// suportado. Bumpada a cada PR principal:
///
/// - `1`: estado em producao antes de PR-1.
/// - `2`: PR-1 mergeado (envelope REST-like, capabilities, health,
///   session, guard pre-auth explicito).
/// - `3`: PR-2 mergeado (CRUD DB config, executeBackup nao-bloqueante,
///   runId formal no contrato, getExecutionStatus).
/// - `4`: PR-3 mergeado (mutex/fila, eventos de fila, staging por
///   runId).
/// - `5`: PR-4 mergeado (artefato com TTL, cleanupStaging remoto,
///   lease de lock).
///
/// Cliente recebe via `getServerCapabilities.protocolVersion` e usa
/// como gate de feature. Servidor ainda nao implementou
/// `getServerCapabilities`; quando implementar, deve retornar este
/// valor.
const int kCurrentProtocolVersion = 1;

/// Helper que confirma se uma wire version recebida e suportada.
/// Centraliza a regra para evitar duplicacao em multiplos pontos do
/// codigo (parser, handlers, testes).
bool isWireVersionSupported(int version) =>
    kSupportedWireVersions.contains(version);

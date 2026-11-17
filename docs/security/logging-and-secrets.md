# Protecao de credenciais nos logs

Este documento descreve o codigo do checkout. A protecao so chega a uma
instalacao depois de compilar, publicar e instalar a versao correspondente.
Ela nao revoga credenciais expostas anteriormente.

## O que e ocultado

| Caminho | Protecao implementada |
| --- | --- |
| FTP detalhado | Omite os comandos `PASS`, `ACCT` e `ADAT`; mascara nas mensagens seguintes os valores vistos nesses comandos |
| Mensagens socket | Oculta campos sensiveis em mapas e listas, inclusive dentro de `config`, sem modificar o pedido enviado |
| Console do aplicativo | Filtra mensagem, contexto por chamada, excecao e stack trace em `LoggerService` |
| Arquivos do aplicativo | `FileLoggerService` filtra o texto antes de gravar, inclusive em chamadas diretas |
| Logs de backup no banco | O repositorio filtra mensagem e detalhes ao gravar e ao ler registros existentes |
| Exportacao TXT, JSON e CSV | Filtra mensagem e detalhes antes da exportacao |

O filtro textual reconhece campos comuns de senha, tokens, segredos, chaves,
autenticacao Basic/Bearer, credenciais em URLs e blocos PEM de chave privada.
Codigos de erro, etapas e identificadores de execucao continuam disponiveis
para diagnostico. A implementacao central fica em
[`failure_diagnostics.dart`](../../lib/core/errors/failure_diagnostics.dart).

## Limites e registros antigos

A ocultacao usa nomes de campos e padroes conhecidos. Nao garante detectar
todo segredo em texto livre, conteudo codificado ou formatos desconhecidos.
Evite registrar corpos completos de autenticacao ou configuracoes, mesmo
quando o caminho de log possui filtro.

Arquivos antigos, dados brutos do banco, backups, logs de CI e copias exportadas
anteriormente nao sao apagados ou reescritos pela correcao. A leitura filtrada
do banco protege a interface, mas uma copia direta do banco ainda pode conter
os valores originais. Logs de ferramentas externas tambem exigem revisao.

Antes de compartilhar um diagnostico, confira usuarios, e-mails, hosts,
caminhos, nomes de bancos e arquivos: esses dados podem ser sensiveis para a
organizacao e nao sao todos removidos automaticamente. Preserve versao,
horario, etapa, codigo de erro e identificadores necessarios a investigacao.
Nao publique `.env`, `signer.env`, banco local ou dumps completos de memoria.

## Protecao do repositorio e dos testes

O teste `bundled_env_secret_leak_test.dart` verifica `.env`, `.env.example`,
`.env.client` e `.env.server`. Ele compara apenas nomes de chaves proibidas;
os valores nao chegam ao matcher nem a mensagem de falha. Uma regressao
provoca uma falha controlada com segredo ficticio e verifica essa garantia.

Esse teste cobre a lista `EnvironmentLoader.forbiddenInBundledAssetKeys`.
Nao e um scanner universal de segredos e nao limpa o historico Git. A regra
do `.gitignore` tambem nao protege arquivos que ja estejam versionados.

## Validacao

Na raiz do repositorio, com as dependencias instaladas:

```powershell
flutter analyze
flutter test test/unit/core/logging test/unit/core/config/bundled_env_secret_leak_test.dart test/unit/core/utils/logger_service_test.dart test/unit/application/services/backup_log_diagnostics_test.dart test/unit/infrastructure/license test/unit/application/services/license_decoder_multi_key_test.dart
```

As regressoes cobrem FTP e eco de senha, campos aninhados, excecoes no console,
gravacao em arquivo/banco, leitura e exportacao de registros antigos, falhas do
teste de seguranca e preparacao protegida do par de chaves. A geracao usa
chaves descartaveis e remove suas pastas temporarias ao terminar.

Para credenciais ja expostas, siga o
[procedimento de troca da chave e das senhas](license-key-rotation.md).

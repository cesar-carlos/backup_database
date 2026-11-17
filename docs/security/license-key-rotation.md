# Troca da chave de licenciamento comprometida

## Estado e alcance

O histórico público expôs uma chave privada que corresponde à chave pública
legada distribuída pelo aplicativo. A remoção do valor na versão atual não
revoga a chave. Forks, clones e instaladores antigos podem conservar cópias.

Esta alteração prepara a geração protegida e os testes de migração. Não gera
uma chave de produção, não modifica configurações instaladas, não reemite
licenças e não ativa a retirada de confiança da chave antiga. Até concluir
o procedimento abaixo e atualizar os clientes, a exposição permanece.

## Preparação pelo responsável pela emissão

1. Use uma estação confiável, com disco protegido, e crie uma pasta privada
   fora do checkout e fora de pastas sincronizadas/publicadas. Execute:

   ```powershell
   dart run scripts/generate_license_keypair.dart ed25519-2026-rotation C:\PrivateSigning
   ```

   O utilitário cria uma subpasta nova, aplica permissões antes de escrever
   e aborta se não conseguir protegê-la. Nunca imprime a chave privada.
   `signer.env` contém o segredo; `public.env` contém somente dados públicos.
   Preserve uma cópia protegida do segredo em seu cofre de credenciais.

2. Instale os campos de `signer.env` somente na estação autorizada a emitir
   licenças. Não distribua esse arquivo com o instalador ou aos clientes.
   Não substitua o `.env` inteiro: preserve configurações não relacionadas.

3. Use um cadastro confiável de clientes para reemitir licenças. Preserve
   dispositivo, validade e funcionalidades autorizadas. Não use apenas uma
   licença assinada com a chave exposta como prova de direito à reemissão.
   Prepare também uma nova CRL assinada pela chave nova: a CRL compartilha
   o conjunto de chaves de verificação das licenças.

## Retirada de confiança e publicação

4. Aplique os campos públicos nos quatro arquivos de distribuição (`.env`,
   `.env.example`, `.env.client`, `.env.server`) e nas configurações externas
   das instalações. Deixe `BACKUP_DATABASE_LICENSE_PUBLIC_KEY` vazio e
   mantenha somente a chave nova no JSON `BACKUP_DATABASE_LICENSE_PUBLIC_KEYS`.
   Exclua a chave comprometida sob qualquer identificador. Trocar apenas
   `ACTIVE_KEY_ID` não retira a confiança da chave antiga.

5. Antes de publicar, teste com configuração externa antiga e nova, interface
   e serviço: a licença legítima nova deve ser aceita; licença e CRL assinadas
   pela chave antiga devem ser recusadas. Confira também renovação, expiração,
   dispositivo diferente e funcionalidades. O loader pode completar campos
   públicos pelo bundle; por isso ambos precisam ser atualizados.

6. Publique o instalador e o appcast em uma janela coordenada com a entrega
   das novas licenças. A retirada da chave antiga invalida as licenças emitidas
   com ela; comunicar e preparar os clientes evita interrupção inesperada.
   Não faça rollback para binários/configurações que voltem a aceitar a chave
   comprometida. Aplicativos antigos continuam vulneráveis até atualizados.

## Outras credenciais e registros

Troque separadamente a senha administrativa e a senha FTP expostas no
histórico. A rotação da assinatura não altera essas credenciais. Examine
acessos e cópias de logs antigos antes de descartá-los conforme a política
de retenção. Os novos filtros protegem gravações e exportações, mas não
apagam segredos já gravados em arquivos, banco, CI, forks ou backups.

Somente após invalidar as credenciais, avalie a limpeza do histórico e das
releases antigas. Reescrever o Git não recolhe cópias de terceiros.

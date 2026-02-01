# Análise: Menu por AppMode e Encoding UTF-8

**Data:** 2026-02-01 17:52
**Status:** 2 Problemas identificados (1 Crítico, 1 OK)

---

## Problema 1: Menu NÃO Filtra por AppMode ❌ CRÍTICO

### Situação Atual

**Arquivo:** `lib/presentation/pages/main_layout.dart`

**Problema:** O menu de navegação mostra **TODOS os 11 itens** independente do modo (Servidor/Cliente/Unificado).

**Impacto:**
- Usuário vê opções que não fazem sentido para o modo selecionado
- Cliente vê opções de Servidor (e vice-versa)
- Experiência de usuário confusa

### Análise dos Itens de Menu

| # | Item | Rota | Cliente | Servidor | Unified |
|---|------|------|---------|---------|---------|
| 1 | Dashboard | `/dashboard` | ✅ | ✅ | ✅ |
| 2 | Bancos de Dados | `/sql-server-config` | ✅ | ✅ | ✅ |
| 3 | Destinos | `/destinations` | ✅ | ✅ | ✅ |
| 4 | Agendamentos | `/schedules` | ✅ | ✅ | ✅ |
| 5 | Notificações | `/notifications` | ✅ | ✅ | ✅ |
| 6 | **Servidor** | `/server-settings` | ❌ | ✅ | ✅ |
| 7 | **Conectar** | `/server-login` | ✅ | ❌ | ✅ |
| 8 | **Agendamentos Remotos** | `/remote-schedules` | ✅ | ❌ | ✅ |
| 9 | **Transferir Backups** | `/transfer-backups` | ✅ | ❌ | ✅ |
| 10 | Logs | `/logs` | ❌ | ✅ | ✅ |
| 11 | Configurações | `/settings` | ✅ | ✅ | ✅ |

**Legenda:**
- ✅ = Deve ser visível
- ❌ = Deve ser ESCONDIDO

### Itens Exclusivos por Modo

**Modo CLIENTE (apenas cliente vê):**
- ✅ Conectar (serverLogin)
- ✅ Agendamentos Remotos (remoteSchedules)
- ✅ Transferir Backups (transferBackups)

**Modo SERVIDOR (apenas servidor vê):**
- ✅ Servidor (serverSettings) - Configurar credenciais, ver clientes conectados
- ✅ Logs (logs) - Logs de conexões

**Modo UNIFIED (ambos os modos):**
- ✅ Todos os 11 itens

### Código Atual (PROBLEMA)

```dart
// main_layout.dart - linha 29-96
final List<NavigationItem> _navigationItems = [
  const NavigationItem(...), // Dashboard
  const NavigationItem(...), // Bancos de Dados
  const NavigationItem(...), // Destinos
  const NavigationItem(...), // Agendamentos
  const NavigationItem(...), // Notificações
  const NavigationItem(...), // Servidor ❌ SEMPRE VISÍVEL
  const NavigationItem(...), // Conectar ❌ SEMPRE VISÍVEL
  const NavigationItem(...), // Agendamentos Remotos ❌ SEMPRE VISÍVEL
  const NavigationItem(...), // Transferir Backups ❌ SEMPRE VISÍVEL
  const NavigationItem(...), // Logs
  const NavigationItem(...), // Configurações
];
```

**Problema:** Lista estática não filtra por `AppMode`

---

## Problema 2: Encoding UTF-8 ✅ CORRETO

### Situação Atual

**Arquivo:** `lib/infrastructure/protocol/binary_protocol.dart`

**Status:** ✅ **UTF-8 ESTÁ SENDO USADO CORRETAMENTE**

### Código Atual (CORRETO)

**Serialização (linha 21):**
```dart
final rawPayload = utf8.encode(jsonEncode(message.payload));
```

**Deserialização (linha 126):**
```dart
final payloadJson = utf8.decode(bytesToDecode);
```

### Por Que UTF-8 é Importante?

**Caracteres Especiais em Português:**
- `ç` (c cedilha) = 0xC3 0xA7 em UTF-8
- `ã` (a til) = 0xC3 0xA3 em UTF-8
- `é` (e agudo) = 0xC3 0xA9 em UTF-8
- `ô` (o circunflexo) = 0xC3 0xB4 em UTF-8

**Exemplo de mensagem:**
```json
{
  "scheduleName": "Backup do São Paulo",
  "destination": "C:\Usuários\João\Backups"
}
```

**SEM UTF-8 (errado):**
- `São Paulo` → `SÃ£o Paulo` (quebrado)
- `João` → `JoÃ£o` (quebrado)

**COM UTF-8 (correto):**
- `São Paulo` → `São Paulo` (correto)
- `João` → `João` (correto)

### Validação

✅ **Encoding está correto**
- `utf8.encode()` usado na serialização
- `utf8.decode()` usado na deserialização
- Suporte completo a caracteres especiais
- Suporte a emojis e Unicode

---

## Solução Proposta

### 1. Adicionar Filtragem por AppMode no Menu

**Arquivo:** `lib/presentation/pages/main_layout.dart`

**Mudanças necessárias:**

```dart
// Importar AppMode
import 'package:backup_database/core/config/app_mode.dart';

// Mudar de lista estática para getter dinâmico
List<NavigationItem> get _navigationItems {
  final mode = currentAppMode;

  final allItems = [
    const NavigationItem(...), // Dashboard
    const NavigationItem(...), // Bancos de Dados
    const NavigationItem(...), // Destinos
    const NavigationItem(...), // Agendamentos
    const NavigationItem(...), // Notificações
    const NavigationItem(...), // Servidor
    const NavigationItem(...), // Conectar
    const NavigationItem(...), // Agendamentos Remotos
    const NavigationItem(...), // Transferir Backups
    const NavigationItem(...), // Logs
    const NavigationItem(...), // Configurações
  ];

  // Filtrar baseado no modo
  switch (mode) {
    case AppMode.client:
      return allItems.where((item) =>
        item.route != RouteNames.serverSettings &&
        item.route != RouteNames.logs
      ).toList();

    case AppMode.server:
      return allItems.where((item) =>
        item.route != RouteNames.serverLogin &&
        item.route != RouteNames.remoteSchedules &&
        item.route != RouteNames.transferBackups
      ).toList();

    case AppMode.unified:
      return allItems;
  }
}
```

### 2. Adicionar Propriedade `mode` em NavigationItem (Opcional)

**Alternativa mais elegante:**

```dart
class NavigationItem {
  const NavigationItem({
    required this.icon,
    required this.label,
    required this.route,
    this.modes = const [AppMode.unified, AppMode.server, AppMode.client],
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;
  final List<AppMode> modes; // NOVO: quais modos veem este item
}
```

**Uso:**
```dart
const NavigationItem(
  icon: FluentIcons.server,
  label: 'Servidor',
  route: RouteNames.serverSettings,
  modes: [AppMode.server, AppMode.unified], // Cliente NÃO vê
),
```

---

## Plano de Implementação

### Opção 1: Filtragem Simples (Recomendado) ⚡

**Vantagens:**
- Rápido de implementar (15-30 min)
- Mudança localizada (main_layout.dart apenas)
- Não quebra código existente

**Desvantagens:**
- Menos elegante que propriedade `modes`

**Estimativa:** 15-30 minutos

### Opção 2: Propriedade `modes` (Mais Elegante) 🎨

**Vantagens:**
- Mais declarativo e legível
- Fácil adicionar novos modos
- Melhor separação de concerns

**Desvantagens:**
- Requer mudar classe `NavigationItem`
- Requer atualizar todos os 11 itens
- Mais tempo de implementação

**Estimativa:** 45-60 minutos

---

## Recomendação

✅ **Implementar Opção 1 (Filtragem Simples)**

**Justificativa:**
- Solução rápida e efetiva
- Funcionalidade crítica (UX afetada)
- Pode refatorar para Opção 2 depois se necessário

**Próximos Passos:**
1. Implementar filtragem por AppMode no MainLayout
2. Testar os 3 modos (client, server, unified)
3. Verificar se itens corretos aparecem em cada modo
4. Commit e push da correção

---

## Status

| Problema | Status | Prioridade |
|----------|--------|------------|
| Menu não filtra por AppMode | ❌ CRÍTICO | ALTA |
| Encoding UTF-8 | ✅ CORRETO | N/A |

---

**Data:** 2026-02-01 17:52
**Status:** Aguardando implementação da correção do menu

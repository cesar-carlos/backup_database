# Service Control Handlers - Notas Técnicas

> **Nota técnica**: Para análise completa da implementação do Windows Service, consulte [analise_implementacao_windows_service.md](analise_implementacao_windows_service.md).

## Status da Implementação

### ✅ Já Implementado (via ServiceShutdownHandler)

O `ServiceShutdownHandler` em `lib/core/service/service_shutdown_handler.dart` já implementa:

1. **SIGINT handler** - Usuário pressiona Ctrl+C
2. **SIGTERM handler** - Windows solicita parada do serviço
3. **Graceful shutdown** - Aguarda backups terminarem antes de encerrar
4. **Callback system** - Permite registrar múltiplos callbacks de shutdown

### 🔄 Tratado pelo NSSM (Automático)

O **NSSM** (Non-Sucking Service Manager) já trata os seguintes eventos do Windows Service Control Manager:

- `SERVICE_CONTROL_SHUTDOWN` - Windows está desligando
- `SERVICE_CONTROL_STOP` - Serviço sendo parado via services.msc
- `SERVICE_CONTROL_PAUSE`/`SERVICE_CONTROL_CONTINUE` - Pause/Resume (não aplicável ao nosso caso)
- `SERVICE_CONTROL_PARAMCHANGE` - Mudança de parâmetros do serviço
- `SERVICE_CONTROL_NETBINDADD`/`REMOVE` - Mudanças de rede
- `SERVICE_CONTROL_HARDWAREPROFILECHANGE` - Mudança de hardware
- `SERVICE_CONTROL_POWEREVENT` - Eventos de energia
- `SERVICE_CONTROL_SESSIONCHANGE` - Mudança de sessão de usuário

**O NSSM intercepta esses eventos e envia SIGTERM para o nosso processo**, que é tratado pelo `ServiceShutdownHandler`.

### ❌ Não Implementado (Por Design)

Os seguintes handlers **não são implementados intencionalmente**:

1. **SERVICE_CONTROL_PAUSE** - Aplicativos de backup não devem ser pausados (podem corromper backups em andamento)
2. **SERVICE_CONTROL_CONTINUE** - Não temos pause, então não precisamos de continue
3. **SERVICE_CONTROL_INTERROGATE** - NSSM já responde ao status do serviço
4. **Custom commands** - Não necessários para backup automático

## Por Que Não Implementar Handlers Nativos do Windows?

### Complexidade vs Benefício

Para implementar handlers nativos do Windows Service Control, precisaríamos:

1. **Criar um wrapper nativo em C++** que chama `RegisterServiceCtrlHandlerEx`
2. **Implementar comunicação IPC** entre o wrapper C++ e o Flutter app
3. **Gerenciar o ciclo de vida do serviço nativo** (muito complexo)
4. **Manter código C++ adicional** (aumento de superfície de bugs)

### Abordagem NSSM (Atual)

**Vantagens:**
- ✅ **Simples** - Usa `eventcreate` e `Process.run`
- ✅ **Robusto** - NSSM é testado e usado por milhares de serviços Windows
- ✅ **Manutenível** - Código Dart puro, sem C++
- ✅ **Suficiente** - SIGTERM cobre 95% dos casos de uso

**Desvantagens:**
- ❌ Sem controle granular sobre cada tipo de evento
- ❌ Dependência de NSSM como executável externo

## Implementação Nativa (Futuro)

Se no futuro for necessário implementar handlers nativos, a arquitetura seria:

```
┌─────────────────────────────────────────┐
│  Windows Service Control Manager        │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│  C++ Service Wrapper (native DLL)       │
│  - RegisterServiceCtrlHandlerEx         │
│  - Accepta todos os eventos             │
│  - Pipe/Shared Memory para Flutter      │
└────────────────┬────────────────────────┘
                 │ IPC (gRPC/Protobuf)
                 ▼
┌─────────────────────────────────────────┐
│  Flutter App (backup_database.exe)      │
│  - Recebe eventos via IPC              │
│  - Trata cada evento                   │
└─────────────────────────────────────────┘
```

**Esforço estimado:** 2-3 semanas de desenvolvimento
**Benefício:** Marginal (apenas 5% de casos edge)

## Conclusão

A implementação atual via **NSSM + ServiceShutdownHandler** é:
- ✅ **Suficiente** para os requisitos de backup automático
- ✅ **Robusta** para produção
- ✅ **Manutenível** pela equipe atual

Implementação nativa de Service Control Handlers **não é recomendada** a menos que haja um requisito explícito do cliente para suportar cenários edge muito específicos (ex: pausar backups sem matar o processo).

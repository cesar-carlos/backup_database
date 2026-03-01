# Guia Rápido - Criar Instalador

## Passos Rápidos

### Método Rápido (Recomendado)

```powershell
# Execute na raiz do projeto - faz tudo automaticamente!
python installer\build_installer.py
```

Este script:
1. ✅ Sincroniza a versão do `pubspec.yaml` com o `setup.iss`
2. ✅ Verifica se o projeto foi compilado
3. ✅ Baixa `vc_redist.x64.exe` automaticamente se ausente
4. ✅ Compila o instalador automaticamente

### Método Manual

#### 1. Compilar o Projeto

```bash
flutter build windows --release
```

#### 2. Sincronizar Versão

```powershell
python installer\update_version.py
```

#### 3. Criar o Instalador

1. Abra o **Inno Setup Compiler**
2. Abra `installer\setup.iss`
3. Compile (Ctrl+F9)
4. O instalador estará em: `installer\dist\BackupDatabase-Setup-{versão}.exe`

### 3. Testar

1. Execute o instalador em uma VM limpa
2. Verifique se tudo funciona
3. Teste a desinstalação

### 4. Distribuir

1. Faça upload para GitHub Releases
2. Atualize o appcast.xml (se usar auto-update)

---

## O que o Instalador Faz

✅ Instala o aplicativo  
✅ Instala Visual C++ Redistributables (se necessário)  
✅ Instala sem verificar dependências (usuário pode usar apenas SQL Server ou apenas Sybase)  
✅ Cria atalhos  
✅ Inclui documentação  
✅ Configura inicialização automática (opcional)  

---

## Documentação Completa

- **Instalador**: `installer\README.md`
- **Guia de Instalação**: `docs\install\installation_guide.md`
- **Requisitos**: `docs\requirements.md`
- **Configuração PATH**: `docs\path_setup.md`

---

**Pronto para criar seu instalador! 🚀**






# Guia Rápido - Criar Instalador

## Passos Rápidos

### 1. Compilar o Projeto

```bash
flutter build windows --release
```

### 2. Criar o Instalador

1. Abra o **Inno Setup Compiler**
2. Abra `installer\setup.iss`
3. Compile (Ctrl+F9)
4. O instalador estará em: `installer\dist\BackupDatabase-Setup-1.0.0.exe`

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
✅ Verifica dependências (sqlcmd, dbbackup)  
✅ Cria atalhos  
✅ Inclui documentação  
✅ Configura inicialização automática (opcional)  

---

## Documentação Completa

- **Instalador**: `installer\README.md`
- **Guia de Instalação**: `docs\installation_guide.md`
- **Requisitos**: `docs\requirements.md`
- **Configuração PATH**: `docs\path_setup.md`

---

**Pronto para criar seu instalador! 🚀**


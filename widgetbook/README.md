# Widgetbook

Catalogo visual irmão do app principal (`backup_database`).

## Windows

O executavel do Widgetbook usa `widgetbook/windows/runner/resources/app_icon.ico`.
Esse arquivo e sincronizado automaticamente quando voce roda `python installer/build_installer.py` na raiz do monorepo.

Se o icone do runner Windows estiver desatualizado, regenere os icones do app principal primeiro:

```powershell
cd ..
dart run flutter_launcher_icons
```

Ou execute o pipeline completo do instalador na raiz.

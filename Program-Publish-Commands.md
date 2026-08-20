# Build- und Publish-Befehle (zwei Launcher, je ein Icon / Assembly-Name)

```powershell
# Build "new instance" launcher (exe name tiny-launcher-new.exe) with new-session icon and display name.
dotnet publish -c Release -r win-x64 `
  /p:AssemblyName=tiny-launcher-new `
  /p:ApplicationIcon="Logos\new-session.ico" `
  /p:AssemblyTitle="Neovim Launcher (new instance)" `
  -o publish\new

# Build "current session" launcher (exe name tiny-launcher-current.exe) with current-session icon and display name.
dotnet publish -c Release -r win-x64 `
  /p:AssemblyName=tiny-launcher-current `
  /p:ApplicationIcon="Logos\current-session.ico" `
  /p:AssemblyTitle="Neovim Launcher (current instance)" `
  -o publish\current
keys".run(115)

# Ohne Zeilenumbüche:

dotnet publish -c Release -r win-x64 /p:AssemblyName=tiny-launcher-new /p:ApplicationIcon="Logos\new-session.ico" /p:AssemblyTitle="Neovim Launcher (new instance)" -o publish\new

dotnet publish -c Release -r win-x64 /p:AssemblyName=tiny-launcher-current /p:ApplicationIcon="Logos\current-session.ico" /p:AssemblyTitle="Neovim Launcher (current instance)" -o publish\current

#Prüfen, ob beide EXEs existieren (PowerShell):
# List both published EXEs
Get-Item -Path .\publish\new\*.exe -ErrorAction SilentlyContinue
Get-Item -Path .\publish\current\*.exe -ErrorAction SilentlyContinue
``

Hinweise zur Konfiguration:

* `<UseAppHost>true</UseAppHost>` ist wichtig, damit eine native exe (apphost) erzeugt wird, in der das Icon sichtbar wird. Ohne AppHost zeigt Windows nicht zuverlässig das Icon, wenn nur ein single-file bundle ohne native host verwendet wird.
* `ApplicationIcon` muss auf eine `.ico`-Datei zeigen. Diese sollte multi-size (16..256) enthalten, siehe vorherige Hinweise.
* `AssemblyName` steuert den Dateinamen der erzeugten exe. Das Programm verwendet den exe-Dateinamen, um zwischen "new" und "current" zu unterscheiden.
* `AssemblyTitle` und `Product` werden von Windows in gewissen Kontexten als FileDescription/Produktname gezeigt; diese Werte lassen sich per `/p:AssemblyTitle="..."` überschreiben.
* Falls `PublishSingleFile=true` Probleme macht beim Icon/Resource-Embedding, kann `PublishSingleFile=false` gewählt; das apphost-exe enthält in jedem Fall das Icon.

## Deployment-Vorschlag

1. Füge `Logos\new-session.ico` und `Logos\current-session.ico` in das Projektverzeichnis (wie in Repo-Layout beschrieben).
2. Führe die beiden `dotnet publish` Befehle aus.
3. Kopiere aus `publish\new\tiny-launcher-new.exe` und `publish\current\tiny-launcher-current.exe` zusammen mit den passenden VBS-Dateien (`open-in-nvim.vbs`, `open-in-nvim-current.vbs`) in das Install-Verzeichnis (z. B. `C:\Program Files\OpenInNvim\`).
4. Passe das Installations-PowerShell-Skript an, dass es den Open-Command der jeweiligen ProgID auf die passende exe setzt, z. B. `"C:\Program Files\OpenInNvim\tiny-launcher-new.exe" "%1"` für New-Instance und `"C:\Program Files\OpenInNvim\tiny-launcher-current.exe" "%1"` für Current-Session.

## Beispiel-Registry-Command (PowerShell-Snippet)

```powershell
# Example: set ProgID open command to tiny-launcher-new.exe
$progId = "Neovim.TextFile.New"
$launcherPath = "C:\Program Files\OpenInNvim\tiny-launcher-new.exe"
$commandKey = "HKCU:\Software\Classes\$progId\shell\open\command"
New-Item -Path $commandKey -Force | Out-Null
New-ItemProperty -Path $commandKey -Name '(default)' -Value "`"$launcherPath`" `"%1`"" -PropertyType String -Force | Out-Null
```

## Ergänzende Empfehlungen

* Icon-Embedding prüfen: nach Publish mit `Resource Hacker` oder `rcedit` kontrollieren, ob EXE tatsächlich das gewünschte Icon enthält.
* Settings-UI-Cache: nach Installation ggf. Explorer/Settings neu starten, damit Windows die neue App-Icon/Name-Anzeige aktualisiert.
* Signieren: Wenn geplant, das Paket breit zu verteilen, empfiehlt sich Code-Signing um Warnungen bei Ausführung zu minimieren.


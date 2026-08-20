# OpenInNvim

Zwei Windows-Explorer-Kontextmenüeinträge für Neovim:
- Open with Neovim (new instance)
- Open with Neovim (current instance)

**Architektur:** Explorer → VBS (unsichtbar) → PowerShell → nvim
Kompatibel mit Windows PowerShell 5.1.

## Link setzen (Junction)

**PowerShell:**

```powershell
New-Item -ItemType Junction -Path 'C:\tools\OpenInNvim' -Target 'E:\repos\Configs\Windows\Contextmenu\OpenInNvim'
```

## Ziele

- Sauber getrennte Workflows: „new“ und „current“
- Zentrale Konfiguration der Pfade (nvim, optional wezterm, optionale Serveradresse)
- Robustes Pfad-/Quoting-Handling (Leerzeichen, neue Dateien)
- Keine Plugins zwingend erforderlich; optional nvr für Komfort

## Verzeichnisstruktur

**Physische Ablage (Repo-Empfehlung):**
`E:\repos\Configs\Windows\Contextmenu\OpenInNvim`

**Kompatibilitätslink für Registry (Junction):**
`C:\tools\OpenInNvim  →  E:\repos\Configs\Windows\Contextmenu\OpenInNvim`

**Inhalt:**
C:\tools\OpenInNvim\
  open-in-nvim.vbs
  open-in-nvim.ps1
  open-in-nvim-current.vbs
  open-in-nvim-current.ps1
  open-in-nvim.config.ps1
  install-context.ps1
  remove-old.reg
  verify.ps1

## Installation

1) Dateien ablegen
   `E:\repos\Configs\Windows\Contextmenu\OpenInNvim verwalten und Junction nach C:\tools\OpenInNvim setzen.`

2) Kontextmenü einrichten
   Variante A (Skript):
     `powershell -ExecutionPolicy Bypass -File "C:\tools\OpenInNvim\install-context.ps1"`
   Variante B (.reg):
     remove-old.reg importieren, danach eigene .reg-Dateien für „new“/„current“ importieren (optional; Skript bevorzugt).

3) Explorer neu starten
   taskkill /F /IM explorer.exe
   explorer.exe

## Konfiguration

Datei: open-in-nvim.config.ps1

### Zentrale Konfiguration für beide Einträge

```ps1
$Cfg = [ordered]@{
  NVIM_BIN    = 'C:\Program Files\Neovim\bin\nvim.exe'
  WEZTERM_BIN = "$env:LOCALAPPDATA\wezterm\wezterm-gui.exe"
  NVIM_SERVER = ''   # leer = Auto-Discovery (nvr --serverlist) oder \\.\pipe\nvim-%USERNAME%
}
```

Bei Scoop/Winget/Portable NVIM_BIN anpassen. NVIM_SERVER kann leer bleiben, wenn eine init.lua serverstart() nutzt oder nvr zur Discovery vorhanden ist.

## Funktionsweise

Open with Neovim (new instance)
 VBS startet PowerShell unsichtbar, PS-Startskript ermittelt Working Directory und Zielpfad.
 Startreihenfolge: WezTerm → Windows Terminal → cmd.exe „start“.
 Es wird stets eine neue Neovim-Instanz gestartet.

Open with Neovim (current instance)
- Kandidatenliste für Serveradresse: NVIM_SERVER (falls gesetzt) → nvr --serverlist (falls nvr installiert) → Heuristik \\.\pipe\nvim-%USERNAME%
- Wenn erreichbar: An bestehende Instanz per nvr --remote oder nvim --remote/--remote-send anbinden.
- Wenn nicht erreichbar: Neue Instanz mit --listen <Adresse> starten und Ziel öffnen.

## Schneller Test

```powershell
PowerShell direkt (new):
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\tools\OpenInNvim\open-in-nvim.ps1" "$env:USERPROFILE\Desktop\test.txt"

PowerShell direkt (current):
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\tools\OpenInNvim\open-in-nvim-current.ps1" "$env:USERPROFILE\Desktop\test.txt"

End-to-End via VBS:
wscript //nologo "C:\tools\OpenInNvim\open-in-nvim.vbs" "%USERPROFILE%\Desktop\test.txt"
wscript //nologo "C:\tools\OpenInNvim\open-in-nvim-current.vbs" "%USERPROFILE%\Desktop\test.txt"
```

## Troubleshooting

- Beim Klick „passiert nichts“:
  - Direkt testen (oben) und ggf. setx OPEN_IN_NVIM_DEBUG 1 setzen.
  - NVIM_BIN in open-in-nvim.config.ps1 prüfen.
  - WezTerm/Windows Terminal vorhanden? Sonst Fallback auf cmd.exe.
- „current“ trifft keine Instanz:
  - In Neovim :echo v:servername prüfen.
  - Mit nvr --serverlist Verfügbarkeit prüfen (falls nvr installiert).
  - Optional init.lua so konfigurieren, dass serverstart('\\.\pipe\nvim-%USERNAME%') beim Start gesetzt wird.

## Deinstallation

- Kontextmenü entfernen: remove-old.reg importieren oder install-context.ps1 anpassen (nur Remove-Key-Aufrufe).
- Junction entfernen:
  Remove-Item -LiteralPath 'C:\tools\OpenInNvim' -Recurse -Force

## Hinweise

- WezTerm-Logs auf „ERROR“ kann man in der eigenen wezterm.lua auf log_info umstellen.
- Für Verzeichnisse öffnet „current“ standardmäßig eine Verzeichnisansicht (cd + edit .).
- Die Implementierung ist PS 5.1 kompatibel (keine ?. oder ?: Operatoren), Single-Responsibility und mit robuster Argument-Quotierung umgesetzt.

---

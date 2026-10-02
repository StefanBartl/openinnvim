# OpenInNvim

Zwei Windows-Explorer-Kontextmenüeinträge für Neovim:
- Open with Neovim (new instance)
- Open with Neovim (current instance)

**Architektur:** Explorer → VBS (unsichtbar) → PowerShell → nvim
Kompatibel mit Windows PowerShell 5.1.

## Link setzen (Junction)

**PowerShell:**

```powershell
New-Item -ItemType Junction -Path 'C:\tools\OpenInNvim' -Target 'E:\repos\openinnvim'
```

Eine Junction braucht weder Administratorrechte noch den Entwicklermodus (anders als ein Symlink).

## Ziele

- Sauber getrennte Workflows: „new“ und „current“
- Zentrale Konfiguration der Pfade (nvim, optional wezterm, optionale Serveradresse)
- Robustes Pfad-/Quoting-Handling (Leerzeichen, neue Dateien)
- Keine Plugins zwingend erforderlich; optional nvr für Komfort

## Verzeichnisstruktur

**Physische Ablage (dieses Repo):**
`E:\repos\openinnvim`

**Kompatibilitätslink für Registry (Junction):**
`C:\tools\OpenInNvim  →  E:\repos\openinnvim`

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
   Dieses Repo (`E:\repos\openinnvim`) verwalten und die Junction nach `C:\tools\OpenInNvim` setzen.

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
- Kandidatenliste für Serveradresse, in dieser Reihenfolge:
  1. NVIM_SERVER (falls gesetzt)
  2. fester Pipe-Name \\.\pipe\nvim-%USERNAME% (falls vorhanden und PREFER_STABLE_PIPE nicht $false)
  3. alle laufenden Instanzen über ihre Standard-Pipe \\.\pipe\nvim.<pid>.<n> (gibt es in jeder Neovim-Sitzung ohne
     Konfiguration; `--headless`-Hilfsprozesse und `-l`-Skripte werden ausgefiltert), sortiert nach INSTANCE_PICK
     (newest/oldest/ask)
  4. nvr --serverlist (nur als letzte Möglichkeit, nvr hängt unter Windows an Pipes)
- Wenn erreichbar: An die Instanz per nvim --server <pipe> --remote / --remote-send anbinden (jeder Aufruf mit Zeitlimit).
- Wenn nicht erreichbar: Neue Instanz mit --listen <Adresse> starten und Ziel öffnen.
- Unter Windows besteht eine Terminal-Sitzung aus zwei Prozessen (sichtbares nvim.exe und dessen `--embed`-Kern); die Pipe
  gehört dem Kern, deshalb wird nach Pipes gesucht und nicht nach der PID des Fensters.

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

## Tests

Die Tests starten eigene Wegwerf-Instanzen und berühren nie eine laufende Sitzung (PID-Einschränkung über
`OPEN_IN_NVIM_ONLY_PIDS`, gefälschter `USERNAME`). Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

Diagnose ohne etwas zu öffnen: `OPEN_IN_NVIM_DRYRUN=1` gibt die geordnete Kandidatenliste aus.

## Deinstallation

- Kontextmenü entfernen: remove-old.reg importieren oder install-context.ps1 anpassen (nur Remove-Key-Aufrufe).
- Junction entfernen (nur den Link, nie den Inhalt; `Remove-Item -Recurse` auf eine Junction kann in
  Windows PowerShell 5.1 den Zielordner leeren):

  ```powershell
  [IO.Directory]::Delete('C:\tools\OpenInNvim', $false)
  ```

## Hinweise

- WezTerm-Logs auf „ERROR“ kann man in der eigenen wezterm.lua auf log_info umstellen.
- Für Verzeichnisse öffnet „current“ standardmäßig eine Verzeichnisansicht (cd + edit .).
- Die Implementierung ist PS 5.1 kompatibel (keine ?. oder ?: Operatoren), Single-Responsibility und mit robuster Argument-Quotierung umgesetzt.

---

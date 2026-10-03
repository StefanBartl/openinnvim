# openinnvim — Live-Test-Checkliste (Stand 2026-10-03, `OpenInNvim.exe`)

Was an `openinnvim` **von Hand im echten System** geprüft werden muss. Automatisiert läuft
`tests\run-tests.ps1` grün (Windows PowerShell 5.1, nur gegen Wegwerf-Instanzen mit `--clean`).
Diese Liste ist für das, was Tests nicht zeigen: der **echte Klick im Explorer**, die echte
Sitzung mit der echten Config, Fokus, Gefühl für die Geschwindigkeit.

Die Liste beschreibt den kompilierten Launcher. Die Fassung für die frühere VBS +
PowerShell-Kette lag bis 2026-10-03 in der nvim-config (`docs/ROADMAP/Final_Checks/`).

**Status:** ❌ ungetestet · 🟡 teilweise · ✅ wie erwartet · 🔴 Fehler (Notiz ausfüllen!).
Ein gefundener Fehler gehört zusätzlich in `ROADMAP.md` im WKDBook `Development/wkdbook-openinnvim` oder als GitHub-Issue.

---

## Table of content

  - [Vorbereitung](#vorbereitung)
  - [Teil A: current instance, Dateien](#teil-a-current-instance-dateien)
  - [Teil B: Ordner und Filetree](#teil-b-ordner-und-filetree)
  - [Teil C: mehrere Instanzen](#teil-c-mehrere-instanzen)
  - [Teil D: keine Instanz erreichbar](#teil-d-keine-instanz-erreichbar)
  - [Teil E: new instance](#teil-e-new-instance)
  - [Teil F: Grenzfälle der laufenden Sitzung](#teil-f-grenzfälle-der-laufenden-sitzung)
  - [Teil G: Installation, Deinstallation, Registry](#teil-g-installation-deinstallation-registry)
  - [Teil H: Diagnose-Schalter und Tests](#teil-h-diagnose-schalter-und-tests)
  - [Teil I: Standard-Apps](#teil-i-standard-apps)
  - [Nach dem Durchlauf](#nach-dem-durchlauf)

---

## Vorbereitung

Installiert ist am 2026-10-03 auf STEVESPC (`install.ps1`): `OpenInNvim.exe` und
`open-in-nvim.ini` in `%LOCALAPPDATA%\OpenInNvim`. Einstellungen, die du in den Teilen unten
änderst, stehen in dieser ini (`true`/`false`, keine PowerShell-Syntax).

Testdateien anlegen (einmalig, auf dem Desktop):

```powershell
$t = "$env:USERPROFILE\Desktop\oin-test"
New-Item -ItemType Directory -Force "$t\My Dir (1) #2 [x] 'q' %p & more" | Out-Null
New-Item -ItemType Directory -Force "$t\einfach" | Out-Null
New-Item -ItemType Directory -Force "$t\%TEMP%x" | Out-Null
Set-Content "$t\einfach\plain.txt" 'plain'
Set-Content "$t\My Dir (1) #2 [x] 'q' %p & more\note #1 [a].txt" 'special'
Set-Content "$t\datei mit leerzeichen.txt" 'space'
Set-Content -LiteralPath "$t\g[1].txt" 'bracket'
Set-Content "$t\g1.txt" 'sibling'
Set-Content -LiteralPath "$t\a`$USERNAME b.txt" 'dollar'
Set-Content "$t\%TEMP%x\in percent.txt" 'percent'
```

Der Launcher hat kein Konsolenfenster; für eine Ausgabe im Terminal die Ausgabe umleiten:

```powershell
$exe = "$env:LOCALAPPDATA\OpenInNvim\OpenInNvim.exe"
$env:OPEN_IN_NVIM_DRYRUN = '1'
& $exe current "$env:USERPROFILE\Desktop\oin-test\einfach\plain.txt" | Out-String
$env:OPEN_IN_NVIM_DRYRUN = $null
```

| # | Was testen | Erwartung | Status | Notizen |
| --- | --- | --- | --- | --- |
| V1 | Rechtsklick auf `plain.txt` → "Weitere Optionen anzeigen" | Beide Einträge "Open with Neovim (new instance)" und "(current instance)", mit Neovim-Icon, nicht doppelt | ❌ | |
| V2 | Der Dry-Run oben | `mode:`, `target:`, `cwd:` und eine `candidate:`-Zeile mit der laufenden Sitzung; es wird nichts geöffnet | ✅ | 2026-10-03, fand `nvim.<pid>.0` |

---

## Teil A: current instance, Dateien

Eine einzelne Neovim-Sitzung läuft (TUI im Terminal, deine echte Config).

| # | Was testen | Erwartung | Status | Notizen |
| --- | --- | --- | --- | --- |
| A1 | Klick **current** auf `plain.txt` | Datei erscheint in der laufenden Sitzung, kein neues Fenster, kein Flackern | ✅ | 2026-10-03 vom Nutzer bestätigt |
| A2 | Geschwindigkeit | Sofort (gemessen ca. 50 ms gegen `--clean`-Instanzen; mit deiner Config kommt die Zeit dazu, die Neovim zum Öffnen braucht) | ❌ | |
| A3 | `datei mit leerzeichen.txt` | Öffnet, Name korrekt | ❌ | |
| A4 | `note #1 [a].txt` im Ordner `My Dir (1) #2 [x] 'q' %p & more` | Öffnet genau diese Datei | ❌ | |
| A5 | `g[1].txt` (daneben liegt `g1.txt`) | Es öffnet `g[1].txt` mit dem Inhalt `bracket`, nicht `g1.txt` | ❌ | |
| A6 | `a$USERNAME b.txt` | Öffnet mit dem Inhalt `dollar`; kein leerer Buffer `a<dein Name> b.txt` | ❌ | |
| A7 | `in percent.txt` im Ordner `%TEMP%x` | Öffnet die Datei in diesem Ordner | ❌ | |
| A8 | Dieselbe Datei zweimal klicken | Kein zweiter Buffer; das Fenster, das sie zeigt, wird angesprungen (auch in einem anderen Tab) | ❌ | |
| A9 | Buffer geändert und ungespeichert, dann eine andere Datei klicken | Neue Datei kommt, nichts geht verloren (bei `nohidden` in einem Split) | ❌ | |
| A10 | Im **Insert-Modus** klicken | Datei öffnet, du bist danach im Normal-Modus; der getippte Text im alten Buffer ist unverändert | ❌ | |
| A11 | Kommandozeile `:` offen, dann klicken | Die Kommandozeile wird abgebrochen, die Datei öffnet | ❌ | |
| A12 | Kommandozeilen-Fenster `q:` offen, dann klicken | Bekannte Lücke: die Instanz lehnt ab (`E11`), der Klick geht an die nächste Instanz oder startet eine neue. Notiere, was passiert | ❌ | |
| A13 | Terminal-Buffer im aktiven Fenster (Terminal-Modus), dann klicken | Datei öffnet in einem normalen Fenster, das Terminal läuft weiter | ❌ | |
| A14 | Fokus ohne `FOCUS_TERMINAL` | Das Terminalfenster kommt **nicht** von selbst nach vorn (so gewollt) | ❌ | |
| A15 | `FOCUS_TERMINAL = true` in der ini, ein anderes Fenster im Vordergrund, klicken | Das Terminalfenster der Sitzung kommt nach vorn (auch minimiert). Bei mehreren Fenstern **eines** Terminal-Prozesses kann das falsche kommen (bekannte Grenze). Danach entscheiden: opt-in lassen oder Standard | ❌ | |
| A16 | Plugins deiner Config, die auf Verzeichnis- oder Buffer-Wechsel reagieren (filetree, Statuszeile, LSP) | Verhalten sich wie beim Öffnen mit `:edit` | ❌ | |

---

## Teil B: Ordner und Filetree

| # | Was testen | Erwartung | Status | Notizen |
| --- | --- | --- | --- | --- |
| B1 | Klick **current** auf Ordner `einfach` (Sitzung hat `:Filetree`, kein Baum offen) | Der Baum öffnet auf diesem Ordner | ❌ | |
| B2 | Dasselbe mit offenem, anders gewurzeltem Baum | Baum springt auf den Ordner, kein zweiter Baum | ❌ | |
| B3 | Ordner `My Dir (1) #2 [x] 'q' %p & more` | Baum öffnet auf genau diesem Ordner | ❌ | |
| B4 | Rechtsklick auf den **Hintergrund** eines Explorer-Fensters → current | Baum auf dem Ordner dieses Fensters | ❌ | |
| B5 | `FOLDER_OPENS_IN = edit` in der ini, Ordner klicken | Arbeitsverzeichnis wechselt, Verzeichnisansicht, kein Baum. Danach zurück auf `filetree` | ❌ | |
| B6 | Sitzung ohne filetree.nvim (`nvim --clean`), Ordner klicken | Verzeichnisansicht + Arbeitsverzeichnis, keine Fehlermeldung | ❌ | |
| B7 | Hintergrund von `C:\` (Laufwerks-Root) | Öffnet `C:\`, kein Quoting-Fehler | ❌ | |
| B8 | Ordner `%TEMP%x` mit `FOLDER_OPENS_IN = edit` | Arbeitsverzeichnis ist genau dieser Ordner | ❌ | |

---

## Teil C: mehrere Instanzen

Zwei Neovim-Sitzungen (A zuerst, B danach) in getrennten Fenstern.

| # | Was testen | Erwartung | Status | Notizen |
| --- | --- | --- | --- | --- |
| C1 | Standard (`INSTANCE_PICK = newest`, `PREFER_STABLE_PIPE = true`): Datei klicken | Landet in der Sitzung, die `\\.\pipe\nvim-<USER>` besitzt (bei deiner Config die zuerst gestartete, also A); ohne festen Namen in B | ❌ | |
| C2 | `PREFER_STABLE_PIPE = false` | Landet in B (zuletzt gestartet) | ❌ | |
| C3 | Dazu `INSTANCE_PICK = oldest` | Landet in A | ❌ | |
| C4 | `INSTANCE_PICK = ask` | **Sichtbares** Auswahlfenster mit Arbeitsverzeichnis, Datei und PID je Instanz (ohne Startzeit: bekannte Lücke) | ❌ | |
| C5 | `ask`: Eintrag wählen, Enter oder Doppelklick | Datei landet in der gewählten Instanz, auch wenn eine andere den festen Namen besitzt | ❌ | |
| C6 | `ask`: Escape | Fenster schließt, nichts wird geöffnet, keine neue Instanz | ❌ | |
| C7 | `ask` mit nur einer Instanz | Kein Fenster, direkt geöffnet | ❌ | |
| C8 | Ein `nvim --headless` im Hintergrund, normaler Klick | Wird nie gewählt (Dry-Run: nicht unter den Kandidaten) | ❌ | |
| C9 | Einstellungen zurücksetzen (`newest`, `true`, `filetree`, `false`) | ini wieder im Standard | ❌ | |

---

## Teil D: keine Instanz erreichbar

Alle Neovim-Fenster schließen.

| # | Was testen | Erwartung | Status | Notizen |
| --- | --- | --- | --- | --- |
| D1 | Klick **current** auf `plain.txt` | WezTerm startet Neovim mit der Datei, Arbeitsverzeichnis = ihr Ordner, **ohne** `git`-Fehlermeldungen | ❌ | |
| D2 | Danach zweiter Klick **current** auf eine andere Datei | Landet in der gerade gestarteten Instanz, kein weiteres Fenster | ❌ | |
| D3 | Klick **current** auf einen Ordner | Neues Terminal, Neovim im Ordner, ohne Datei | ❌ | |
| D4 | `TERMINAL = wt` in der ini | Windows Terminal wird genommen | ❌ | |
| D5 | `TERMINAL = console` | Neovim in einer eigenen Konsole, kein `cmd.exe` dazwischen | ❌ | |
| D6 | Nach dem Start: `Get-Process OpenInNvim` | Kein hängender Launcher-Prozess | ❌ | |

---

## Teil E: new instance

| # | Was testen | Erwartung | Status | Notizen |
| --- | --- | --- | --- | --- |
| E1 | Klick **new** auf `plain.txt` bei laufender Sitzung | Immer ein neues Terminal mit neuem Neovim und der Datei | ✅ | 2026-10-03 vom Nutzer bestätigt (nach dem PATH-Fix `c9976bd`) |
| E2 | Klick **new** auf `note #1 [a].txt` und auf `a$USERNAME b.txt` | Datei korrekt geöffnet | ❌ | |
| E3 | Klick **new** auf einen Ordner und auf den Hintergrund von `C:\` | Neues Neovim im Ordner, ohne Datei | ❌ | |
| E4 | Die laufende Sitzung | Bleibt unverändert | ❌ | |
| E5 | `NVIM_BIN` in der ini auf einen falschen Pfad **und** `nvim` nicht im `PATH` (nur mit Aufwand herzustellen) | Meldungsfenster "Neovim not found"; danach zurücksetzen | ❌ | |

---

## Teil F: Grenzfälle der laufenden Sitzung

| # | Was testen | Erwartung | Status | Notizen |
| --- | --- | --- | --- | --- |
| F1 | `:sleep 20` laufen lassen, in dieser Zeit klicken | Die Datei öffnet **während** des Sleeps (er blockiert RPC nicht); keine neue Instanz | ❌ | |
| F2 | Hit-Enter-Prompt erzeugen (`:echo "a\nb\nc"`), dann klicken | Die blockierte Sitzung wird sofort übersprungen: die Datei geht an die nächste Instanz oder eine neue startet | ❌ | |
| F3 | Eine Datei, deren Öffnen lange dauert (großes File, viele Autocommands) | Sie öffnet **nur** in der einen Sitzung; es startet keine zweite | ❌ | |
| F4 | Datei mit vorhandener Swap-Datei (in einer anderen Sitzung offen) | Neovim zeigt seinen Swap-Dialog; der Launcher bleibt unsichtbar wartend und beendet sich spätestens nach 15 s | ❌ | |
| F5 | Neovide oder anderes GUI, falls benutzt | Wird gefunden und beliefert | ❌ | |
| F6 | Sehr langer Pfad (> 260 Zeichen) | Öffnet oder scheitert sauber, kein Hänger | ❌ | |
| F7 | Neovim als Administrator gestartet, Klick aus dem normalen Explorer | Vermutlich nicht erreichbar (Vertrauensprüfung, Pipe-Rechte): notiere, was passiert | ❌ | |

---

## Teil G: Installation, Deinstallation, Registry

| # | Was testen | Erwartung | Status | Notizen |
| --- | --- | --- | --- | --- |
| G1 | `powershell -NoProfile -ExecutionPolicy Bypass -File E:\repos\openinnvim\install.ps1 -DryRun` | Listet Build, Config und 6 `Write HKCU\...`-Zeilen, ändert nichts | ❌ | |
| G2 | Echte Installation (ohne `-DryRun`) | `Neovim: <Pfad>`, "Installed:", `Launcher:` und `Config:` | ✅ | 2026-10-03 |
| G3 | Inhalt von `%LOCALAPPDATA%\OpenInNvim` | `OpenInNvim.exe`, `open-in-nvim.ini`, `install.manifest.txt` (dazu `Logos` und `_nicht-mehr-gebraucht` aus früheren Versionen) | ✅ | 2026-10-03 |
| G4 | `Get-ItemProperty -LiteralPath 'HKCU:\Software\Classes\*\shell\Open_in_Neovim_current\command'` | `"C:\Users\...\OpenInNvim\OpenInNvim.exe" current "%1"` | ✅ | 2026-10-03, alle 6 Einträge geprüft |
| G5 | Erneut `install.ps1` | "Config kept", deine ini bleibt | ✅ | 2026-10-03 |
| G6 | Direkt nach einer Neuinstallation klicken | Es läuft der neue Befehl (der Installer meldet dem Explorer die Änderung, `b752940`) | ❌ | |
| G7 | `install.ps1 -InstallDir E:\repos\openinnvim` (in place) | exe in `<repo>\bin`, Einträge zeigen dorthin, `git status` sauber. Danach wieder `install.ps1` ohne Parameter | ❌ | |
| G8 | `uninstall.ps1 -DryRun`, dann `uninstall.ps1` | Alle 6 Einträge weg, Dateien bleiben. Danach `install.ps1` erneut | ❌ | |
| G9 | `uninstall.ps1 -RemoveFiles` | Löscht exe und Manifest, die ini bleibt (ohne `-RemoveConfig`) | ❌ | |
| G10 | Windows 11: Einträge nur unter "Weitere Optionen anzeigen"? | Ja, bekannte Grenze (siehe Roadmap, Punkt 3) | ❌ | |

---

## Teil H: Diagnose-Schalter und Tests

Jeweils mit `$exe` und `| Out-String` wie in der Vorbereitung; Variablen danach wieder auf `$null`.

| # | Was testen | Erwartung | Status | Notizen |
| --- | --- | --- | --- | --- |
| H1 | `OPEN_IN_NVIM_DRYRUN=1`, Modus `current` | Kandidaten in Reihenfolge, öffnet nichts | ✅ | 2026-10-03 |
| H2 | `OPEN_IN_NVIM_SPAWN_DRYRUN=1`, Modus `new` | `spawn:`, `spawn-cwd:` und `spawn-via:`-Zeilen (wezterm, wt, console), kein `--listen`, startet nichts | ✅ | 2026-10-03, auch mit abgeschnittenem `PATH` |
| H3 | `OPEN_IN_NVIM_NO_SPAWN=1` ohne laufende Instanz | `no reachable instance`, Exit-Code 3, kein Fenster | ❌ | |
| H4 | `OPEN_IN_NVIM_LOG=<Datei>` und ein echter Klick-Aufruf | Eine Zeile je Entscheidung mit Millisekunden | ❌ | |
| H5 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File E:\repos\openinnvim\tests\run-tests.ps1` | `passed: N  failed: 0`, danach keine übrigen `nvim`-Prozesse außer deinen; deine Sitzung bleibt unberührt | ✅ | 2026-10-03, 252 |

---

## Teil I: Standard-Apps

Nur wenn du Neovim als Standard-App für Dateitypen benutzt (`docs/FEATURES/DEFAULT-APPS.md`).

| # | Was testen | Erwartung | Status | Notizen |
| --- | --- | --- | --- | --- |
| I1 | Doppelklick auf eine Datei, die `Neovim.TextFile*` zugeordnet ist | Öffnet über `OpenInNvim.exe` (`register-nvim-default-app.ps1` schreibt `Neovim.TextFile`, `install-icons-for-progids.ps1` schreibt `.New`/`.Current` samt open-Kommando) | ❌ | |
| I2 | Einstellungen → Apps → Standard-Apps | "Neovim (new instance)" / "(current instance)" mit Namen; Icon generisch (die exe hat kein eingebettetes Icon: bekannte Lücke) | ❌ | |
| I3 | `register-nvim-default-app.ps1` | Fragt nach Modus, schreibt das ProgID auf die exe | ❌ | |

---

## Nach dem Durchlauf

- Fehler nach `ROADMAP.md` im WKDBook `Development/wkdbook-openinnvim` (Abschnitt 4) oder als GitHub-Issue, und in
  `HANDOVER.md` im WKDBook `Development/wkdbook-openinnvim` unter "Offen".
- Geänderte Einstellungen in `%LOCALAPPDATA%\OpenInNvim\open-in-nvim.ini` zurück auf den Standard.
- Testordner löschen: `Remove-Item "$env:USERPROFILE\Desktop\oin-test" -Recurse`.
- Der frühere Teil K (neotest-Listener) gehört nicht hierher; er steht im neotest-Handover der
  nvim-config (WKDBooks `nvim-config/Backlog/TASKS/neotest-listener-und-windows-laeufe-2026-10-03.md`).

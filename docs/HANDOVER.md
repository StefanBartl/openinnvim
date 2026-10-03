# openinnvim (Übergabe)

Stand: 2026-10-03. Maßgeblich ist der Abschnitt
[Stand openinnvim](#stand-openinnvim-2026-10-03-maßgeblich); die Abschnitte danach sind der Verlauf
(Review-Runde, Paketplan) und die Commit-Liste.

**Ort dieser Datei:** seit 2026-10-03 im openinnvim-Repo (`docs/HANDOVER.md`), vorher in der
nvim-config. Pfade mit `docs/ROADMAP/...` ohne Repo-Angabe meinen das nvim-config-Repo.

**Der neotest-Teil** (Listener, `NVIM_LISTEN_ADDRESS`, scheiternde `neotest-plenary`-Läufe, "Option E")
betrifft die nvim-config und liegt dort:
`nvim-config/docs/ROADMAP/handovers/neotest-listener-und-plenary_HANDOVER.md`.

---

## Table of content

  - [Stand openinnvim (2026-10-03, maßgeblich)](#stand-openinnvim-2026-10-03-maßgeblich)
  - [Kurzfassung](#kurzfassung)
  - [Wo liegt was](#wo-liegt-was)
  - [Unterbrochene Review-Runde (2026-10-03)](#unterbrochene-review-runde-2026-10-03)
  - [Offen und Nachfrage](#offen-und-nachfrage)
  - [Commits dieses Chats](#commits-dieses-chats)

---

## Stand openinnvim (2026-10-03, maßgeblich)

**Dieser Abschnitt gilt vor allem, was weiter unten noch die VBS + PowerShell-Kette beschreibt.**

**Gemacht**

- openinnvim ist jetzt **ein kompiliertes Programm** `OpenInNvim.exe` (C# 5 / .NET Framework, gebaut
  mit dem `csc.exe` von Windows über `build.ps1`). Es bedient beide Menüeinträge
  (`OpenInNvim.exe current "%1"` / `new "%1"`). Quelltext in `E:\repos\openinnvim\src\`.
- Paket 1 (`b2f8b90`): Kern für `current` — rohe Kommandozeile, `open-in-nvim.ini`, Pipe-Suche mit
  Vertrauensprüfung des Pipe-Besitzers (nvim.exe, gleiche Sitzung, gleicher Benutzer), vollständiger
  msgpack-Decoder, RPC über Pipe und TCP, `nvim_get_mode`-Vorprüfung, Öffnen per `bufadd` statt
  Ex-Dateiargument. Gemessen 53 ms je Klick statt 540 ms (altes `.ps1`), Maschine STEVESPC.
- Paket 2 (`9db2279`): neue Instanz (WezTerm, Windows Terminal, Konsole; kein `cmd.exe`), Chooser
  (`INSTANCE_PICK = ask`), Fokus (`FOCUS_TERMINAL`).
- Paket 3 (`5dede04`): `install.ps1` baut die exe, schreibt ini und die 6 HKCU-Einträge mit absolutem
  Pfad; `uninstall.ps1` nach Manifest; `register-nvim-default-app.ps1` zeigt auf die exe.
  **Entfernt:** beide `.vbs`, `open-in-nvim.ps1`, `open-in-nvim-current.ps1`, `open-in-nvim.lib.ps1`,
  `open-in-nvim.config.ps1`, `verify.ps1`, TinyLauncher (`Program.cs`, `.csproj`, `deploy-…ps1`),
  die alte Testsuite.
- Tests: `tests\run-tests.ps1` (Windows PowerShell 5.1), 252 Prüfungen grün, nur gegen eigene
  Wegwerf-Instanzen.
- Paket 4: Repo-Docs auf den neuen Stand gebracht, `docs/ROADMAP.md` neu (Setup-Dateien als
  GitHub-Release für Windows, Linux, macOS mit Aufwandsschätzung: Windows ca. 2 Tage, alle drei mit
  portablem Kern ca. 11–15 Tage).

**Vom Nutzer im Explorer bestätigt (2026-10-03):** "current instance" und "new instance" funktionieren
nach den drei Fixes unten.

- `b752940`: `install.ps1`/`uninstall.ps1` melden dem Explorer `SHCNE_ASSOCCHANGED`. Ohne das führte
  ein Klick direkt nach der Installation noch den alten Befehl aus (Windows Script Host:
  `C:\tools\OpenInNvim\open-in-nvim.vbs` nicht gefunden), obwohl die Registry schon richtig war.
- `c9976bd`: Der Launcher ergänzt den geerbten `PATH` vor dem Start einer neuen Instanz aus der
  Registry (Maschine + Benutzer). Ursache: der Benutzer-`PATH` auf STEVESPC hat 101 Einträge und
  4092 Zeichen, der Explorer gibt dann einen abgeschnittenen `PATH` weiter; WezTerm und Windows
  Terminal wurden nicht gefunden (Rückfall auf die Konsole), und Neovim hatte kein `git`
  (`gitsigns`, `lensline` meldeten Fehler). Testschalter: `OPEN_IN_NVIM_NO_PATH_REFRESH`.
- `cbfe2be`: verstümmelte Testzeile repariert; Suite 252/252.

**Lokal auf STEVESPC geändert (kein Git)**

- `install.ps1` ausgeführt: exe und ini in `%LOCALAPPDATA%\OpenInNvim`, die 6 Einträge zeigen dorthin.
  Probelauf (`OPEN_IN_NVIM_DRYRUN=1`) fand die laufende Sitzung.
- Die drei "Öffnen mit"-ProgIDs (`Neovim.TextFile`, `.New`, `.Current`) zeigten auf die alten
  Launcher bzw. einen toten Pfad; jetzt auf `OpenInNvim.exe` mit `new`/`current`.
- `tiny-launcher-*.exe` (je 68 MB) nach `%LOCALAPPDATA%\OpenInNvim\_nicht-mehr-gebraucht` verschoben.
- Junction `C:\tools\OpenInNvim` entfernt (wird nicht mehr gebraucht).

**Verworfen**

- Die Fundstellen in der PowerShell-Kette zu beheben (Entscheidung des Nutzers: kompilierter Launcher).
- Die eigene adversarielle Gegenprüfung der 31 Fundstellen (durch Tests im neuen Programm ersetzt).
- Agentenketten je Paket (Bauen, Review, Fix, Nachprüfung): dem Nutzer zu langsam. Das Review von
  Paket 1 wurde mittendrin gestoppt; Pakete 2 und 3 sind direkt gebaut. **Keines der drei
  Code-Commits hat ein unabhängiges Review**, belegt sind sie nur durch die Testsuite.
- `nvim --server … --remote` und `cmd /c start` als Wege (siehe Design-Datei).

**Offen**

- [x] **Echter Klick im Explorer:** Datei mit current und new vom Nutzer bestätigt. Ordner und
      Ordner-Hintergrund sind nicht einzeln bestätigt.
- [x] Benutzer-`PATH` auf STEVESPC am 2026-10-03 entrümpelt: von 101 Einträgen / 4092 Zeichen auf
      44 Einträge / 1839 Zeichen (29 Doppelte, 23 schon im Maschinen-`PATH`, 4 nicht mehr vorhandene
      Ordner entfernt). Sicherung des alten Werts: `C:\Users\bartl\PATH-user-backup-2026-10-03.txt`.
      Erst neu gestartete Programme sehen den neuen Wert.
- [ ] Unabhängiges Review über `src\` und die Installer (Paket 5).
- [ ] Test der Explorer-Übergabe über ein Shell-Verb (`Start-Process -Verb`) fehlt.
- [ ] Vertrauensprüfung "anderer Benutzer / andere Sitzung" ist eingebaut, aber ungetestet.
- [x] Live-Test-Liste für die exe neu geschrieben und ins Repo geholt: [`LIVE-TESTS.md`](LIVE-TESTS.md)
      (am 2026-10-03; die meisten Punkte sind noch ungetestet).
- [ ] WKDBook: `openinnvim/ROADMAP/ROADMAP.md` und Backlog an den neuen Stand anpassen.
- [ ] Beim Docs-Abgleich gefunden, noch offen: Chooser-Label ohne Startzeit; Fokus für eine reine
      Konsole (`AttachConsole` aus dem Design fehlt); `install-icons-for-progids.ps1` ist verwaist
      (nichts schreibt mehr das open-Kommando von `Neovim.TextFile.New`/`.Current`);
      `uninstall.ps1` entfernt die Standard-App-Registrierung nicht; `install.ps1 -Force` übernimmt
      die Werte einer alten `open-in-nvim.config.ps1` nicht und löscht sie trotzdem; in-place-Install
      schreibt kein Manifest; `.gitignore` hat noch `obj/`, `publish/`, `*.user`; die exe hat kein
      eingebettetes Icon. Behoben in `7cdc4af`: `NVIM_BIN` wurde relativ zum angeklickten Ordner
      geprüft, Fokus lief zweimal je Klick.
- [ ] Optional: Benutzer-Variable `NVIM_VBS` löschen; Ordner `_nicht-mehr-gebraucht` löschen.
- [ ] Kleinere bekannte Lücken stehen in `E:\repos\openinnvim\docs\ROADMAP.md`, Abschnitt 4
      (Kommandozeilenfenster `q:`, Prompt zwischen Probe und Anfrage, zwei Icons, WezTerm-Fenster).
- Neovim 0.12.2 stürzt ab (0xC0000005), wenn das Fenster eines ca. 50 ms alten Terminal-Buffers
  geteilt wird; ohne den Launcher reproduziert, kein Launcher-Fehler, nicht gemeldet.

---

## Kurzfassung

- **openinnvim wird auf einen kompilierten Launcher umgebaut** (Entscheidung 2026-10-03, Design im
  WKDBook, Paket 1 läuft). Bis Paket 3 fertig ist, gilt die Beschreibung der VBS + PowerShell-Kette
  unten weiter; danach muss `install.ps1` neu ausgeführt werden. Details in
  [Unterbrochene Review-Runde](#unterbrochene-review-runde-2026-10-03).

---

## Wo liegt was

| Was | Ort |
| --- | --- |
| Repo | `E:\repos\openinnvim`, GitHub `StefanBartl/openinnvim` (alter Name `open-in-nvim` leitet weiter) |
| Offene Arbeit am Tool | `WKDBooks/Development/wkdbook-myplugins/openinnvim/ROADMAP/ROADMAP.md` |
| Bauprotokoll des Launchers | `.../openinnvim/Backlog/FEATURES/2026-10-02_current-instance-launcher.md` |
| Untersuchung `rpc_pipe`, Umzug, Junction-Reparatur, Registry-Prüfung | `.../openinnvim/Backlog/TASKS/2026-10-02_nvim-listen-address-und-kontextmenue.md` |
| neotest-Listener: Messtabellen, Optionen, Wiederholung der Messung | `.../openinnvim/Backlog/TASKS/2026-10-02_neotest-listener-messung.md` |
| Review-Funde (Bug / Sicherheit / Performance), Docs-Standardisierung, PowerShell-5.1-Lehre | `.../openinnvim/Backlog/TASKS/2026-10-02_openinnvim-review.md` |
| Installer, relative VBS, Fokus, **zweiter** Review | `.../openinnvim/Backlog/TASKS/2026-10-02_installer-fokus-zweiter-review.md` |
| Live-Tests für dich | [`LIVE-TESTS.md`](LIVE-TESTS.md) |
| **Review-Fundstellen vom 2026-10-03 (31 Stück, ungeprüft)** | [`REVIEW-2026-10-03.md`](REVIEW-2026-10-03.md) |
| **Design des nativen Launchers, Paketplan mit Stand** | `WKDBooks/.../openinnvim/ROADMAP/native-launcher-design.md` |
| Probe-Tool für neotest-Läufe mit der echten Config | `WKDBooks/.../TOOLS/neotest-run-probe.md`, `TOOLS/scripts/neotest-run-probe/` |
| Installierte Binaries/VBS der Exe-Variante | `C:\Users\bartl\AppData\Local\OpenInNvim` (kein Repo, nicht angefasst) |

---

## Unterbrochene Review-Runde (2026-10-03)

Auftrag des Nutzers im vierten Chat: "Prüfe die Ergebnisse und die Commits nochmal, mach eigene
Tests, finde die optimale Lösung mit Bug-, Sicherheits- und Tempo-Verbesserungen." Dafür lief ein
Workflow mit sieben Agenten **nacheinander** (nie mehr als einer), vier Phasen:

1. **openinnvim-Review** auf HEAD `a464fd4` aus drei Blickwinkeln (Bugs + PowerShell 5.1, Sicherheit,
   Tempo), jeder mit Testlauf und eigenen Experimenten gegen Wegwerf-Instanzen. **Fertig.**
2. **Adversarielle Gegenprüfung** jeder Fundstelle (ein Agent, alle 31). **Abgebrochen mitten im
   Lauf** (Chat beendet), kein Ergebnis.
3. **Docs gegen Code/Git/System** (openinnvim README + `docs/`, dieses Handover, Final_Checks, Report
   Aufgabe 1/4, WKDBook-Backlog/Roadmap, `TOOLS/neotest-run-probe.md`). **Nicht gestartet.**
4. **neotest-Lösung empirisch** mit der echten Config (Szenarien S0–S5, Attach-Fix, Vorschlagsdiffs).
   **Nicht gestartet.**

Kein Agent hat ein Repo verändert oder committet (`git status` in openinnvim, lib.nvim, Config-Worktree,
WKDBooks nach dem Abbruch: sauber); keine Streuprozesse.

**Ergebnis von Phase 1:** 31 Fundstellen (12 Bugs, 10 Sicherheit, 9 Tempo) mit Behauptung, Beleg,
Reproduktion und Fix-Vorschlag im Bericht
[`REVIEW-2026-10-03.md`](REVIEW-2026-10-03.md) —
**ungeprüft**, also Behauptungen je eines Reviewers. Die Testsuite lief bei zwei von drei Agenten
**104/104 grün** (Windows PowerShell 5.1, 23 s); der dritte sah einen Abbruch bei 99/104, weil
`Get-FileHash` fehlt, wenn PS 5.1 den `PSModulePath` eines pwsh-7-Elternprozesses erbt (B-F-06).
Kurzfassung der Behauptungen, nach Gewicht:

- **hoch:** `INSTANCE_PICK='ask'`-Chooser ist über die versteckte VBS-Kette unsichtbar und blockiert
  endlos (B-F-01); `tiny-launcher-new.exe` startet wegen leerem `Assembly.Location` im
  Single-File-Publish das *current*-VBS (B-F-02); ein unerreichbarer TCP-`NVIM_SERVER` kostet 5,7 s
  und startet einen versteckten Editor mit voller Config (P-PERF-1); ein Öffnen über 3 s gilt als
  Ablehnung, die Datei landet zusätzlich in einer zweiten Instanz (P-PERF-2); ~85 % der Klickzeit
  sind Host-Overhead (VBS + `powershell.exe`-Start + erste Cmdlets), ein kompilierter
  .NET-Framework-Launcher braucht 67 ms statt ~540 ms (P-PERF-3, mit gemessenem Prototyp).
- **mittel, mehrfach unabhängig gefunden:** `%NAME%` in Datei-/Ordnernamen wird von
  `WScript.Shell.Run` und von `cmd start` expandiert (B-F-03, S-F3, B-F-12, S-F8; Fix: Pfad per
  Umgebungsvariable an PowerShell reichen, verifiziert); Namen mit `$NAME` oder `[...]` verändert
  Vims Dateiargument-Expansion auch auf der RPC-Route, weil `drop`/`fnameescape` benutzt wird
  (S-F4; Fix: `bufadd` + `nvim_win_set_buf`, verifiziert); stabile Pipe und `NVIM_SERVER` bekommen
  keine der Prüfungen (UI, nvim.exe, Session), ein Pipe-Squatter oder headless-Besitzer erhält die
  Datei (B-F-05, S-F1); `[int]`-Casts auf ungeprüfte Pipe-Namen/Antworten brechen unter
  `$ErrorActionPreference='Stop'` jeden Klick (S-F2); ein blockierter Editor (hit-enter) kostet
  0,5 s je Instanz und 3 s auf der stabilen Pipe, `nvim_get_mode` antwortet in 4 ms (B-F-08,
  P-PERF-5); der msgpack-Decoder behandelt unbekannte Typen wie "unvollständig" und verbrennt das
  Zeitlimit (B-F-09, S-F5, P-PERF-6); Discovery fragt alle Instanzen sequenziell, obwohl für
  `newest` die erste reicht (P-PERF-7); `install.ps1` schreibt ein relatives `-InstallDir` relativ
  in die Registry (B-F-07); cmdlet-freier Hot-Path spart ~240 ms (P-PERF-4).
- **niedrig:** `Trim('"')` macht aus `C:\"` ein `C:` (B-F-10), `wscript.exe` ohne Pfad in der
  Registry (S-F7), Fokus-Walk über veraltete PID-Tabelle (S-F9, P-PERF-8), veraltete Zeitangaben
  in Code und Docs (P-PERF-9, B-F-11, S-F10), `uint32`/`array32` im Decoder.

**Entscheidung des Nutzers (2026-10-03, nach der Unterbrechung): kompilierter Launcher jetzt.**
Die Fundstellen werden nicht mehr in der VBS + PowerShell-Kette behoben, sondern in **einem**
C#-Programm `OpenInNvim.exe` (C# 5 / .NET Framework, gebaut mit dem `csc.exe` von Windows, kein
SDK), das beide Menüeinträge bedient und die alte Kette ersetzt. Die eigene Gegenprüfung der 31
Fundstellen (Phase 2) entfällt damit: was am Verhalten hängt, wird im neuen Programm per Test
belegt. Die **verbindliche Vorgabe** (Kommandozeile, Config als `open-in-nvim.ini`, Instanzsuche,
Vertrauensprüfung des Pipe-Besitzers, RPC-Client, Öffnen ohne Ex-Dateiargument, Start einer neuen
Instanz, Chooser, Fokus, Build/Installation/Tests, Paketplan mit Stand) liegt im WKDBook:
`WKDBooks/Development/wkdbook-myplugins/openinnvim/ROADMAP/native-launcher-design.md` (`57f3507`).

**Paketplan** (je Paket: ein Agent baut, ein zweiter prüft unabhängig, bestätigte Funde werden
behoben, dann Commit auf `main`; nie mehr als ein Agent gleichzeitig):

1. Kern für `current` (`src/*.cs`, `build.ps1`, `tests/run-native-tests.ps1`); alte Kette bleibt
   unangetastet und benutzbar.
2. `new` und Start einer Instanz (WezTerm, Windows Terminal, Konsole ohne `cmd.exe`), Chooser, Fokus.
3. `install.ps1`/`uninstall.ps1` neu (baut die exe, schreibt die ini und die 6 Einträge mit
   absoluten Pfaden), Standard-App-Registrierung auf die exe, **alte Kette löschen** (VBS, die drei
   `.ps1`, TinyLauncher), Shell-Verb-Test. **Ab hier muss der Nutzer `install.ps1` neu ausführen**:
   seine Einträge zeigen über die Junction `C:\tools\OpenInNvim` noch auf die VBS im Repo.
4. Repo-Docs neu, Messwerte alt/neu.
5. Abschluss-Review über das ganze Repo; dieses Handover, die Final_Checks-Liste und die Roadmap im
   WKDBook nachziehen.

**Wenn ein Chat mitten in einem Paket abbricht:** `git -C E:\repos\openinnvim status` zeigt die
unfertige Arbeit im Arbeitsverzeichnis (Agenten committen nicht). Stand des Pakets in der Tabelle
am Ende der Design-Datei nachtragen. Die Workflow-Skripte mit den Prompts liegen unter
`C:\Users\bartl\.claude\projects\C--Users-bartl-AppData-Local-nvim--claude-worktrees-nvim-plugin-cleanup-20ecd9\be9b5351-70a2-44d9-ac54-cfb498f312b0\workflows\scripts\`
(`openinnvim-native-p1-core-*.js` usw.; der Resume-Cache gilt nur in der alten Sitzung, die Prompts
sind aber wiederverwendbar). Die Prototypen der Reviewer (`oin-proto.cs`, `measure.ps1`, Fake-Pipe-
Server) lagen im Scratchpad jener Sitzung und sind danach weg; der Bericht beschreibt sie.

Die neotest-Lösung ("Option E") ist davon unabhängig; sie steht im neotest-Handover der nvim-config.

---

## Offen und Nachfrage

- [ ] **openinnvim: nativer Launcher, Pakete 1–5** (siehe oben und die Design-Datei im WKDBook).
- [ ] **`install.ps1` ausführen und den echten Klick im Explorer abnehmen** — **erst nach Paket 3**
      (neue `install.ps1`, baut die exe). Die Final-Checks-Liste wird in Paket 5 auf den neuen
      Launcher umgeschrieben; die heutige Fassung beschreibt noch die VBS + PowerShell-Kette.
- [ ] **Fokus** (`FOCUS_TERMINAL`) von Hand prüfen, nach Paket 2: nur der Win32-Teil braucht ein
      echtes Fenster. Danach entscheiden: opt-in lassen oder Standard.
- [x] Unabhängiger Blick auf `openinnvim` `d0d1a5d`: durch die Review-Runde vom 2026-10-03 erledigt
      (Bericht; die Funde fließen in den nativen Launcher).
- [ ] openinnvim: Setup-`.exe`-Installer (Inno Setup, GitHub Actions) — nach Paket 5; liefert dann
      die fertig gebaute `OpenInNvim.exe` mit. Details in der ROADMAP im WKDBook.
- [ ] GitHub-Beschreibung und Topics von `openinnvim` setzen (`NEW-04`, `NEW-05`); `stylua.toml`,
      `.luacheckrc`, CI-Workflow.
- [ ] Aufräumen (optional): User-Variable `NVIM_VBS` zeigt auf ein nicht existierendes
      Verzeichnis und wird nirgends gelesen.

---

## Commits dieses Chats

✅ = durch den ultracode-Review (Reasoning-Stufe `ultracode`, vom Nutzer so gestellt)
abgenommen oder reine Doku.

| Repository | Commit | Beschreibung |
| --- | --- | --- |
| nvim-config | `afe3cee4` ✅ | docs(roadmap): Konkurrenzanalyse abgehakt, drei Reports verlinkt |
| Configs | `f02220f` ✅ | docs: Verweise auf das umbenannte Repo `openinnvim` |
| nvim-config | `0d3ba109` ✅ | docs(handover): NVIM_LISTEN_ADDRESS, neotest-Listener und openinnvim |
| openinnvim | `b5aa51d` ✅ | docs(readme): neuer Repo-Pfad, sichere Junction-Entfernung |
| nvim-config | `e5075b1d` ✅ | docs(handover): Reparatur, PID-Pipe-Suche, Filetree-Plan |
| openinnvim | `28d358c` ✅ | feat(current): Instanzen über Standard-Pipes finden, `:silent`, Fix `(c)`, Tests |
| openinnvim | `41c399f` ✅ | feat(current): Ordner in filetree.nvim (Review fand den `fnameescape`-Fehler, behoben in `9eb8c7e`) |
| openinnvim | `a8698cb` ✅ | fix(ps51): `?:` in verify.ps1 und `"$key:"` in install-context.ps1 |
| openinnvim | `9eb8c7e` ✅ | fix(launchers): Review-Fixes (RPC-Öffnen, verlorenes `$args`, Pfad-Escaping, Tempo); zweiter Blick fand den Pipe-Fehlfall, behoben in `d0d1a5d` |
| nvim-config | `3c01f438` ✅ | docs(handover): Tests grün, Filetree-Ordner |
| nvim-config | `76f5ca5b` ✅ | docs(handover): Review-Ergebnisse |
| openinnvim | `99946e2` ✅ | docs: Standard-README + `docs/`-Struktur, MIT-Lizenz; `nvr` ganz entfernt (zweiter Blick: ok) |
| openinnvim | `d0d1a5d` | feat(install): `install.ps1`/`uninstall.ps1`, relative VBS-Pfade, opt-in Fokus, zweiter Review (Pipe-Fehlfall 3,4 s → 0,4 s); 104 Prüfungen. **Kein Haken**: neuer Code, noch nicht unabhängig geprüft |
| WKDBooks | `1767d31`, `107d316` ✅ | docs(openinnvim): neues Buch mit Backlog und Roadmap; Index-Zeile |
| nvim-config | `82acfb17` ✅ | docs(handover): schlank, Erledigtes ins WKDBook; Live-Test-Checkliste |
| WKDBooks | `9cd608a` ✅ | docs(openinnvim): Installer, Fokus, zweiter Review ins Backlog; Roadmap gekürzt |
| nvim-config | `83f73c2c` ✅ | docs(handover) und Live-Test-Checkliste: Installation per `install.ps1`, Fokus-Test |
| nvim-config | `622d9ff1` ✅ | docs(handover): neotest-Listener, Teilergebnis des Workflows (Code gelesen, Laufzeittest offen) |
| WKDBooks | `3251163` ✅ | docs(tools): neotest-run-probe (Runner, Treiber, Rezept) mit den zwei Windows-Befunden |
| nvim-config | `8df382d4` ✅ | docs(handover): neotest unter Windows — Läufe scheitern, Prototyp-Fix, Entscheidung |
| nvim-config | `e666a6c9` ✅ | docs(handover, report): Review-Runde unterbrochen; 31 ungeprüfte Fundstellen als Bericht, Option E für neotest als Plan |
| WKDBooks | `57f3507` ✅ | docs(openinnvim): Design des nativen Launchers, Paketplan |
| nvim-config | `a7f8fcc2` ✅ | docs(handover): Entscheidung für den kompilierten Launcher, Paketplan, Abbruch-Anleitung |
| openinnvim | `b2f8b90` | feat(native): Kern für `current`. **Kein Haken**: Review abgebrochen |
| openinnvim | `9db2279` | feat(native): neue Instanz, Chooser, Fokus. **Kein Haken**: ohne Review |
| openinnvim | `5dede04` | feat(install)!: Installer baut die exe, alte Kette entfernt. **Kein Haken**: ohne Review |
| WKDBooks | `1c04d69` ✅ | docs(openinnvim): Paketstand 1–3 |
| openinnvim | `073f70d` ✅ | docs: Repo-Docs für den kompilierten Launcher, Roadmap |
| nvim-config | `95b53c6e` ✅ | docs(handover): Stand nach den Paketen 1–4, Verworfenes, lokale Änderungen, Offenes |
| openinnvim | `7cdc4af` | fix(native): `NVIM_BIN` nie relativ zum angeklickten Ordner, Fokus einmal je Klick. **Kein Haken**: ohne Review |
| nvim-config | `94e73d0c` ✅ | docs(handover): Funde aus dem Docs-Abgleich |
| openinnvim | `b752940` | fix(install): Explorer über geänderte Einträge informieren. **Kein Haken**: ohne Review |
| openinnvim | `c9976bd` | fix(spawn): vollständiger `PATH` aus der Registry. **Kein Haken**: ohne Review |
| openinnvim | `cbfe2be` | test: PATH-Merge-Prüfung repariert |
| nvim-config | `22e51c40` ✅ | docs(handover): Klick bestätigt, Explorer-Cache und abgeschnittener PATH |
| openinnvim + nvim-config | (dieser Commit) ✅ | docs: Handover ins openinnvim-Repo verschoben, Verweise angepasst, PATH entrümpelt |

Zusätzlich ohne Commit: GitHub-Repo `open-in-nvim` umbenannt in `openinnvim`, Klon nach
`E:\repos\openinnvim`; Junction `C:\tools\OpenInNvim` umgesetzt (kein Git).

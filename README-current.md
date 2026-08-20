Zielbild und Architektur

* Neovim stellt eine RPC-Schnittstelle bereit (MessagePack-RPC). Eine laufende Instanz kann als „Server“ an einer Adresse (Unix-Socket, TCP oder unter Windows: Named Pipe) lauschen. Andere Prozesse („Clients“) verbinden sich dorthin und senden Requests/Benachrichtigungen (z. B. „öffne Datei“, „führe Ex-Befehl aus“). ([Neovim][1])
* Für die „current instance“ nutzt man genau diese Serveradresse. Gibt es eine erreichbare Instanz, sendet man Remote-Befehle; gibt es keine, startet man eine neue Instanz und lässt sie an einer bekannten Adresse lauschen. ([Neovim][2])

Transport, Adressierung, Serverlebenszyklus

* Adresse setzen beim Start: `nvim --listen {addr}` startet einen Server und setzt die Serveradresse (`v:servername`). Unter Windows empfiehlt sich eine Named Pipe wie `\\.\pipe\nvim-<USERNAME>`. Auf Unix sind es i. d. R. Sockets unter `$XDG_RUNTIME_DIR`. ([Neovim][2])
* Serverstatus in Neovim prüfen: `:echo v:servername`. Alle bekannten Server (aus Sicht von Vimscript) liefert `:echo serverlist()`. Programmgesteuert kann man in Lua/Vimscript per `serverstart({addr})` bzw. `serverstop({addr})` dynamisch starten/stoppen. ([Neovim][3])
* Umgebungsvariablen: `NVIM_LISTEN_ADDRESS` war historisch gebräuchlich, ist heute in Neovim als Mittel zum Setzen/Ermitteln „deprecated“; stattdessen nutzt man `--listen`, `serverstart()` und `v:servername`. Für von Neovim gestartete Jobs/Terminals setzt Neovim `$NVIM` automatisch auf die Server-Adresse des Eltern-Nvim; `$NVIM_LISTEN_ADDRESS` ist beim Start explizit „unset“. ([Neovim][4])

Client-Seite: eingebaute Neovim-CLI vs. nvr

* Neovim hat eingebaute Client-Optionen (Kompatibilität zu Vims clientserver). Wichtig:
  `--server {addr}` Zieladresse setzen
  `--remote {files...}` Dateien in der Remote-Instanz öffnen (entspricht `:drop`)
  `--remote-send {keys}` Tastensequenz in der Remote-Instanz ausführen
  `--remote-expr {expr}` Ausdruck in der Remote-Instanz evaluieren
  `--remote-ui` UI der Remote-Instanz im aktuellen Terminal „durchtunneln“
  `--listen {addr}` lokalen Server starten
  Nicht unterstützt in Neovim: `--servername`, `--serverlist`, alle „wait“-Varianten (Stand der offiziellen Doku). ([Neovim][2])
* neovim-remote (nvr) ist ein schlanker CLI-Client in Python, der Vim-artige Optionen bereitstellt und Komfortfunktionen mitbringt. Relevante Optionen:
  `--servername {addr}` Zielserver wählen
  `--serverlist` bekannte Serveradressen listen
  `--remote {files...}`, `--remote-send`, `--remote-expr` analog zu Vim
  nvr ergänzt also bewusst Lücken, die Neovim selbst (noch) nicht abdeckt. ([GitHub][5])

Wie „current instance“ technisch funktioniert (schrittweise)

1. Ermitteln/entscheiden, welche Serveradresse verwendet wird. Varianten:
   a) Fix aus Konfiguration (z. B. `\\.\pipe\nvim-%USERNAME%`).
   b) Auto-Discovery per `nvr --serverlist` (falls nvr installiert).
   c) Fallback auf ein konventionelles Schema (z. B. `\\.\pipe\nvim-%USERNAME%`). ([GitHub][5])
2. Wenn eine Adresse vorliegt, versucht man, Remote-Befehle zu senden:
   a) Mit nvr: `nvr --servername <addr> --remote "<file>"` für Dateien; für Ordner: `--remote-send` mit `:cd` + `:edit .`.
   b) Ohne nvr direkt mit Neovim: `nvim --server <addr> --remote "<file>"` oder `--remote-send '<C-\><C-n>:cd ... | edit .<CR>'`. Wichtig: `--remote` „frisst“ den Rest der Kommandozeile als Dateiliste; Optionen müssen davor stehen. ([Neovim][2])
3. Schlagen Remote-Versuche fehl (kein Server erreichbar), startet man eine neue Instanz mit `--listen <addr>` und (optional) der Datei als letztem Argument. So etabliert man die „current“-Instanz für künftige Aufrufe. ([Neovim][2])

Was in Neovim intern passiert (RPC-Ebene)

* Neovim exponiert eine klar definierte API über MessagePack-RPC (Requests, Responses, Notifications). Beispiele:
  `nvim_command("edit foo")` führt einen Ex-Befehl aus,
  `nvim_eval("expand('%:p')")` evaluiert einen Vimscript-Ausdruck,
  `nvim_buf_set_lines(...)` modifiziert Buffer-Inhalte,
  `rpcnotify(0, "event", payload)` sendet asynchron ein Event an Plugins/UIs.
  nvr/neovim-CLI verpacken letztlich genau solche RPC-Aufrufe/Key-Events. ([Neovim][6])
* Remote-UI und Remote-Plugins sind Spezialfälle desselben RPC-Kanals:
  `--remote-ui` macht den Client zu einer UI, die Screen-Updates/Inputs über RPC austauscht.
  Remote-Plugins (z. B. Python via `pynvim`) laufen out-of-process und sprechen die gleiche API. ([Neovim][2])

Windows-Spezifika

* Transport ist eine Named Pipe (`\\.\pipe\…`). Berechtigungen folgen den Windows-ACLs der Pipe; standardmäßig ist die Pipe lokal-host-weit sichtbar, nicht netzwerkweit.
* Quoting ist heikel: Pfade und `--remote-send`-Strings müssen korrekt gequotet werden (Doppelte Anführungszeichen in der Shell; in Vimscript-Strings Einzelquotes verdoppeln; für Dateinamen `fnameescape()` benutzen). Unser „current“-Skript baut dafür gezielt `:execute 'cd ' . fnameescape('…') | edit …`. ([Neovim][2])

Rollen von v:servername, NVIM_LISTEN_ADDRESS, $NVIM

* `v:servername`: die tatsächliche, von Neovim gesetzte Serveradresse der Instanz; immer die verlässliche Quelle im Editor. ([Neovim][3])
* `NVIM_LISTEN_ADDRESS`: früher gängige Variable, heute „deprecated“ für Set/Read; stattdessen `--listen`/`serverstart()` verwenden. Sie ist beim Start explizit „unset“ (kann aber gezielt an Jobs/Terminals durchgereicht werden). ([Neovim][4])
* `$NVIM`: Neovim setzt diese Variable für gestartete Jobs auf den Wert von `v:servername`. Damit kann ein innerhalb von Neovim gestarteter Prozess (z. B. ein Build-Tool) sofort zum „Mutter-Nvim“ verbinden, ohne Adresse zu kennen. ([Neovim][7])

Warum nvr trotz eingebauter Optionen oft praktischer ist

* Neovim selbst bietet `--server/--remote/--remote-send`, aber nicht `--servername/--serverlist`. nvr liefert diese Komfort-Features nach und ist im Alltag bequemer, um „die eine richtige“ Instanz zu finden, ohne harte Pfadangaben oder eigene Discovery-Logik. ([Neovim][2])

Beispiele und typische Aufrufe

* Server deterministisch starten (Windows, stabile Pipe):

```
nvim --listen \\.\pipe\nvim-%USERNAME%
```

* Datei in bestimmte Instanz öffnen (Neovim-CLI):

```
nvim --server \\.\pipe\nvim-%USERNAME% --remote "C:\Path With Spaces\foo.txt"
```

* In bestehender Instanz in ein Verzeichnis wechseln und NetRW anzeigen:

```
nvim --server \\.\pipe\nvim-%USERNAME% --remote-send "<C-\><C-n>:execute 'cd ' . fnameescape('C:\Path With Spaces') | edit .<CR>"
```

* Mit nvr zur „current“ verbinden (komfortabel):

```
nvr --servername \\.\pipe\nvim-%USERNAME% --remote "C:\Path With Spaces\foo.txt"
nvr --serverlist
```

* Aus Neovim heraus an Eltern-Nvim senden (Job erbt $NVIM):

```
nvr --remote-send "<C-\><C-n>:write<CR>"
```

([Neovim][2])

Fehlerbilder und Diagnose

* „Nichts passiert“ beim Kontextmenü „current“: kein erreichbarer Server. Prüfen mit
  `:echo v:servername` in Neovim und `nvr --serverlist` (falls nvr vorhanden). Ohne Treffer neue Instanz mit `--listen` starten oder init.lua per `serverstart()` konfigurieren. ([Neovim][2])
* nvr meldet „ambiguous option: --server“: nvr nutzt `--servername`, nicht `--server`. Korrekt ist z. B.:
  `nvr --servername \\.\pipe\nvim-%USERNAME% --remote file.txt`. ([GitHub][5])
* `--remote` konsumiert die restliche Kommandozeile als Dateiliste; zusätzliche Optionen müssen davor stehen. Bei Bedarf stattdessen `--remote-send` mit einem zusammengesetzten Ex-Befehl verwenden. ([Neovim][2])

Sichere Implementierungsdetails im Skriptkontext

* Adresswahl: erst Konfigurationswert, dann `nvr --serverlist`, zuletzt heuristische Default-Pipe `\\.\pipe\nvim-%USERNAME%`.
* Senden: wenn nvr vorhanden, bevorzugt `--remote`/`--remote-send`; sonst Neovim-CLI mit `--server/--remote`/`--remote-send`.
* Quoting: Windows-Argumente immer doppelt quoten, innerhalb von Vimscript Einzelquotes verdoppeln und `fnameescape()` verwenden; Tastensequenzen beginnen mit `<C-\><C-n>` um sicher Normal-Mode zu erzwingen. ([Neovim][2])

Zusammenfassung der Schnittstellen

* Editorseitige API: MessagePack-RPC mit Funktionen wie `nvim_command`, `nvim_eval`, Buffer-/Window-/Tabpage-Operationen; per CLI verkapselt über `--remote*`/`--server` oder via nvr. ([Neovim][6])
* Start/Adresse: `--listen`, `serverstart()`, `v:servername`, `serverlist()`. ([Neovim][2])
* Clienttools: Neovim-CLI (kein `--servername/--serverlist`), nvr (liefert diese). ([Neovim][2])

Damit ist präzise nachvollziehbar, wie die „current instance“-Kommunikation funktioniert, welche Flags/Kommandos es gibt, wie Discovery/Quoting sauber umgesetzt wird und wo nvr vs. Neovim-CLI jeweils ihre Stärken haben.

[1]: https://neovim.io/doc/user/dev_arch.html?utm_source=chatgpt.com "Dev_arch - Neovim docs"
[2]: https://neovim.io/doc/user/remote.html " Remote - Neovim docs"
[3]: https://neovim.io/doc/user/starting.html?utm_source=chatgpt.com "Starting - Neovim docs"
[4]: https://neovim.io/doc/user/deprecated.html?utm_source=chatgpt.com "Deprecated - Neovim docs"
[5]: https://github.com/mhinz/neovim-remote?utm_source=chatgpt.com "mhinz/neovim-remote: :ok_hand: Support for"
[6]: https://neovim.io/doc/user/api.html?utm_source=chatgpt.com "Api - Neovim docs"
[7]: https://neovim.io/doc/user/builtin.html?utm_source=chatgpt.com "Builtin - Neovim docs"


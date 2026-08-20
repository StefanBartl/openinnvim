# OpenInNvim-Roadmap

## Docs

1. Erstellen einer `README.md`-File mit Anleitung

## Projektstruktur

1. Eigentlich wäre folgende Struktur korrekt:

```sh
/OpenInNvim
/OpenInNvim/Contextmenu
/OpenInNvim/Contextmenu/...
/OpenInNvim/DefaultApps
/OpenInNvim/DefaultApps/install-icons-for-progid.ps1 & file-extensions.ps1
/OpenInNvim/DefaultApps/Logos/current-session.ico & new-session.ico
/OpenInNvim/DefaultApps/Launcher/TinyLauncher.csproj & Program.cs & deploy-open-in-nvim,.ps1 &
```

## DefaultApps

1. `file-extensions.ps1` soll in `installs-for-progid.ps1` verwendet werden
2. Bug: Für "New Instance" wird weder ein Logo noch der korrekte Text Angezeigt, sondern nue "Microsdoft WIndows Based Script Host" angezeigt

--

## Ablauf

Bisheriger Ablauf:
1. Ausführen von `/register-nvim-default-app.ps1`
2. Ausführen von `install-icons-for-progid.ps1`
    2.a) Sicherstellen, dass Program.cs ausgeführt und die EXE-Files gebaut worden sind
    2.b) Sicherstellen, dass die Logos vorhanden sind
3. Auführen von `/deploy-open-in-nvim.ps1`

Wenn möglich sollte folgendes verbessert werden:
    - Die Schritte sollten alle in einem Skript ausgeführt werden
    - Bezüglich dem builden der EXE-Files wäre es weitaus besser wenn man eine Lösung finden würde, die portabel auf auf verschiedenen modernen Windows Versionen bzw. Hardware-Systemen funktionert. Wenn das nicht möglich ist, sollte im obigen Skriopt die Hardware und OS-Kompoenten ermittelt werden um entsprechend korrekte EXE-Files generieren zu können - automatisch. Berüksichtigt sollen alle Windows-Versionen werden die problemlos bearbeitet werden können in dieser Lösung, jednefalls abere das aktuelle Windows auf den wichtigsten Architekturen.

--

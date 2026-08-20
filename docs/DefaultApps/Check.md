
Prüfen, ob die RegisteredApplications-Einträge vorhanden sind (korrekt):

```powershell
# Get RegisteredApplications properties and filter for entries that contain "Neovim.TextFile"
# This reliably lists any RegisteredApplications entries referencing the Neovim progids.
$reg = Get-ItemProperty -Path "HKCU:\Software\RegisteredApplications" -ErrorAction SilentlyContinue
$reg.PSObject.Properties | Where-Object { $_.Value -match 'Neovim.TextFile' -or $_.Name -match 'Neovim.TextFile' } | Select-Object Name, Value
```

Prüfen, ob beide ProgIDs Capabilities und DefaultIcon/Open-Command gesetzt haben:

```powershell
# Check capabilities exist for both progids
Get-ItemProperty -Path "HKCU:\Software\Neovim.TextFile.New\Capabilities" -ErrorAction SilentlyContinue
Get-ItemProperty -Path "HKCU:\Software\Neovim.TextFile.Current\Capabilities" -ErrorAction SilentlyContinue

# Show DefaultIcon and Open command keys for both ProgIDs
Get-ItemProperty -Path "HKCU:\Software\Classes\Neovim.TextFile.New\DefaultIcon" -ErrorAction SilentlyContinue
Get-ItemProperty -Path "HKCU:\Software\Classes\Neovim.TextFile.Current\DefaultIcon" -ErrorAction SilentlyContinue
Get-ItemProperty -Path "HKCU:\Software\Classes\Neovim.TextFile.New\shell\open\command" -ErrorAction SilentlyContinue
Get-ItemProperty -Path "HKCU:\Software\Classes\Neovim.TextFile.Current\shell\open\command" -ErrorAction SilentlyContinue
```

Prüfen, ob Capabilities\FileAssociations für beide ProgIDs Einträge haben:

```powershell
# List file associations recorded under each progid (may be many)
Get-ItemProperty -Path "HKCU:\Software\Neovim.TextFile.New\Capabilities\FileAssociations" -ErrorAction SilentlyContinue
Get-ItemProperty -Path "HKCU:\Software\Neovim.TextFile.Current\Capabilities\FileAssociations" -ErrorAction SilentlyContinue
```

Prüfen auf UserChoice (kann Anzeige/Zuordnungen überschreiben):

```powershell
# Inspect UserChoice for .txt and .md as representative examples
Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.txt\UserChoice" -ErrorAction SilentlyContinue
Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.md\UserChoice"  -ErrorAction SilentlyContinue
```

Sofort reparieren / sicherstellen: kleines, idempotentes Repair-Script — setzt RegisteredApplications, DefaultIcon und Open-Command falls nötig. Ausführen wenn man möchte:

```powershell
# repair-neovim-progids.ps1
# Ensures RegisteredApplications entries exist and that both ProgIDs have DefaultIcon, Open command and minimal Capabilities.
param(
    [string]$InstallDir = "$env:LOCALAPPDATA\OpenInNvim"   # adjust if installed elsewhere
)

# Fail fast
$ErrorActionPreference = 'Stop'

# Paths used for registry values (adjust if real paths differ)
$exeNew  = Join-Path $InstallDir 'tiny-launcher-new.exe'
$exeCurr = Join-Path $InstallDir 'tiny-launcher-current.exe'
$iconNew = Join-Path $InstallDir 'Logos\new-session.ico'
$iconCurr= Join-Path $InstallDir 'Logos\current-session.ico'

# Ensure RegisteredApplications entries exist
New-ItemProperty -Path "HKCU:\Software\RegisteredApplications" -Name "Neovim.TextFile.New" -Value "Software\Neovim.TextFile.New\Capabilities" -PropertyType String -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\RegisteredApplications" -Name "Neovim.TextFile.Current" -Value "Software\Neovim.TextFile.Current\Capabilities" -PropertyType String -Force | Out-Null

# Helper to create minimal progid keys (DefaultIcon, open command, Capabilities)
function Ensure-ProgId {
    param($progId, $displayName, $iconPath, $openExe)
    $pidKey = "HKCU:\Software\Classes\$progId"
    New-Item -Path $pidKey -Force | Out-Null
    New-ItemProperty -Path $pidKey -Name '(default)' -Value $displayName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $pidKey -Name 'FriendlyAppName' -Value $displayName -PropertyType String -Force | Out-Null

    $iconKey = "$pidKey\DefaultIcon"
    New-Item -Path $iconKey -Force | Out-Null
    if (Test-Path $iconPath) {
        New-ItemProperty -Path $iconKey -Name '(default)' -Value $iconPath -PropertyType String -Force | Out-Null
    }

    $cmdKey = "$pidKey\shell\open\command"
    New-Item -Path $cmdKey -Force | Out-Null
    if (Test-Path $openExe) {
        $openCmd = "`"$openExe`" `"%1`""
        New-ItemProperty -Path $cmdKey -Name '(default)' -Value $openCmd -PropertyType String -Force | Out-Null
    }

    $capKey = "HKCU:\Software\$progId\Capabilities"
    New-Item -Path $capKey -Force | Out-Null
    New-ItemProperty -Path $capKey -Name 'ApplicationName' -Value $displayName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $capKey -Name 'ApplicationDescription' -Value 'Texteditor basierend auf Neovim' -PropertyType String -Force | Out-Null
    New-Item -Path "$capKey\FileAssociations" -Force | Out-Null
}

# Ensure both progids
Ensure-ProgId -progId 'Neovim.TextFile.New'     -displayName 'Neovim (new instance)'     -iconPath $iconNew  -openExe $exeNew
Ensure-ProgId -progId 'Neovim.TextFile.Current' -displayName 'Neovim (current instance)' -iconPath $iconCurr -openExe $exeCurr

# Optionally, add some common extensions to both Capabilities so they appear more obviously in Settings
$extList = @('.txt','.md','.lua','.py','.js')
foreach ($ext in $extList) {
    New-ItemProperty -Path "HKCU:\Software\Neovim.TextFile.New\Capabilities\FileAssociations" -Name $ext -Value 'Neovim.TextFile.New' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path "HKCU:\Software\Neovim.TextFile.Current\Capabilities\FileAssociations" -Name $ext -Value 'Neovim.TextFile.Current' -PropertyType String -Force | Out-Null
}

# Restart explorer to refresh icons/settings cache (optional)
Stop-Process -Name explorer -Force
Start-Process explorer

Write-Host "Repair finished. Open Settings -> Apps -> Default apps and search 'Neovim' to verify both entries."
```

Was zu erwarten ist / zusätzliche Hinweise

* Nach Reparatur und Restart des Explorers sollte Settings → Apps → Default apps beide Einträge anzeigen (weil jetzt RegisteredApplications auf beide ProgIDs verweist und beide Capabilities/FileAssociations Einträge vorhanden sind).
* Falls weiterhin nur eine erscheint, dann existiert sehr wahrscheinlich ein `UserChoice`-Eintrag für viele Extensions, der Windows veranlasst, nur die bereits gesetzte App prominent zu zeigen — das kann man für Tests temporär entfernen (siehe vorherige Nachricht), aber das verändert Benutzerpräferenzen.
* Windows cache kann sich störrisch verhalten; Ab-/Anmelden oder einmaliges manuelles Zuweisen via Settings («Öffnen mit» → «Andere App auswählen» → «Immer diese App verwenden») hilft oft.

Wenn gewünscht, erzeugen/ausführen:

* a) das obige `repair-neovim-progids.ps1` direkt (Passe `$InstallDir` an wenn Install-Path anders ist) — ich kann das Skript hier noch anpassen und komplett als Datei ausgeben.
* b) eine kleine Checkliste, die schrittweise sagt, welche Schlüssel/Values genau erwartet werden (falls man lieber manuell prüft).

Soll ich das Repair-Skript hier als Datei fertig ausgeben (komplett) oder direkt die einzelnen Prüf-Commands nacheinander ausführen lassen?

# register-nvim-default-app.ps1
# Registers Neovim as default application for many text file extensions on Windows.
# English comments are used throughout as requested.

param(
    [string]$InstallPath = $PSScriptRoot
)

# Stop on first error to avoid partial registry changes.
$ErrorActionPreference = 'Stop'

# If the script is executed interactively (e.g. pasted into console) $PSScriptRoot may be null.
# Ensure InstallPath has a sensible fallback to the current working directory.
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    # Use the Path property when $PWD is a PathInfo object.
    $InstallPath = (Get-Location).ProviderPath
}

# --- USER PROMPT FOR MODE ---
$Mode = ''
while ($true) {
    Clear-Host

    # Present options to the user
    Write-Host "Möchtest du 'new Instance' oder 'Current Session' als Standardapp registrieren?" -ForegroundColor Yellow
    Write-Host " 1) New Instance  (Öffnet Dateien immer in einem neuen Neovim-Fenster)"
    Write-Host " 2) Current Session (Versucht, Dateien in einer laufenden Instanz zu öffnen)"

    # Read user input. Trim to remove stray whitespace.
    $choice = (Read-Host "Bitte wähle 1 oder 2").Trim()

    # Use explicit comparisons with if/elseif to avoid confusion about break semantics inside switch.
    if ($choice -eq '1') {
        $Mode = 'new'
        break    # This break exits the while loop (explicit and unambiguous).
    } elseif ($choice -eq '2') {
        $Mode = 'current'
        break    # Same here.
    } else {
        # If input is invalid, show error and loop again.
        Write-Host "`nUngültige Eingabe. Bitte gib nur 1 oder 2 ein." -ForegroundColor Red
        Start-Sleep -Seconds 2
        continue
    }
}
# --- END USER PROMPT ---

# Determine which VBS script to use based on chosen mode.
$vbsScript = if ($Mode -eq 'new') {
    Join-Path $InstallPath 'open-in-nvim.vbs'
} else {
    Join-Path $InstallPath 'open-in-nvim-current.vbs'
}

# Validate that the VBS file exists before attempting to write registry entries.
if (-not (Test-Path -LiteralPath $vbsScript)) {
    throw "VBS script not found: $vbsScript"
}

# ProgID and display name
$progId = "Neovim.TextFile"
$appName = if ($Mode -eq 'new') { "Neovim (new instance)" } else { "Neovim (current instance)" }

# Icon and command. Use full paths and quote arguments properly.
$nvimIcon = "C:\Program Files\Neovim\bin\nvim.exe,0"
$wscript = "wscript.exe"
$command = "$wscript //nologo `"$vbsScript`" `"%1`""

Write-Host "`nRegistriere Neovim als Standardanwendung..."
Write-Host "Gewählter Modus: $appName"

# 1) Create/update ProgID
$progIdPath = "HKCU:\Software\Classes\$progId"
New-Item -Path $progIdPath -Force | Out-Null
New-ItemProperty -Path $progIdPath -Name '(default)' -Value $appName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $progIdPath -Name 'FriendlyAppName' -Value $appName -PropertyType String -Force | Out-Null

# 2) Icon
$iconPath = "$progIdPath\DefaultIcon"
New-Item -Path $iconPath -Force | Out-Null
New-ItemProperty -Path $iconPath -Name '(default)' -Value $nvimIcon -PropertyType String -Force | Out-Null

# 3) Open command
$commandPath = "$progIdPath\shell\open\command"
New-Item -Path $commandPath -Force | Out-Null
New-ItemProperty -Path $commandPath -Name '(default)' -Value $command -PropertyType String -Force | Out-Null

# 4) Registered app capabilities for Default Apps UI
$capabilitiesPath = "HKCU:\Software\$progId\Capabilities"
New-Item -Path $capabilitiesPath -Force | Out-Null
New-ItemProperty -Path $capabilitiesPath -Name 'ApplicationName' -Value $appName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $capabilitiesPath -Name 'ApplicationDescription' -Value "Texteditor basierend auf Neovim" -PropertyType String -Force | Out-Null

# 5) File associations list
$fileAssocsPath = "$capabilitiesPath\FileAssociations"
New-Item -Path $fileAssocsPath -Force | Out-Null

$extensions = @(
    # --- Text, Dokumentation & Daten ---
    '.txt', '.md', '.markdown',
    '.csv', '.log',

    # --- Web-Entwicklung (Frontend & Backend) ---
    '.html', '.htm', '.css', '.scss', '.sass', '.less',
    '.js', '.mjs', '.cjs',           # JavaScript (Module, CommonJS)
    '.ts', '.mts', '.cts',           # TypeScript (Module, CommonJS)
    '.jsx', '.tsx',                  # React/JSX
    '.json', '.jsonc', '.geojson',   # JSON & Varianten
    '.php',

    # --- Skript- und Allzwecksprachen ---
    '.py', '.pyw', '.pyi',           # Python, Python Windowed, Stubs
    '.rb',                           # Ruby
    '.lua',                          # Lua

    # --- Kompilierte Sprachen & Systemprogrammierung ---
    '.c', '.h', '.cpp', '.hpp', '.cc', '.cxx', '.hh', # C & C++
    '.rs',                           # Rust
    '.go',                           # Go
    '.zig',                          # ZIG
    '.asm', '.s',                    # Assembly
    '.java', '.kt', '.kts', '.gradle', # Java, Kotlin, Gradle
    '.cs', '.csproj',                # C#
    '.swift',                        # Swift
    '.wat',                          # WebAssembly Text Format

    # --- Shell & Terminal-Skripte ---
    '.ps1', '.psm1', '.psd1',         # PowerShell
    '.sh', '.bash', '.zsh', '.fish',   # *nix Shells
    '.bat', '.cmd',                  # Windows Batch

    # --- Konfiguration & Datenformate ---
    '.yaml', '.yml',
    '.xml', '.xsl', '.xslt', '.svg',  # XML-basierte Formate
    '.toml',
    '.ini', '.conf', '.config', '.env', '.properties',

    # --- Datenbanken & Vorlagen ---
    '.sql',
    '.graphql', '.gql',
    '.tpl', '.hbs', '.ejs',          # Template-Engines

    # --- Editor, Build-System & Versionskontrolle ---
    '.vim', '.vimrc',
    '.diff', '.patch'
)

foreach ($ext in $extensions) {
    # Ensure extension key is created with a safe value.
    New-ItemProperty -Path $fileAssocsPath -Name $ext -Value $progId -PropertyType String -Force | Out-Null
}

# 6) Register in RegisteredApplications so Windows shows it in Settings -> Default apps
$regAppsPath = "HKCU:\Software\RegisteredApplications"
if (-not (Test-Path $regAppsPath)) {
    New-Item -Path $regAppsPath -Force | Out-Null
}
New-ItemProperty -Path $regAppsPath -Name $progId -Value "Software\$progId\Capabilities" -PropertyType String -Force | Out-Null

Write-Host "`nRegistrierung abgeschlossen!" -ForegroundColor Green
Write-Host "`nNächste Schritte:"
Write-Host "1. Öffne: Einstellungen -> Apps -> Standard-Apps"
Write-Host "2. Suche nach: $appName"
Write-Host "3. Wähle die Dateitypen aus, für die Neovim standard sein soll"
Write-Host "`nAlternativ: Rechtsklick auf eine Datei -> Öffnen mit -> Andere App auswählen -> '$appName'"
Write-Host "            und 'Immer diese App verwenden' aktivieren"








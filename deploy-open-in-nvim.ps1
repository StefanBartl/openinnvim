# deploy-openinnvim.ps1
# Deploy both launcher EXEs, VBS scripts and icons to an install directory
# and configure per-user ProgIDs so both "Neovim (new instance)" and
# "Neovim (current instance)" are registered.
#
# English comments inside the script per request. Script uses HKCU (per-user).
param(
    [string]$SourceRoot = $PSScriptRoot,
    [string]$InstallDir  = "$env:LOCALAPPDATA\OpenInNvim"  # default per-user install path to avoid UAC
)

# Fail fast on error.
$ErrorActionPreference = 'Stop'

# Normalize paths
$SourceRoot = (Resolve-Path -Path $SourceRoot).Path
$InstallDir  = $InstallDir.TrimEnd('\','/')

# Define expected build outputs relative to SourceRoot
$pubNewExe     = Join-Path $SourceRoot 'publish\new\tiny-launcher-new.exe'
$pubCurrentExe = Join-Path $SourceRoot 'publish\current\tiny-launcher-current.exe'
$vbsNew        = Join-Path $SourceRoot 'open-in-nvim.vbs'
$vbsCurrent    = Join-Path $SourceRoot 'open-in-nvim-current.vbs'
$logosDirSrc   = Join-Path $SourceRoot 'Logos'
$newIconSrc    = Join-Path $logosDirSrc 'new-session.ico'
$currentIconSrc= Join-Path $logosDirSrc 'current-session.ico'

# Validate source files exist
if (-not (Test-Path -LiteralPath $pubNewExe))    { throw "Missing: $pubNewExe" }
if (-not (Test-Path -LiteralPath $pubCurrentExe)){ throw "Missing: $pubCurrentExe" }
if (-not (Test-Path -LiteralPath $vbsNew))       { throw "Missing: $vbsNew" }
if (-not (Test-Path -LiteralPath $vbsCurrent))   { throw "Missing: $vbsCurrent" }
if (-not (Test-Path -LiteralPath $newIconSrc))   { throw "Missing: $newIconSrc" }
if (-not (Test-Path -LiteralPath $currentIconSrc)){ throw "Missing: $currentIconSrc" }

# Create install dir
New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null

# Copy files (preserve distinct filenames to avoid accidental overwrite)
Copy-Item -Path $pubNewExe     -Destination $InstallDir -Force
Copy-Item -Path $pubCurrentExe -Destination $InstallDir -Force
Copy-Item -Path $vbsNew        -Destination $InstallDir -Force
Copy-Item -Path $vbsCurrent    -Destination $InstallDir -Force

# Copy logos
$logosDest = Join-Path $InstallDir 'Logos'
New-Item -Path $logosDest -ItemType Directory -Force | Out-Null
Copy-Item -Path $newIconSrc     -Destination $logosDest -Force
Copy-Item -Path $currentIconSrc -Destination $logosDest -Force

# Define ProgIDs and friendly names
$progIdNew     = 'Neovim.TextFile.New'
$progIdCurrent = 'Neovim.TextFile.Current'
$displayNew    = 'Neovim (new instance)'
$displayCurrent= 'Neovim (current instance)'

# Compose paths for exes and icons in install dir (used in registry values)
$installedNewExe     = Join-Path $InstallDir 'tiny-launcher-new.exe'
$installedCurrentExe = Join-Path $InstallDir 'tiny-launcher-current.exe'
$installedNewIcon    = Join-Path $logosDest 'new-session.ico'
$installedCurrentIcon= Join-Path $logosDest 'current-session.ico'

# Helper to create/update a ProgID with DefaultIcon and Open command and Capabilities
function Ensure-ProgId {
    param(
        [string]$ProgId,
        [string]$DisplayName,
        [string]$IconPath,
        [string]$OpenCommand
    )

    # ProgID key under HKCU\Software\Classes
    $pidKey = "HKCU:\Software\Classes\$ProgId"
    New-Item -Path $pidKey -Force | Out-Null
    New-ItemProperty -Path $pidKey -Name '(default)' -Value $DisplayName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $pidKey -Name 'FriendlyAppName' -Value $DisplayName -PropertyType String -Force | Out-Null

    # DefaultIcon
    $iconKey = "$pidKey\DefaultIcon"
    New-Item -Path $iconKey -Force | Out-Null
    New-ItemProperty -Path $iconKey -Name '(default)' -Value $IconPath -PropertyType String -Force | Out-Null

    # Open command
    $cmdKey = "$pidKey\shell\open\command"
    New-Item -Path $cmdKey -Force | Out-Null
    New-ItemProperty -Path $cmdKey -Name '(default)' -Value $OpenCommand -PropertyType String -Force | Out-Null

    # Capabilities minimal metadata
    $capKey = "HKCU:\Software\$ProgId\Capabilities"
    New-Item -Path $capKey -Force | Out-Null
    New-ItemProperty -Path $capKey -Name 'ApplicationName' -Value $DisplayName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $capKey -Name 'ApplicationDescription' -Value 'Texteditor basierend auf Neovim' -PropertyType String -Force | Out-Null

    # Ensure RegisteredApplications entry
    $regApps = 'HKCU:\Software\RegisteredApplications'
    if (-not (Test-Path $regApps)) { New-Item -Path $regApps -Force | Out-Null }
    New-ItemProperty -Path $regApps -Name $ProgId -Value "Software\$ProgId\Capabilities" -PropertyType String -Force | Out-Null
}

# Build open commands that pass "%1" to the exe
$openCmdNew     = "`"$installedNewExe`" `"%1`""
$openCmdCurrent = "`"$installedCurrentExe`" `"%1`""

# Ensure both ProgIDs exist and point to respective exes/icons
Ensure-ProgId -ProgId $progIdNew -DisplayName $displayNew -IconPath $installedNewIcon -OpenCommand $openCmdNew
Ensure-ProgId -ProgId $progIdCurrent -DisplayName $displayCurrent -IconPath $installedCurrentIcon -OpenCommand $openCmdCurrent

# Optionally: set per-extension default ProgID under HKCU (convenience; Settings/UserChoice may override)
$extensions = @('.txt','.md','.lua','.py','.js')  # reduce list as convenience; extend if desired
foreach ($ext in $extensions) {
    $extKey = "HKCU:\Software\Classes\$ext"
    New-Item -Path $extKey -Force | Out-Null
    # Do NOT write UserChoice directly. Instead set default for HKCU classes to chosen ProgID for convenience.
    # Here we keep current session as default example; user can change via Settings UI.
    New-ItemProperty -Path $extKey -Name '(default)' -Value $progIdCurrent -PropertyType String -Force | Out-Null
}

# Show summary for verification
Write-Host "Installed files to: $InstallDir"
Get-ChildItem -Path $InstallDir -File | Select-Object Name, Length, LastWriteTime
Write-Host ""
Write-Host "Registered ProgIDs (HKCU):"
Get-ItemProperty -Path "HKCU:\Software\Classes\$progIdNew\DefaultIcon" -ErrorAction SilentlyContinue
Get-ItemProperty -Path "HKCU:\Software\Classes\$progIdCurrent\DefaultIcon" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "If Settings still show 'Windows Based Script Host', open Settings -> Apps -> Default apps and search for 'Neovim (new instance)' or 'Neovim (current instance)' and set file types manually. Restarting Explorer may refresh icons:"
Write-Host "  Stop-Process -Name explorer -Force; Start-Process explorer"

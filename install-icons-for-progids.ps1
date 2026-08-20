# install-icons-for-progids.ps1
# Installs DefaultIcon entries for two ProgIDs:
#   HKCU:\Software\Classes\Neovim.TextFile.New\DefaultIcon
#   HKCU:\Software\Classes\Neovim.TextFile.Current\DefaultIcon
#
# This script is intentionally small and only writes icon and minimal capability metadata.
# It does NOT change per-extension UserChoice keys (those are managed by Settings UI).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\install-icons-for-progids.ps1
#
param(
    [string]$InstallPath = $PSScriptRoot
)

# English comments inside code as requested.

# Fail fast on errors to avoid partial writes.
$ErrorActionPreference = 'Stop'

# Resolve InstallPath fallback if run from interactive prompt
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = (Get-Location).ProviderPath
}

# Normalize path (remove trailing slashes)
$InstallPath = $InstallPath.TrimEnd('\','/')

# Prepare expected paths for the icon files and logos directory
$logosDir = Join-Path $InstallPath 'Logos'
$newIconPath = Join-Path $logosDir 'new-session.ico'
$currentIconPath = Join-Path $logosDir 'current-session.ico'

# Validate that icons exist
if (-not (Test-Path -LiteralPath $logosDir)) {
    throw "Logos directory not found: $logosDir"
}
if (-not (Test-Path -LiteralPath $newIconPath)) {
    throw "new-session.ico not found: $newIconPath"
}
if (-not (Test-Path -LiteralPath $currentIconPath)) {
    throw "current-session.ico not found: $currentIconPath"
}

# Define ProgIDs and display names
$progIdNew = 'Neovim.TextFile.New'
$progIdCurrent = 'Neovim.TextFile.Current'
$displayNameNew = 'Neovim (new instance)'
$displayNameCurrent = 'Neovim (current instance)'

# Helper function to ensure a ProgID exists and set DefaultIcon + metadata
function Set-ProgIdIconAndMetadata {
    param(
        [string]$ProgId,
        [string]$DisplayName,
        [string]$IconFullPath
    )

    # Create ProgID key under HKCU per-user
    $progIdKey = "HKCU:\Software\Classes\$ProgId"
    New-Item -Path $progIdKey -Force | Out-Null

    # Set friendly display name and default value
    New-ItemProperty -Path $progIdKey -Name '(default)' -Value $DisplayName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $progIdKey -Name 'FriendlyAppName' -Value $DisplayName -PropertyType String -Force | Out-Null

    # DefaultIcon subkey: use explicit path to the .ico file (no index for .ico)
    $iconKey = "$progIdKey\DefaultIcon"
    New-Item -Path $iconKey -Force | Out-Null
    New-ItemProperty -Path $iconKey -Name '(default)' -Value $IconFullPath -PropertyType String -Force | Out-Null

    # Minimal Capabilities so the RegisteredApplications entry can point to something sane
    $capPath = "HKCU:\Software\$ProgId\Capabilities"
    New-Item -Path $capPath -Force | Out-Null
    New-ItemProperty -Path $capPath -Name 'ApplicationName' -Value $DisplayName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $capPath -Name 'ApplicationDescription' -Value 'Texteditor basierend auf Neovim' -PropertyType String -Force | Out-Null

    # Ensure FileAssociations subkey exists (values left to caller / Settings UI)
    $fileAssoc = "$capPath\FileAssociations"
    New-Item -Path $fileAssoc -Force | Out-Null

    # Register ProgId in RegisteredApplications so it appears in Settings -> Default apps list
    $regAppsKey = 'HKCU:\Software\RegisteredApplications'
    if (-not (Test-Path $regAppsKey)) {
        New-Item -Path $regAppsKey -Force | Out-Null
    }
    New-ItemProperty -Path $regAppsKey -Name $ProgId -Value "Software\$ProgId\Capabilities" -PropertyType String -Force | Out-Null
}

# Set for both ProgIDs
Set-ProgIdIconAndMetadata -ProgId $progIdNew -DisplayName $displayNameNew -IconFullPath $newIconPath
Set-ProgIdIconAndMetadata -ProgId $progIdCurrent -DisplayName $displayNameCurrent -IconFullPath $currentIconPath

# Optional: show summary info for user to verify
Write-Host "Wrote DefaultIcon and minimal Capabilities for:"
Write-Host "  $progIdNew -> $newIconPath"
Write-Host "  $progIdCurrent -> $currentIconPath"
Write-Host ""
Write-Host "Verify with (PowerShell):"
Write-Host "  Get-ItemProperty -Path 'HKCU:\Software\Classes\$progIdNew\DefaultIcon'"
Write-Host "  Get-ItemProperty -Path 'HKCU:\Software\Classes\$progIdCurrent\DefaultIcon'"
Write-Host ""
Write-Host "Hinweis: Falls Settings weiterhin 'Windows Based Script Host' anzeigt, die App einmal manuell in"
Write-Host "Einstellungen -> Apps -> Standard-Apps auswählen oder Explorer neu starten."
Write-Host ""
Write-Host "Optional: Restart Explorer to clear some icon caching (admin not required for HKCU changes):"
Write-Host "  Stop-Process -Name explorer -Force"
Write-Host "  Start-Process explorer"


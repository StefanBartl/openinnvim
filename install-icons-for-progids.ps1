# install-icons-for-progids.ps1
# Registers two further default-app entries, each with its own icon and its own open command:
#   Neovim.TextFile.New      -> "<launcher>" new "%1"
#   Neovim.TextFile.Current  -> "<launcher>" current "%1"
#
# Writes (per user, HKCU only): ProgID with display name, DefaultIcon and shell\open\command,
# Capabilities with the file types of file-extensions.ps1, and the RegisteredApplications value.
# It does NOT change per-extension UserChoice keys (those are managed by the Settings UI).
# uninstall.ps1 removes everything written here.
#
# Usage (after install.ps1):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\install-icons-for-progids.ps1
#
# Compatible with Windows PowerShell 5.1.
param(
    # Folder that holds Logos\ (the repository).
    [string]$InstallPath = $PSScriptRoot,
    # Folder OpenInNvim.exe was installed to (or a repository with bin\OpenInNvim.exe).
    [string]$LauncherDir = (Join-Path $env:LOCALAPPDATA 'OpenInNvim'),
    # Registry keys below HKCU. Only tests change them.
    [string]$ClassesKey = 'Software\Classes',
    [string]$SoftwareKey = 'Software'
)

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

# The launcher, validated before anything is written: a ProgID without an open command shows up in
# Settings -> Default apps and then opens nothing.
$launcher = $null
foreach ($candidate in @(
        (Join-Path $LauncherDir 'OpenInNvim.exe'),
        (Join-Path (Join-Path $LauncherDir 'bin') 'OpenInNvim.exe'),
        (Join-Path (Join-Path $InstallPath 'bin') 'OpenInNvim.exe'))) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $launcher = [IO.Path]::GetFullPath($candidate); break }
}
if (-not $launcher) {
    throw "OpenInNvim.exe not found in $LauncherDir (run install.ps1 first, or pass -LauncherDir)."
}

# The list of file types lives in file-extensions.ps1 (one copy, shared with the other scripts).
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
. (Join-Path $scriptDir 'file-extensions.ps1')

# Define ProgIDs and display names
$progIdNew = 'Neovim.TextFile.New'
$progIdCurrent = 'Neovim.TextFile.Current'
$displayNameNew = 'Neovim (new instance)'
$displayNameCurrent = 'Neovim (current instance)'

# Helper function to write one ProgID: name, icon, open command, capabilities.
function Set-ProgIdIconAndMetadata {
    param(
        [string]$ProgId,
        [string]$DisplayName,
        [string]$IconFullPath,
        [string]$Mode
    )

    # Create ProgID key under HKCU per-user
    $progIdKey = "HKCU:\$ClassesKey\$ProgId"
    New-Item -Path $progIdKey -Force | Out-Null

    # Set friendly display name and default value
    New-ItemProperty -Path $progIdKey -Name '(default)' -Value $DisplayName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $progIdKey -Name 'FriendlyAppName' -Value $DisplayName -PropertyType String -Force | Out-Null

    # DefaultIcon subkey: use explicit path to the .ico file (no index for .ico)
    $iconKey = "$progIdKey\DefaultIcon"
    New-Item -Path $iconKey -Force | Out-Null
    New-ItemProperty -Path $iconKey -Name '(default)' -Value $IconFullPath -PropertyType String -Force | Out-Null

    # Open command. The program by its full, quoted path: nothing is looked up at click time.
    $commandKey = "$progIdKey\shell\open\command"
    New-Item -Path $commandKey -Force | Out-Null
    New-ItemProperty -Path $commandKey -Name '(default)' -Value "`"$launcher`" $Mode `"%1`"" -PropertyType String -Force | Out-Null

    # Capabilities the RegisteredApplications entry points at
    $capPath = "HKCU:\$SoftwareKey\$ProgId\Capabilities"
    New-Item -Path $capPath -Force | Out-Null
    New-ItemProperty -Path $capPath -Name 'ApplicationName' -Value $DisplayName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $capPath -Name 'ApplicationDescription' -Value 'Text editor based on Neovim' -PropertyType String -Force | Out-Null

    # File types this entry can be chosen for in Settings -> Default apps
    $fileAssoc = "$capPath\FileAssociations"
    New-Item -Path $fileAssoc -Force | Out-Null
    foreach ($ext in $extensions) {
        New-ItemProperty -Path $fileAssoc -Name $ext -Value $ProgId -PropertyType String -Force | Out-Null
    }

    # Register ProgId in RegisteredApplications so it appears in Settings -> Default apps list
    $regAppsKey = "HKCU:\$SoftwareKey\RegisteredApplications"
    if (-not (Test-Path -LiteralPath $regAppsKey)) {
        New-Item -Path $regAppsKey -Force | Out-Null
    }
    New-ItemProperty -Path $regAppsKey -Name $ProgId -Value "$SoftwareKey\$ProgId\Capabilities" -PropertyType String -Force | Out-Null
}

# Set for both ProgIDs
Set-ProgIdIconAndMetadata -ProgId $progIdNew -DisplayName $displayNameNew -IconFullPath $newIconPath -Mode 'new'
Set-ProgIdIconAndMetadata -ProgId $progIdCurrent -DisplayName $displayNameCurrent -IconFullPath $currentIconPath -Mode 'current'

# Explorer and Settings keep the old registrations until told (not for a throw-away test key).
. (Join-Path $scriptDir 'shell-notify.ps1')
Send-AssocChanged -Skip:(($ClassesKey -ne 'Software\Classes') -or ($SoftwareKey -ne 'Software'))

# Optional: show summary info for user to verify
Write-Host "Wrote icon, open command and Capabilities for:"
Write-Host "  $progIdNew -> `"$launcher`" new `"%1`" ($newIconPath)"
Write-Host "  $progIdCurrent -> `"$launcher`" current `"%1`" ($currentIconPath)"
Write-Host ""
Write-Host "Verify with (PowerShell):"
Write-Host "  Get-ItemProperty -Path 'HKCU:\Software\Classes\$progIdNew\shell\open\command'"
Write-Host "  Get-ItemProperty -Path 'HKCU:\Software\Classes\$progIdCurrent\DefaultIcon'"
Write-Host ""
Write-Host "Note: if Settings still shows 'Windows Based Script Host', pick the app once manually in"
Write-Host "Settings -> Apps -> Default apps, or restart Explorer."

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
    Write-Host "Register 'new instance' or 'current instance' as the default app?" -ForegroundColor Yellow
    Write-Host " 1) New instance      (always opens files in a new Neovim window)"
    Write-Host " 2) Current instance  (tries to open files in a running instance)"

    # Read user input. Trim to remove stray whitespace.
    $choice = (Read-Host "Please choose 1 or 2").Trim()

    # Use explicit comparisons with if/elseif to avoid confusion about break semantics inside switch.
    if ($choice -eq '1') {
        $Mode = 'new'
        break    # This break exits the while loop (explicit and unambiguous).
    } elseif ($choice -eq '2') {
        $Mode = 'current'
        break    # Same here.
    } else {
        # If input is invalid, show error and loop again.
        Write-Host "`nInvalid input. Enter 1 or 2." -ForegroundColor Red
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

Write-Host "`nRegistering Neovim as a default application..."
Write-Host "Selected mode: $appName"

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
New-ItemProperty -Path $capabilitiesPath -Name 'ApplicationDescription' -Value "Text editor based on Neovim" -PropertyType String -Force | Out-Null

# 5) File associations list
$fileAssocsPath = "$capabilitiesPath\FileAssociations"
New-Item -Path $fileAssocsPath -Force | Out-Null

# The list of file types lives in file-extensions.ps1 (one copy, shared with the other scripts).
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
. (Join-Path $scriptDir 'file-extensions.ps1')

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

Write-Host "`nRegistration finished!" -ForegroundColor Green
Write-Host "`nNext steps:"
Write-Host "1. Open: Settings -> Apps -> Default apps"
Write-Host "2. Search for: $appName"
Write-Host "3. Choose the file types Neovim should open by default"
Write-Host "`nAlternatively: right-click a file -> Open with -> Choose another app -> '$appName'"
Write-Host "            and tick 'Always use this app'"








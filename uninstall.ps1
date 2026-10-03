# uninstall.ps1
# Removes the context-menu entries written by install.ps1 and the default-app registrations of
# register-nvim-default-app.ps1 / install-icons-for-progids.ps1 (all under HKCU) and, with -RemoveFiles, the files it
# put there. File removal follows the manifest in the install folder, never a recursive delete, and never
# touches a folder that is the repository itself.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 [-RemoveFiles] [-RemoveConfig]
#
# Compatible with Windows PowerShell 5.1.

param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'OpenInNvim'),
  # Registry keys below HKCU. Only tests change them.
  [string]$ClassesKey = 'Software\Classes',
  [string]$SoftwareKey = 'Software',
  # Also delete the files listed in the manifest.
  [switch]$RemoveFiles,
  # Also delete the config file (it is yours: kept unless you ask).
  [switch]$RemoveConfig,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$Source = $PSScriptRoot
if (-not $Source -or $Source -eq '') { $Source = (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) }
$Source = [IO.Path]::GetFullPath($Source).TrimEnd('\', '/')
$InstallDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallDir)
$InstallDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\', '/')

function Write-Step {
  param([string]$Text)
  if ($DryRun) { Write-Host "[dry run] $Text" } else { Write-Host $Text }
}

function Test-RegKey {
  param([string]$Path)
  $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path)
  if ($k) { $k.Close(); return $true }
  return $false
}

$names = @('Open_in_Neovim_new', 'Open_in_Neovim_current')
$paths = @('*\shell', 'Directory\shell', 'Directory\Background\shell')
$hkcu = [Microsoft.Win32.Registry]::CurrentUser

$removed = 0
foreach ($p in $paths) {
  foreach ($n in $names) {
    $key = "$ClassesKey\$p\$n"
    if (Test-RegKey $key) {
      Write-Step "Remove HKCU\$key"
      if (-not $DryRun) { $hkcu.DeleteSubKeyTree($key, $false) }
      $removed++
    }
  }
}
Write-Host "Context-menu entries removed: $removed"

# The default-app registrations of register-nvim-default-app.ps1 and install-icons-for-progids.ps1: the
# ProgIDs, their Capabilities and the RegisteredApplications values. Only these names, nothing else.
$progIds = @('Neovim.TextFile', 'Neovim.TextFile.New', 'Neovim.TextFile.Current')
$regApps = "$SoftwareKey\RegisteredApplications"
$removedProgIds = 0
foreach ($id in $progIds) {
  foreach ($key in @("$ClassesKey\$id", "$SoftwareKey\$id")) {
    if (Test-RegKey $key) {
      Write-Step "Remove HKCU\$key"
      if (-not $DryRun) { $hkcu.DeleteSubKeyTree($key, $false) }
      $removedProgIds++
    }
  }
  $ra = $hkcu.OpenSubKey($regApps, $true)
  if ($ra) {
    try {
      if ($null -ne $ra.GetValue($id)) {
        Write-Step "Remove HKCU\$regApps value $id"
        if (-not $DryRun) { $ra.DeleteValue($id, $false) }
        $removedProgIds++
      }
    } finally { $ra.Close() }
  }
}
Write-Host "Default-app registrations removed: $removedProgIds"

. (Join-Path $Source 'shell-notify.ps1')
if (-not $DryRun) { Send-AssocChanged -Skip:($ClassesKey -ne 'Software\Classes') }

if ($RemoveFiles) {
  $manifest = Join-Path $InstallDir 'install.manifest.txt'
  $inPlace = ($InstallDir -ieq $Source) -or (Test-Path -LiteralPath (Join-Path $InstallDir '.git'))
  if ($inPlace) {
    Write-Warning "$InstallDir is the repository itself: files are left alone."
  } elseif (-not (Test-Path -LiteralPath $manifest)) {
    Write-Warning "No manifest in ${InstallDir}: nothing deleted (not an installation made by install.ps1)."
  } else {
    foreach ($f in (Get-Content -LiteralPath $manifest)) {
      $f = $f.Trim()
      if ($f -eq '' -or $f -ne (Split-Path -Leaf $f)) { continue }          # plain file names only
      $isConfig = ($f -like '*.ini') -or ($f -like '*.config.ps1')
      if ($isConfig -and -not $RemoveConfig) { Write-Host "Config kept: $(Join-Path $InstallDir $f)"; continue }
      $target = Join-Path $InstallDir $f
      if (Test-Path -LiteralPath $target) { Write-Step "Delete $target"; if (-not $DryRun) { [IO.File]::Delete($target) } }
    }
    if (-not $DryRun) { [IO.File]::Delete($manifest) }
    # Only an empty folder is removed.
    if (-not $DryRun -and (Test-Path -LiteralPath $InstallDir) -and -not (Get-ChildItem -LiteralPath $InstallDir -Force)) {
      [IO.Directory]::Delete($InstallDir, $false)
      Write-Host "Removed empty folder $InstallDir"
    }
  }
}

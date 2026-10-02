# install.ps1
# Installs the two Explorer context-menu entries ("Open with Neovim (new instance)" and
# "(current instance)") for files, folders and folder backgrounds.
#
# - Per user: writes only under HKCU, needs no administrator rights.
# - Copies the launcher files to -InstallDir (default %LOCALAPPDATA%\OpenInNvim). When -InstallDir is the
#   repository itself, nothing is copied and the entries point at the repository ("in place").
# - Finds nvim.exe and writes it into a fresh config; an existing config is kept unless -Force.
# - Does not touch file associations.
# - Safe to run again.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDir $PWD.Path   # in place
#
# Compatible with Windows PowerShell 5.1 (no ?: or ?. operators, no parameter named $args).

param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'OpenInNvim'),
  [string]$NvimExe = '',
  # Registry key below HKCU that holds the shell classes. Only tests change it.
  [string]$ClassesKey = 'Software\Classes',
  [switch]$Force,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$Source = $PSScriptRoot
if (-not $Source -or $Source -eq '') { $Source = (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) }
$InstallDir = $InstallDir.TrimEnd('\', '/')

# Files that make up an installation. The VBS wrappers find the .ps1 files next to themselves; both
# launchers need the lib; the config is the only one a person edits.
$LauncherFiles = @(
  'open-in-nvim.vbs', 'open-in-nvim-current.vbs',
  'open-in-nvim.ps1', 'open-in-nvim-current.ps1',
  'open-in-nvim.lib.ps1'
)
$ConfigFile   = 'open-in-nvim.config.ps1'
$ManifestFile = 'install.manifest.txt'

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

function Find-NvimExe {
  <#
    .SYNOPSIS
      First nvim.exe found: PATH, the official installer, winget, scoop. $null when there is none.
  #>
  $cmd = Get-Command -Name 'nvim.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd -and $cmd.Source) { return $cmd.Source }
  $candidates = @(
    (Join-Path $env:ProgramFiles 'Neovim\bin\nvim.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Neovim\bin\nvim.exe'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\nvim.exe'),
    (Join-Path $env:USERPROFILE 'scoop\apps\neovim\current\bin\nvim.exe')
  )
  foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
  return $null
}

# ---------------------------------------------------------------------------------------------
# 1) Check the source
# ---------------------------------------------------------------------------------------------
foreach ($f in ($LauncherFiles + $ConfigFile)) {
  if (-not (Test-Path -LiteralPath (Join-Path $Source $f))) { throw "Required file missing: $(Join-Path $Source $f)" }
}

$InPlace = ($InstallDir -ieq $Source.TrimEnd('\', '/'))

# ---------------------------------------------------------------------------------------------
# 2) Neovim
# ---------------------------------------------------------------------------------------------
$Nvim = $NvimExe
if (-not $Nvim) { $Nvim = Find-NvimExe }
if ($Nvim -and -not (Test-Path -LiteralPath $Nvim)) { throw "NvimExe does not exist: $Nvim" }
if ($Nvim) { Write-Host "Neovim: $Nvim" } else { Write-Warning "nvim.exe not found. Set NVIM_BIN in the config, or put nvim on PATH." }

# ---------------------------------------------------------------------------------------------
# 3) Files
# ---------------------------------------------------------------------------------------------
if ($InPlace) {
  Write-Host "Installing in place: $InstallDir (no files copied, config untouched)"
} else {
  Write-Step "Copy launcher files to $InstallDir"
  if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    foreach ($f in $LauncherFiles) { Copy-Item -LiteralPath (Join-Path $Source $f) -Destination (Join-Path $InstallDir $f) -Force }
  }

  $destConfig = Join-Path $InstallDir $ConfigFile
  if ((Test-Path -LiteralPath $destConfig) -and -not $Force) {
    Write-Host "Config kept: $destConfig (use -Force to replace it)"
  } else {
    Write-Step "Write config $destConfig"
    if (-not $DryRun) {
      $text = [IO.File]::ReadAllText((Join-Path $Source $ConfigFile))
      if ($Nvim) {
        $escaped = $Nvim.Replace("'", "''")
        $text = [regex]::Replace($text, "(?m)^(\s*NVIM_BIN\s*=\s*)'[^']*'", { param($m) $m.Groups[1].Value + "'" + $escaped + "'" })
      }
      [IO.File]::WriteAllText($destConfig, $text, (New-Object System.Text.UTF8Encoding($false)))
    }
  }

  # The manifest lets uninstall.ps1 remove exactly these files and never recurse into the folder.
  if (-not $DryRun) {
    $names = @($LauncherFiles) + $ConfigFile
    [IO.File]::WriteAllLines((Join-Path $InstallDir $ManifestFile), [string[]]$names)
  }
}

# ---------------------------------------------------------------------------------------------
# 4) Registry entries
# ---------------------------------------------------------------------------------------------
$entries = @(
  @{ Name = 'Open_in_Neovim_new';     Label = 'Open with Neovim (new instance)';     Vbs = 'open-in-nvim.vbs' },
  @{ Name = 'Open_in_Neovim_current'; Label = 'Open with Neovim (current instance)'; Vbs = 'open-in-nvim-current.vbs' }
)
# "%1" is the clicked item, "%V" the folder whose background was clicked.
$targets = @(
  @{ Path = '*\shell';                    Arg = '%1' },
  @{ Path = 'Directory\shell';            Arg = '%1' },
  @{ Path = 'Directory\Background\shell'; Arg = '%V' }
)
# Names of earlier versions of this tool; removed so a menu never shows duplicates.
$legacy = @('Open_in_Neovim', 'Open_in_Neovim_nvr', 'Open_in_Neovim_new_hidden', 'Open_in_Neovim_Debug')

$hkcu = [Microsoft.Win32.Registry]::CurrentUser
foreach ($t in $targets) {
  foreach ($old in $legacy) {
    $key = "$ClassesKey\$($t.Path)\$old"
    if (Test-RegKey $key) { Write-Step "Remove legacy entry HKCU\$key"; if (-not $DryRun) { $hkcu.DeleteSubKeyTree($key, $false) } }
  }
  foreach ($e in $entries) {
    $key = "$ClassesKey\$($t.Path)\$($e.Name)"
    $command = 'wscript.exe //nologo "' + (Join-Path $InstallDir $e.Vbs) + '" "' + $t.Arg + '"'
    Write-Step "Write HKCU\$key"
    if (-not $DryRun) {
      $k = $hkcu.CreateSubKey($key)
      $k.SetValue('', $e.Label)
      if ($Nvim) { $k.SetValue('Icon', $Nvim) }
      $k.Close()
      $c = $hkcu.CreateSubKey("$key\command")
      $c.SetValue('', $command)
      $c.Close()
    }
  }
}

Write-Host ''
if ($DryRun) { Write-Host 'Dry run, nothing was changed. Would install:' } else { Write-Host 'Installed:' }
foreach ($e in $entries) { Write-Host "  * $($e.Label)" }
Write-Host 'On Windows 11 the entries are under "Show more options" (the classic menu).'
Write-Host "Config: $(Join-Path $InstallDir $ConfigFile)"

# install.ps1
# Builds OpenInNvim.exe and installs the two Explorer context-menu entries ("Open with Neovim (new
# instance)" and "(current instance)") for files, folders and folder backgrounds.
#
# - Per user: writes only under HKCU, needs no administrator rights.
# - Builds the exe from src\*.cs with the C# compiler that ships with Windows (no SDK) into -InstallDir
#   (default %LOCALAPPDATA%\OpenInNvim). When -InstallDir is the repository itself, the exe goes to
#   <repo>\bin (git-ignored) and the entries point there ("in place").
# - Finds nvim.exe and writes it into a fresh open-in-nvim.ini; an existing ini is kept unless -Force.
#   An open-in-nvim.config.ps1 of the old VBS + PowerShell version is converted once.
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
# Absolute before anything is compared or written: a relative folder would end up relative in the
# registry, where nothing can resolve it.
$Source = [IO.Path]::GetFullPath($Source).TrimEnd('\', '/')
$InstallDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallDir)
$InstallDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\', '/')

$ExeName      = 'OpenInNvim.exe'
$ConfigFile   = 'open-in-nvim.ini'
$OldConfig    = 'open-in-nvim.config.ps1'
$ManifestFile = 'install.manifest.txt'
# Files of the old VBS + PowerShell version; removed from an install folder that still has them.
$OldFiles = @('open-in-nvim.vbs', 'open-in-nvim-current.vbs', 'open-in-nvim.ps1', 'open-in-nvim-current.ps1', 'open-in-nvim.lib.ps1')

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

function Set-IniValue {
  <#
    .SYNOPSIS
      Replace (or append) "KEY = value" in ini text; a commented-out "# KEY = ..." line is taken over.
  #>
  param([string]$Text, [string]$Key, [string]$Value)
  $line = $Key + ' = ' + $Value
  $rx = '(?m)^[ \t]*#?[ \t]*' + [regex]::Escape($Key) + '[ \t]*=.*$'
  if ([regex]::IsMatch($Text, $rx)) {
    return ([regex]::new($rx)).Replace($Text, { param($m) $line }, 1)
  }
  return ($Text.TrimEnd() + "`r`n" + $line + "`r`n")
}

# ---------------------------------------------------------------------------------------------
# 1) Check the source
# ---------------------------------------------------------------------------------------------
foreach ($f in @('build.ps1', $ConfigFile)) {
  if (-not (Test-Path -LiteralPath (Join-Path $Source $f))) { throw "Required file missing: $(Join-Path $Source $f)" }
}
if (-not (Test-Path -LiteralPath (Join-Path $Source 'src'))) { throw "Required folder missing: $(Join-Path $Source 'src')" }

$InPlace = ($InstallDir -ieq $Source)
if ($InPlace) { $InstallDir = Join-Path $Source 'bin' }
$Exe = Join-Path $InstallDir $ExeName

# ---------------------------------------------------------------------------------------------
# 2) Neovim
# ---------------------------------------------------------------------------------------------
$Nvim = $NvimExe
if (-not $Nvim) { $Nvim = Find-NvimExe }
if ($Nvim -and -not (Test-Path -LiteralPath $Nvim)) { throw "NvimExe does not exist: $Nvim" }
if ($Nvim) { $Nvim = [IO.Path]::GetFullPath($Nvim); Write-Host "Neovim: $Nvim" } else { Write-Warning "nvim.exe not found. Set NVIM_BIN in the config, or put nvim on PATH." }

# ---------------------------------------------------------------------------------------------
# 3) Build the launcher
# ---------------------------------------------------------------------------------------------
Write-Step "Build $Exe"
if (-not $DryRun) {
  [void][IO.Directory]::CreateDirectory($InstallDir)
  & (Join-Path $Source 'build.ps1') -OutDir $InstallDir | Out-Null
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Exe)) { throw "Building $ExeName failed (run build.ps1 to see the compiler output)." }
}

# ---------------------------------------------------------------------------------------------
# 4) Config
# ---------------------------------------------------------------------------------------------
$destConfig = Join-Path $InstallDir $ConfigFile
$oldConfigPath = Join-Path $InstallDir $OldConfig
if ((Test-Path -LiteralPath $destConfig) -and -not $Force) {
  Write-Host "Config kept: $destConfig (use -Force to replace it)"
} else {
  Write-Step "Write config $destConfig"
  if (-not $DryRun) {
    $text = [IO.File]::ReadAllText((Join-Path $Source $ConfigFile))
    if ((Test-Path -LiteralPath $oldConfigPath) -and -not $Force) {
      # The old config is a PowerShell file that defines $Cfg; its values carry over.
      $Cfg = $null
      try { . $oldConfigPath } catch { Write-Warning "Old config not readable, defaults used: $($_.Exception.Message)" }
      if ($Cfg) {
        foreach ($k in @('NVIM_BIN', 'WEZTERM_BIN', 'NVIM_SERVER', 'PREFER_STABLE_PIPE', 'INSTANCE_PICK', 'FOLDER_OPENS_IN', 'FOCUS_TERMINAL')) {
          if ($Cfg.Contains($k) -and $null -ne $Cfg[$k] -and "$($Cfg[$k])" -ne '') {
            $v = $Cfg[$k]
            if ($v -is [bool]) { if ($v) { $v = 'true' } else { $v = 'false' } }
            $text = Set-IniValue $text $k ([string]$v)
          }
        }
        Write-Host "Converted the old config: $oldConfigPath"
      }
    }
    if ($Nvim) { $text = Set-IniValue $text 'NVIM_BIN' $Nvim }
    [IO.File]::WriteAllText($destConfig, $text, (New-Object System.Text.UTF8Encoding($false)))
  }
}

# Files of the old version in this folder (a previous install.ps1 copied them here).
if (-not $InPlace) {
  foreach ($f in ($OldFiles + $OldConfig)) {
    $old = Join-Path $InstallDir $f
    if (Test-Path -LiteralPath $old) { Write-Step "Remove old file $old"; if (-not $DryRun) { [IO.File]::Delete($old) } }
  }
  # The manifest lets uninstall.ps1 remove exactly these files and never recurse into the folder.
  if (-not $DryRun) {
    [IO.File]::WriteAllLines((Join-Path $InstallDir $ManifestFile), [string[]]@($ExeName, $ConfigFile))
  }
}

# ---------------------------------------------------------------------------------------------
# 5) Registry entries
# ---------------------------------------------------------------------------------------------
$entries = @(
  @{ Name = 'Open_in_Neovim_new';     Label = 'Open with Neovim (new instance)';     Mode = 'new' },
  @{ Name = 'Open_in_Neovim_current'; Label = 'Open with Neovim (current instance)'; Mode = 'current' }
)
# "%1" is the clicked item, "%V" the folder whose background was clicked.
$targets = @(
  @{ Path = '*\shell';                    Arg = '%1' },
  @{ Path = 'Directory\shell';            Arg = '%1' },
  @{ Path = 'Directory\Background\shell'; Arg = '%V' }
)
# Names of earlier versions of this tool; removed so a menu never shows duplicates.
$legacy = @('Open_in_Neovim', 'Open_in_Neovim_nvr', 'Open_in_Neovim_new_hidden', 'Open_in_Neovim_Debug')

$icon = $Exe
if ($Nvim) { $icon = $Nvim }

$hkcu = [Microsoft.Win32.Registry]::CurrentUser
foreach ($t in $targets) {
  foreach ($old in $legacy) {
    $key = "$ClassesKey\$($t.Path)\$old"
    if (Test-RegKey $key) { Write-Step "Remove legacy entry HKCU\$key"; if (-not $DryRun) { $hkcu.DeleteSubKeyTree($key, $false) } }
  }
  foreach ($e in $entries) {
    $key = "$ClassesKey\$($t.Path)\$($e.Name)"
    # The program by its full, quoted path: nothing is looked up at click time.
    $command = '"' + $Exe + '" ' + $e.Mode + ' "' + $t.Arg + '"'
    Write-Step "Write HKCU\$key"
    if (-not $DryRun) {
      $k = $hkcu.CreateSubKey($key)
      $k.SetValue('', $e.Label)
      $k.SetValue('Icon', $icon)
      $k.Close()
      $c = $hkcu.CreateSubKey("$key\command")
      $c.SetValue('', $command)
      $c.Close()
    }
  }
}

# Explorer keeps the old commands in memory until it is told that associations changed; without this a
# click right after the (un)install still runs the previous command.
if (-not $DryRun) {
  try {
    Add-Type -Namespace OpenInNvimSetup -Name Shell -MemberDefinition '[System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern void SHChangeNotify(int wEventId, uint uFlags, System.IntPtr dwItem1, System.IntPtr dwItem2);'
    [OpenInNvimSetup.Shell]::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)   # SHCNE_ASSOCCHANGED, SHCNF_FLUSH
  } catch { Write-Warning "Could not notify Explorer; restart it if the menu still runs the old command." }
}

Write-Host ''
if ($DryRun) { Write-Host 'Dry run, nothing was changed. Would install:' } else { Write-Host 'Installed:' }
foreach ($e in $entries) { Write-Host "  * $($e.Label)" }
Write-Host 'On Windows 11 the entries are under "Show more options" (the classic menu).'
Write-Host "Launcher: $Exe"
Write-Host "Config:   $destConfig"

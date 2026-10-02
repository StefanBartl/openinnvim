# open-in-nvim.ps1
# Purpose: Always open a NEW Neovim instance for a given file or directory.
# Chain: Explorer (Context Menu) -> VBS (hidden) -> this script -> nvim.exe
# Compatible with Windows PowerShell 5.1 (no CmdletBinding, no null-conditional ops).

# ---------------------------
# 0) Strict error behavior
# ---------------------------
$ErrorActionPreference = 'Stop'

# ---------------------------
# 1) Locate script directory (robust for PS 5.1)
# ---------------------------
# Prefer $PSScriptRoot (defined when running as a script).
$Here = $PSScriptRoot
if (-not $Here -or $Here -eq '') {
  # Fallback: use MyInvocation (available in PS 5.1)
  $scriptPath = $MyInvocation.MyCommand.Path
  if ($scriptPath -and $scriptPath -ne '') {
    # Use -Path (no wildcard expansion needed) to avoid ambiguous parameter sets
    $Here = Split-Path -Path $scriptPath -Parent
  } else {
    # Last fallback: current working directory (should not normally happen)
    $Here = $PWD.Path
  }
}

# ---------------------------
# 2) Load central config (same folder), or fallback defaults
# ---------------------------
$CfgPath = Join-Path -Path $Here -ChildPath 'open-in-nvim.config.ps1'
if (Test-Path -LiteralPath $CfgPath) {
  . $CfgPath
} else {
  # Minimal defaults if the config file is missing
  $Cfg = [ordered]@{
    NVIM_BIN    = 'nvim'                                    # resolve via PATH
    WEZTERM_BIN = "$env:LOCALAPPDATA\wezterm\wezterm-gui.exe"
  }
}

# Shared helpers (command-line quoting, detached spawn).
$LibPath = Join-Path -Path $Here -ChildPath 'open-in-nvim.lib.ps1'
if (-not (Test-Path -LiteralPath $LibPath)) {
  Write-Error "open-in-nvim.lib.ps1 is missing next to this script: $LibPath"
  exit 1
}
. $LibPath

# ---------------------------
# 3) Helpers
# ---------------------------
function Resolve-Bin {
  <#
    .SYNOPSIS
      Resolve a binary from a preferred absolute path or from PATH (fallback).
    .RETURNS
      Absolute path string or $null if not found at all.
  #>
  param([string]$Preferred, [string]$FallbackName)
  if ($Preferred -and (Test-Path -LiteralPath $Preferred)) {
    return (Get-Item -LiteralPath $Preferred).FullName
  }
  $cmd = Get-Command -Name $FallbackName -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Quote-Arg {
  <#
    .SYNOPSIS
      Quote a command-line argument for Windows (handles embedded quotes).
  #>
  param([string]$s)
  if ($null -eq $s -or $s -eq '') { return '""' }
  return '"' + $s.Replace('"','""') + '"'
}

# Optional: enable simple debug popups by setting env var OPEN_IN_NVIM_DEBUG=1
$DEBUG_OPENIN = ($env:OPEN_IN_NVIM_DEBUG -and $env:OPEN_IN_NVIM_DEBUG -ne '0')
function Show-Debug {
  param([string]$msg)
  if (-not $DEBUG_OPENIN) { return }
  Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', 'echo', $msg, '&', 'pause') | Out-Null
}

# ---------------------------
# 4) Resolve Neovim binary
# ---------------------------
$NVIM = Resolve-Bin $Cfg.NVIM_BIN 'nvim'
if (-not $NVIM) {
  Show-Debug "Neovim not found. Set NVIM_BIN in open-in-nvim.config.ps1 or ensure 'nvim' is on PATH."
  exit 1
}

# ---------------------------
# 5) Determine target from $args (Explorer forwards %1 or %V via VBS)
# ---------------------------
$TargetPath = if ($args.Count -gt 0) { $args[0] } else { $PWD.Path }
# Explorer hands over a real path, which may legitimately contain "%NAME%" (a folder called %TEMP%):
# environment variables are only expanded when the path as given does not exist.
$Expanded   = $TargetPath.Trim('"')
if (-not (Test-Path -LiteralPath $Expanded)) {
  $Expanded = [Environment]::ExpandEnvironmentVariables($Expanded)
}

$Cwd     = $PWD.Path
$FileArg = $null
if (Test-Path -LiteralPath $Expanded) {
  $item = Get-Item -LiteralPath $Expanded
  if ($item.PSIsContainer) {
    # Folder target → start nvim in that directory
    $Cwd = $item.FullName
  } else {
    # File target → start nvim with file, cwd = parent folder
    $Cwd     = $item.Directory.FullName
    $FileArg = $item.FullName
  }
} else {
  # Non-existing path → treat parent as cwd and pass literal path to create a new file
  $parent = Split-Path -Path $Expanded -Parent
  if ($parent -and (Test-Path -LiteralPath $parent)) {
    $Cwd = (Get-Item -LiteralPath $parent).FullName
  }
  $FileArg = $Expanded
}

# Build Neovim argument array (always new instance; explicit '--' for literal path handling)
$nvimArgs = @()
if ($FileArg) { $nvimArgs += @('--', $FileArg) }

# ---------------------------
# 6) Launch strategies (WezTerm -> Windows Terminal -> plain cmd.exe start)
# ---------------------------
# All three start the terminal detached through Invoke-Spawn (lib): the arguments are quoted correctly
# (a folder "My Dir" or a drive root "C:\" survives) and the hidden PowerShell does not keep waiting
# until the terminal is closed, which "& wezterm ... | Out-Null" did.
# The parameter is called $launchArgs, not $args: in Windows PowerShell 5.1 a declared parameter named
# $args does not bind, the automatic variable stays empty and the file argument was silently lost.
function Start-With-WezTerm {
  param([string]$cwd, [string[]]$launchArgs)
  $wez = $null
  $wezPref = $Cfg.WEZTERM_BIN
  if ($wezPref -and (Test-Path -LiteralPath $wezPref)) {
    $wez = $wezPref
  } else {
    $wezCmd = Get-Command -Name 'wezterm' -ErrorAction SilentlyContinue
    if ($wezCmd) { $wez = $wezCmd.Source }
  }
  if (-not $wez) { return $false }
  Invoke-Spawn -FilePath $wez -ArgList (@('start', '--cwd', $cwd, '--', $NVIM) + $launchArgs)
  return $true
}

function Start-With-WindowsTerminal {
  param([string]$cwd, [string[]]$launchArgs)
  $wtCmd = Get-Command -Name 'wt' -ErrorAction SilentlyContinue
  if (-not $wtCmd) { return $false }
  # Open a new tab (-w 0 nt), set working directory (-d), then run nvim
  Invoke-Spawn -FilePath $wtCmd.Source -ArgList (@('-w', '0', 'nt', '-d', $cwd, '--', $NVIM) + $launchArgs)
  return $true
}

function Start-With-CmdStart {
  param([string]$cwd, [string[]]$launchArgs)
  # Fallback: detached console via cmd.exe "start"
  $quotedCwd = Quote-Arg $cwd
  $cmdline   = Quote-Arg $NVIM
  if ($launchArgs.Count -gt 0) {
    $qa = @(); foreach ($a in $launchArgs) { $qa += (Quote-Arg $a) }
    $cmdline += ' ' + ($qa -join ' ')
  }
  # '""' is the (empty) window title: "start" takes the first quoted argument for the title, and an
  # empty array element is rejected by Windows PowerShell 5.1 ("argument is null or empty").
  Invoke-Spawn -FilePath 'cmd.exe' -Raw -ArgList @('/c', 'start', '""', '/D', $quotedCwd, $cmdline)
  return $true
}

# ---------------------------
# 7) Try in order and exit
# ---------------------------
if (Start-With-WezTerm -cwd $Cwd -launchArgs $nvimArgs) { exit 0 }
if (Start-With-WindowsTerminal -cwd $Cwd -launchArgs $nvimArgs) { exit 0 }
[void](Start-With-CmdStart -cwd $Cwd -launchArgs $nvimArgs)
exit 0

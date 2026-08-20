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
$Expanded   = [Environment]::ExpandEnvironmentVariables($TargetPath).Trim('"')

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
function Start-With-WezTerm {
  param([string]$cwd, [string[]]$args)
  $wezPref = $Cfg.WEZTERM_BIN
  if ($wezPref -and (Test-Path -LiteralPath $wezPref)) {
    & $wezPref start --cwd $cwd -- $NVIM @args | Out-Null
    return $true
  }
  $wezCmd = Get-Command -Name 'wezterm' -ErrorAction SilentlyContinue
  if ($wezCmd) {
    wezterm start --cwd $cwd -- $NVIM @args | Out-Null
    return $true
  }
  return $false
}

function Start-With-WindowsTerminal {
  param([string]$cwd, [string[]]$args)
  $wtCmd = Get-Command -Name 'wt' -ErrorAction SilentlyContinue
  if ($wtCmd) {
    $wt = $wtCmd.Source
    # Open a new tab (-w 0 nt), set working directory (-d), then run nvim
    $wtArgs = @('-w','0','nt','-d', $cwd, '--', $NVIM) + $args
    Start-Process -FilePath $wt -ArgumentList $wtArgs | Out-Null
    return $true
  }
  return $false
}

function Start-With-CmdStart {
  param([string]$cwd, [string[]]$args)
  # Fallback: detached console via cmd.exe "start"
  $quotedCwd = Quote-Arg $cwd
  $cmdline   = Quote-Arg $NVIM
  if ($args.Count -gt 0) {
    $qa = @(); foreach ($a in $args) { $qa += (Quote-Arg $a) }
    $cmdline += ' ' + ($qa -join ' ')
  }
  Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c','start','','/D', $quotedCwd, $cmdline) | Out-Null
  return $true
}

# ---------------------------
# 7) Try in order and exit
# ---------------------------
if (Start-With-WezTerm -cwd $Cwd -args $nvimArgs) { exit 0 }
if (Start-With-WindowsTerminal -cwd $Cwd -args $nvimArgs) { exit 0 }
[void](Start-With-CmdStart -cwd $Cwd -args $nvimArgs)
exit 0

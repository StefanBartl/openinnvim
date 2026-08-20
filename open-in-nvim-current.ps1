# open-in-nvim-current.ps1
# Behavior:
# - Try to open the target in an already running Neovim instance ("current").
# - Discovery order: configured NVIM_SERVER -> (if available) `nvr --serverlist` -> default \\.\pipe\nvim-%USERNAME%
# - If no server is reachable, start a NEW instance with `--listen` at a stable address and open the target.
# Compatible with Windows PowerShell 5.1 (no CmdletBinding, no null-conditional, no ?: operator).

# ---------------------------
# 0) Strict error behavior
# ---------------------------
$ErrorActionPreference = 'Stop'

# ---------------------------
# 1) Locate script directory (robust for PS 5.1) and load central config
# ---------------------------
$Here = $PSScriptRoot
if (-not $Here -or $Here -eq '') {
  $scriptPath = $MyInvocation.MyCommand.Path
  if ($scriptPath -and $scriptPath -ne '') {
    $Here = Split-Path -Path $scriptPath -Parent
  } else {
    $Here = $PWD.Path
  }
}

$CfgPath = Join-Path -Path $Here -ChildPath 'open-in-nvim.config.ps1'
if (Test-Path -LiteralPath $CfgPath) {
  . $CfgPath
} else {
  # Minimal defaults if the config file is missing
  $Cfg = [ordered]@{
    NVIM_BIN    = 'nvim'                                    # resolve via PATH
    WEZTERM_BIN = "$env:LOCALAPPDATA\wezterm\wezterm-gui.exe"
    NVIM_SERVER = ''                                        # empty -> discover
  }
}

# ---------------------------
# 2) Helpers
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

function Escape-For-VimSingleQuote {
  <#
    .SYNOPSIS
      Escape a string for embedding into a single-quoted Vimscript string.
      We double single quotes: "C:\O'Brien" -> "C:\O''Brien"
      Backslashes are left as-is; fnameescape() will add escapes on the Vim side.
  #>
  param([string]$s)
  if ($null -eq $s) { return '' }
  return $s.Replace("'", "''")
}

function Build-RemoteEditCommand {
  <#
    .SYNOPSIS
      Build a safe :execute command for remote-send that optionally changes
      the working directory and opens either '.' (directory view) or a file.
    .PARAMETER cwd
      The working directory to switch to before opening the target.
    .PARAMETER file
      File path to open. If $null or empty, a directory view (.) is opened.
    .RETURNS
      String with <C-\><C-n> prefix and trailing <CR> for --remote-send.
  #>
  param([string]$cwd, [string]$file)

  $parts = @()

  if ($cwd -and $cwd -ne '') {
    # :execute 'cd ' . fnameescape('<cwd>')
    $parts += (":execute 'cd ' . fnameescape('" + (Escape-For-VimSingleQuote $cwd) + "')")
  }

  if ($file -and $file -ne '') {
    # :execute 'edit ' . fnameescape('<file>')
    $parts += (":execute 'edit ' . fnameescape('" + (Escape-For-VimSingleQuote $file) + "')")
  } else {
    # No file -> open a directory view in the current cwd
    $parts += ":edit ."
  }

  return "<C-\><C-n>" + ($parts -join " | ") + "<CR>"
}

# Optional debug popup (enable via: setx OPEN_IN_NVIM_DEBUG 1)
$DEBUG_OPENIN = ($env:OPEN_IN_NVIM_DEBUG -and $env:OPEN_IN_NVIM_DEBUG -ne '0')
function Show-Debug {
  param([string]$msg)
  if (-not $DEBUG_OPENIN) { return }
  Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', 'echo', $msg, '&', 'pause') | Out-Null
}

# ---------------------------
# 3) Resolve binaries
# ---------------------------
$NVIM = Resolve-Bin $Cfg.NVIM_BIN 'nvim'
$NVR  = Resolve-Bin $null 'nvr'         # optional
if (-not $NVIM) {
  Write-Error "Neovim not found. Fix NVIM_BIN in config or ensure 'nvim' is on PATH."
  exit 1
}

# ---------------------------
# 4) Determine target from $args (Explorer forwards %1 or %V via VBS)
# ---------------------------
$TargetPath = if ($args.Count -gt 0) { $args[0] } else { $PWD.Path }
$Expanded   = [Environment]::ExpandEnvironmentVariables($TargetPath).Trim('"')

$IsDir  = $false
$Cwd    = $PWD.Path
$FileArg = $null

if (Test-Path -LiteralPath $Expanded) {
  $item = Get-Item -LiteralPath $Expanded
  if ($item.PSIsContainer) {
    $IsDir = $true
    $Cwd   = $item.FullName
  } else {
    $IsDir   = $false
    $Cwd     = $item.Directory.FullName
    $FileArg = $item.FullName
  }
} else {
  $parent = Split-Path -Path $Expanded -Parent
  if ($parent -and (Test-Path -LiteralPath $parent)) {
    $Cwd = (Get-Item -LiteralPath $parent).FullName
  }
  $FileArg = $Expanded  # allow creating a new file remotely
}

# ---------------------------
# 5) Build candidate server list
# ---------------------------
$candidates = New-Object System.Collections.ArrayList

# 5.1 explicit server from config
if ($Cfg.NVIM_SERVER -and $Cfg.NVIM_SERVER -ne '') {
  [void]$candidates.Add($Cfg.NVIM_SERVER)
}

# 5.2 discover via nvr --serverlist (if available)
if ($NVR) {
  try {
    $out = & $NVR --serverlist 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) {
      foreach ($line in ($out -split "`r?`n")) {
        $addr = $line.Trim()
        if ($addr -ne '' -and -not $candidates.Contains($addr)) {
          [void]$candidates.Add($addr)
        }
      }
    }
  } catch {
    # ignore discovery errors
  }
}

# 5.3 fallback: per-user pipe (matches common init.lua pattern)
if ($candidates.Count -eq 0) {
  [void]$candidates.Add("\\.\pipe\nvim-$env:USERNAME")
}

# ---------------------------
# 6) Try to open via nvr (preferred) or raw nvim --remote-send
# ---------------------------
function Try-Open-With-Nvr {
  param([string]$server, [string]$cwd, [string]$fileArg, [bool]$isDir)
  if (-not $NVR) { return $false }

  if ($isDir) {
    # Build a safe :cd + :edit . command and send keys
    $keys = Build-RemoteEditCommand -cwd $cwd -file $null
    & $NVR --servername $server --remote-send $keys | Out-Null
  } else {
    # For files prefer --remote to reuse window/tab logic in the server
    & $NVR --servername $server --remote -- $fileArg | Out-Null
  }
  return ($LASTEXITCODE -eq 0)
}

function Try-Open-With-NvimRemote {
  param([string]$server, [string]$cwd, [string]$fileArg, [bool]$isDir)

  if ($isDir) {
    $keys = Build-RemoteEditCommand -cwd $cwd -file $null
    & $NVIM --server $server --remote-send $keys | Out-Null
    return ($LASTEXITCODE -eq 0)
  } else {
    # Prefer --remote for files if supported by this nvim build; otherwise remote-send a command.
    & $NVIM --server $server --remote -- $fileArg | Out-Null
    if ($LASTEXITCODE -eq 0) { return $true }

    # Fallback: :execute 'cd …' | edit <file>
    $keys = Build-RemoteEditCommand -cwd $cwd -file $fileArg
    & $NVIM --server $server --remote-send $keys | Out-Null
    return ($LASTEXITCODE -eq 0)
  }
}

foreach ($srv in $candidates) {
  if (Try-Open-With-Nvr -server $srv -cwd $Cwd -fileArg $FileArg -isDir $IsDir) { exit 0 }
  if (Try-Open-With-NvimRemote -server $srv -cwd $Cwd -fileArg $FileArg -isDir $IsDir) { exit 0 }
}

# ---------------------------
# 7) No server reachable -> start a NEW instance that listens on a stable pipe
# ---------------------------
$listen = if ($Cfg.NVIM_SERVER -and $Cfg.NVIM_SERVER -ne '') { $Cfg.NVIM_SERVER } else { "\\.\pipe\nvim-$env:USERNAME" }
$NVIM_ARGS = @('--listen', $listen)
if (-not $IsDir -and $FileArg) { $NVIM_ARGS += @('--', $FileArg) }

function Start-With-WezTerm {
  param([string]$cwd, [string[]]$args)
  $wezPref = $Cfg.WEZTERM_BIN
  if ($wezPref -and (Test-Path -LiteralPath $wezPref)) {
    Start-Process -FilePath $wezPref -ArgumentList @('start','--cwd', $cwd, '--', $NVIM) + $args | Out-Null
    return $true
  }
  $wezCmd = Get-Command -Name 'wezterm' -ErrorAction SilentlyContinue
  if ($wezCmd) {
    Start-Process -FilePath $wezCmd.Source -ArgumentList @('start','--cwd', $cwd, '--', $NVIM) + $args | Out-Null
    return $true
  }
  return $false
}

function Start-With-WindowsTerminal {
  param([string]$cwd, [string[]]$args)
  $wtCmd = Get-Command -Name 'wt' -ErrorAction SilentlyContinue
  if ($wtCmd) {
    $wt = $wtCmd.Source
    Start-Process -FilePath $wt -ArgumentList @('-w','0','nt','-d', $cwd, '--', $NVIM) + $args | Out-Null
    return $true
  }
  return $false
}

function Start-With-CmdStart {
  param([string]$cwd, [string[]]$args)
  $quotedCwd = Quote-Arg $cwd
  $cmdline   = Quote-Arg $NVIM
  if ($args.Count -gt 0) {
    $qa = @(); foreach ($a in $args) { $qa += (Quote-Arg $a) }
    $cmdline += ' ' + ($qa -join ' ')
  }
  Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c','start','','/D', $quotedCwd, $cmdline) | Out-Null
  return $true
}

if (Start-With-WezTerm -cwd $Cwd -args $NVIM_ARGS) { exit 0 }
if (Start-With-WindowsTerminal -cwd $Cwd -args $NVIM_ARGS) { exit 0 }
[void](Start-With-CmdStart -cwd $Cwd -args $NVIM_ARGS)
exit 0

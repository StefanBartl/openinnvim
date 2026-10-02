# open-in-nvim-current.ps1
# Behavior:
# - Try to open the target in an already running Neovim instance ("current").
# - Discovery order: configured NVIM_SERVER -> stable pipe \\.\pipe\nvim-%USERNAME% (if it exists) ->
#   every running instance with a UI attached (default pipes \\.\pipe\nvim.<pid>.<n>).
# - Files and folders are handed over by RPC on the pipe; `nvim --server ... --remote` is the fallback for
#   non-pipe addresses (TCP). No external tool besides Neovim itself is needed.
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

# Shared helpers (instance discovery, RPC client, command-line quoting, spawning). Required: the two
# code paths "with" and "without" the file were never both exercised, so there is only one now.
$LibPath = Join-Path -Path $Here -ChildPath 'open-in-nvim.lib.ps1'
if (-not (Test-Path -LiteralPath $LibPath)) {
  Write-Error "open-in-nvim.lib.ps1 is missing next to this script: $LibPath"
  exit 1
}
. $LibPath

# Read an optional setting from $Cfg; older config files do not have the newer keys.
function Get-CfgValue {
  param([string]$Key, $Default)
  if ($Cfg.Contains($Key) -and $null -ne $Cfg[$Key] -and "$($Cfg[$Key])" -ne '') { return $Cfg[$Key] }
  return $Default
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
      Escape a string for embedding into a single-quoted Vimscript string that travels through
      --remote-send (which reads key notation).
      We double single quotes: "C:\O'Brien" -> "C:\O''Brien"
      A literal "<" becomes "<lt>": a name such as "a<CR>b" must not be typed as keys. NTFS forbids
      "<", but a not yet existing target can still be given on the command line.
      Backslashes are left as-is; fnameescape() will add escapes on the Vim side.
  #>
  param([string]$s)
  if ($null -eq $s) { return '' }
  return $s.Replace("'", "''").Replace('<', '<lt>')
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

  # Every command is :silent. ":cd" echoes the new directory, and a path wider than the window
  # raises a hit-enter prompt that leaves the instance waiting for a key.
  $parts = @()

  if ($cwd -and $cwd -ne '') {
    # :silent execute 'cd ' . fnameescape('<cwd>')
    $parts += (":silent execute 'cd ' . fnameescape('" + (Escape-For-VimSingleQuote $cwd) + "')")
  }

  if ($file -and $file -ne '') {
    # :silent execute 'edit ' . fnameescape('<file>')
    $parts += (":silent execute 'edit ' . fnameescape('" + (Escape-For-VimSingleQuote $file) + "')")
  } else {
    # No file -> open a directory view in the current cwd
    $parts += ":silent edit ."
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
# OPEN_IN_NVIM_ONLY_PIDS (tests, debugging) restricts the launcher to those processes. The per-user pipe
# name is not PID based and could reach a real session, so it stays out of it.
$OnlyPidsMode = [bool]$env:OPEN_IN_NVIM_ONLY_PIDS
if (-not $NVIM) {
  Write-Error "Neovim not found. Fix NVIM_BIN in config or ensure 'nvim' is on PATH."
  exit 1
}

# ---------------------------
# 4) Determine target from $args (Explorer forwards %1 or %V via VBS)
# ---------------------------
$TargetPath = if ($args.Count -gt 0) { $args[0] } else { $PWD.Path }
# Explorer hands over a real path, which may legitimately contain "%NAME%" (a folder called %TEMP%):
# environment variables are only expanded when the path as given does not exist.
$Expanded   = $TargetPath.Trim('"')
if (-not (Test-Path -LiteralPath $Expanded)) {
  $Expanded = [Environment]::ExpandEnvironmentVariables($Expanded)
}

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
  # An unrooted name starting with '-' would be parsed as an option by --remote.
  if (-not [IO.Path]::IsPathRooted($FileArg)) { $FileArg = Join-Path -Path $Cwd -ChildPath $FileArg }
}

# ---------------------------
# 5) Build candidate server list
# ---------------------------
$candidates = New-Object System.Collections.ArrayList

# 5.1 explicit server from config
if ($Cfg.NVIM_SERVER -and $Cfg.NVIM_SERVER -ne '') {
  [void]$candidates.Add($Cfg.NVIM_SERVER)
}

# 5.2 a stable per-user pipe (nvim-<USERNAME>) pins the "main" instance when the user's own config
# creates it (serverstart). Preferred while it exists; PREFER_STABLE_PIPE = $false skips it.
$StablePipe = "\\.\pipe\nvim-$env:USERNAME"
if (-not $OnlyPidsMode -and (Get-CfgValue 'PREFER_STABLE_PIPE' $true) -and (Test-NvimPipe $StablePipe)) {
  if (-not $candidates.Contains($StablePipe)) { [void]$candidates.Add($StablePipe) }
}

# 5.3 every running Neovim exposes \\.\pipe\nvim.<pid>.<n> without any configuration. Only instances
# with a UI attached count (headless helpers are skipped). INSTANCE_PICK: newest (default) | oldest | ask.
$onlyPids = @()
if ($env:OPEN_IN_NVIM_ONLY_PIDS) {
  # Debugging/test aid: restrict discovery to a comma separated PID list.
  $onlyPids = @($env:OPEN_IN_NVIM_ONLY_PIDS -split '[,; ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
}
$pick = [string](Get-CfgValue 'INSTANCE_PICK' 'newest')
$found = Select-NvimInstance -Instances @(Get-NvimInstances -OnlyPids $onlyPids) -Pick $pick
if ($pick -eq 'ask' -and $found.Count -gt 1 -and -not $env:OPEN_IN_NVIM_DRYRUN) {
  $chosen = Show-NvimChooser -Instances $found
  if (-not $chosen) { exit 0 }                       # dialog cancelled
  if (-not $candidates.Contains($chosen)) { [void]$candidates.Add($chosen) }
} else {
  foreach ($inst in $found) {
    if (-not $candidates.Contains($inst.Pipe)) { [void]$candidates.Add($inst.Pipe) }
  }
}

# ---------------------------
# 6) Open the target in a running instance
# ---------------------------
function Invoke-Bounded {
  <#
    .SYNOPSIS
      Run an external program with a time limit and no window.
    .RETURNS
      The exit code, or $null when the limit was hit (the process tree is then killed by its own PID).
    .NOTES
      nvim --remote against a busy or hung instance can block forever. This script runs hidden, so a
      hang would be invisible and never end.
  #>
  param([string]$Exe, [string[]]$ArgList, [int]$TimeoutMs = 5000)
  $q = @()
  foreach ($a in $ArgList) { $q += (ConvertTo-CommandLineArg $a) }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = ($q -join ' ')
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  if (-not $proc.WaitForExit($TimeoutMs)) {
    & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null
    return $null
  }
  return $proc.ExitCode
}

function Try-Open-With-NvimRemote {
  <#
    .NOTES
      Command-line fallback, used for servers the RPC path cannot reach (TCP addresses, or a pipe the
      RPC client failed to talk to). Folders get cd + a directory view only: handing a path to a user
      command through command-line text cannot be made safe for names with #, % or [.
  #>
  param([string]$server, [string]$cwd, [string]$fileArg, [bool]$isDir)

  if ($isDir) {
    $keys = Build-RemoteEditCommand -cwd $cwd -file $null
    $rc = Invoke-Bounded -Exe $NVIM -ArgList @('--server', $server, '--remote-send', $keys)
    return ($rc -eq 0)
  }

  # Prefer --remote for files if supported by this nvim build; otherwise remote-send a command.
  # No "--" before the path: Neovim takes it literally and opens a buffer named "--" (exit code 2).
  # $fileArg is always an absolute path here, so it cannot be mistaken for an option.
  $rc = Invoke-Bounded -Exe $NVIM -ArgList @('--server', $server, '--remote', $fileArg)
  if ($rc -eq 0) { return $true }
  if ($null -eq $rc) { return $false }   # timed out: the instance does not answer, try the next one

  # Fallback: :execute 'cd ...' | edit <file>
  $keys = Build-RemoteEditCommand -cwd $cwd -file $fileArg
  $rc = Invoke-Bounded -Exe $NVIM -ArgList @('--server', $server, '--remote-send', $keys)
  return ($rc -eq 0)
}

$FolderMode = [string](Get-CfgValue 'FOLDER_OPENS_IN' 'filetree')
$OpenPath   = if ($IsDir) { $Cwd } else { $FileArg }

function Open-ViaServer {
  <#
    .SYNOPSIS
      Hand the target to one server address. True when it was opened.
  #>
  param([string]$srv)
  # Preferred: talk to the instance over its pipe. No second nvim.exe (about a second each), the
  # path never passes through command-line or key parsing, and a refusal comes back as an error.
  if ($srv.StartsWith('\\.\pipe\')) {
    $r = Invoke-NvimOpen -Pipe $srv -Path $OpenPath -IsDir $IsDir -FolderMode $FolderMode
    if ($r.Ok) { return $true }
    # Reached but refused (error reply, or no answer in time): the command-line route would hit the
    # same wall, so go on to the next instance.
    if ($r.Connected) { return $false }
  }
  return (Try-Open-With-NvimRemote -server $srv -cwd $Cwd -fileArg $FileArg -isDir $IsDir)
}

# With nothing else to try, fall back to the per-user pipe name (matches the common init.lua pattern).
if ($candidates.Count -eq 0) { [void]$candidates.Add($StablePipe) }

# Diagnostics: OPEN_IN_NVIM_DRYRUN=1 prints the ordered candidates and exits without opening anything.
if ($env:OPEN_IN_NVIM_DRYRUN) {
  foreach ($c in $candidates) { Write-Output ('candidate: ' + $c) }
  exit 0
}

foreach ($srv in $candidates) {
  # ONLY_PIDS mode must never reach a real session through the per-user pipe name.
  if ($OnlyPidsMode -and $srv -eq $StablePipe) { continue }
  if (Open-ViaServer $srv) { exit 0 }
}

# ---------------------------
# 7) No server reachable -> start a NEW instance that listens on a stable pipe
# ---------------------------
# Safety stop for tests and diagnostics: never open a window.
if ($env:OPEN_IN_NVIM_NO_SPAWN) { Write-Output 'no reachable instance'; exit 3 }
$listen = if ($Cfg.NVIM_SERVER -and $Cfg.NVIM_SERVER -ne '') { $Cfg.NVIM_SERVER } else { "\\.\pipe\nvim-$env:USERNAME" }
$NVIM_ARGS = @()
# A name that is already taken (by an instance that refused or hung) would make "--listen" fail.
if (-not ($listen.StartsWith('\\.\pipe\') -and (Test-NvimPipe $listen))) { $NVIM_ARGS += @('--listen', $listen) }
if (-not $IsDir -and $FileArg) { $NVIM_ARGS += @('--', $FileArg) }

# Note: the parameter is called $nvimArgs, not $args. In Windows PowerShell 5.1 a declared parameter
# named $args does not bind; the automatic variable stays empty and the arguments are silently lost.
function Start-With-WezTerm {
  param([string]$cwd, [string[]]$nvimArgs)
  $wezPref = $Cfg.WEZTERM_BIN
  $wez = $null
  if ($wezPref -and (Test-Path -LiteralPath $wezPref)) {
    $wez = $wezPref
  } else {
    $wezCmd = Get-Command -Name 'wezterm' -ErrorAction SilentlyContinue
    if ($wezCmd) { $wez = $wezCmd.Source }
  }
  if (-not $wez) { return $false }
  Invoke-Spawn -FilePath $wez -ArgList (@('start', '--cwd', $cwd, '--', $NVIM) + $nvimArgs)
  return $true
}

function Start-With-WindowsTerminal {
  param([string]$cwd, [string[]]$nvimArgs)
  $wtCmd = Get-Command -Name 'wt' -ErrorAction SilentlyContinue
  if (-not $wtCmd) { return $false }
  Invoke-Spawn -FilePath $wtCmd.Source -ArgList (@('-w', '0', 'nt', '-d', $cwd, '--', $NVIM) + $nvimArgs)
  return $true
}

function Start-With-CmdStart {
  param([string]$cwd, [string[]]$nvimArgs)
  $quotedCwd = Quote-Arg $cwd
  $cmdline   = Quote-Arg $NVIM
  if ($nvimArgs.Count -gt 0) {
    $qa = @(); foreach ($a in $nvimArgs) { $qa += (Quote-Arg $a) }
    $cmdline += ' ' + ($qa -join ' ')
  }
  # '""' is the (empty) window title: "start" takes the first quoted argument for the title, and an
  # empty array element is rejected by Windows PowerShell 5.1 ("argument is null or empty").
  Invoke-Spawn -FilePath 'cmd.exe' -Raw -ArgList @('/c', 'start', '""', '/D', $quotedCwd, $cmdline)
  return $true
}

if (Start-With-WezTerm -cwd $Cwd -nvimArgs $NVIM_ARGS) { exit 0 }
if (Start-With-WindowsTerminal -cwd $Cwd -nvimArgs $NVIM_ARGS) { exit 0 }
[void](Start-With-CmdStart -cwd $Cwd -nvimArgs $NVIM_ARGS)
exit 0

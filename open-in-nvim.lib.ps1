# open-in-nvim.lib.ps1
# Helpers for the "current instance" launcher (dot-sourced by open-in-nvim-current.ps1).
#
# Every Neovim instance listens on a default RPC pipe named \\.\pipe\nvim.<pid>.<n>, even without
# any configuration. This file finds those pipes, keeps the instances with a UI attached (a person
# is sitting in front of them; plugin jobs and other headless helpers have none), opens files and
# folders in one over RPC, and can ask a pipe for a short label (cwd | file) for a chooser.
#
# Windows PowerShell 5.1 compatible: no ?: and no ?. operators. Keep this file ASCII only.

function Get-NvimPipeEntries {
  <#
    .SYNOPSIS
      List default Neovim pipes from the pipe namespace.
    .RETURNS
      Objects with Pid (int), Index (int) and Pipe (full \\.\pipe\... name), sorted by Pid, Index.
  #>
  $rx = '^\\\\\.\\pipe\\nvim\.(\d+)\.(\d+)$'
  $found = New-Object System.Collections.ArrayList
  $names = @()
  try { $names = [IO.Directory]::GetFiles('\\.\pipe\') } catch { return @() }
  foreach ($n in $names) {
    $m = [regex]::Match($n, $rx)
    if (-not $m.Success) { continue }
    [void]$found.Add([pscustomobject]@{
      Pid   = [int]$m.Groups[1].Value
      Index = [int]$m.Groups[2].Value
      Pipe  = $n
    })
  }
  return @($found | Sort-Object Pid, Index)
}

function Test-NvimPipe {
  <#
    .SYNOPSIS
      True if a pipe with exactly this full name (\\.\pipe\...) currently exists.
  #>
  param([string]$Pipe)
  try { return ([IO.Directory]::GetFiles('\\.\pipe\') -contains $Pipe) } catch { return $false }
}

function Get-NvimInstances {
  <#
    .SYNOPSIS
      Running Neovim instances of this logon session that a person is sitting in front of.
    .DESCRIPTION
      An instance counts when it owns a default pipe and has a UI attached (len(nvim_list_uis()) > 0).
      Plugin jobs and helpers (--headless, -l scripts, a plugin's "--embed --headless" child) have no
      UI, a TUI session's editor core and a GUI such as Neovide have one. Asking the instance is
      both cheaper than a WMI query for command lines (about 200 ms) and more accurate than
      pattern matching on them.
    .PARAMETER OnlyPids
      Restrict to these PIDs (debugging and tests; env OPEN_IN_NVIM_ONLY_PIDS feeds this).
    .PARAMETER UiTimeoutMs
      How long one instance may take to answer; a hung one is skipped.
    .RETURNS
      Objects Pid, Pipe, Started (DateTime or $null), sorted by Pid.
  #>
  param([int[]]$OnlyPids = @(), [int]$UiTimeoutMs = 500)

  $entries = @(Get-NvimPipeEntries)
  if ($OnlyPids.Count -gt 0) { $entries = @($entries | Where-Object { $OnlyPids -contains $_.Pid }) }
  if ($entries.Count -eq 0) { return @() }

  $procs = @{}
  foreach ($p in @(Get-Process -Name 'nvim' -ErrorAction SilentlyContinue)) { $procs[[int]$p.Id] = $p }

  # Only instances of this logon session: on a shared machine (RDP, fast user switching) another
  # user's editor must never receive a file the person just clicked.
  $mySession = $null
  try { $mySession = (Get-Process -Id $PID).SessionId } catch { $mySession = $null }

  $result = New-Object System.Collections.ArrayList
  $seen = @{}
  foreach ($e in $entries) {
    if ($seen.ContainsKey($e.Pid)) { continue }     # first (lowest index) pipe per process is enough
    $proc = $procs[$e.Pid]
    if (-not $proc) { continue }                     # pipe of a process that is not nvim.exe or is gone
    if ($null -ne $mySession -and [int]$proc.SessionId -ne [int]$mySession) { continue }
    $uis = Invoke-NvimEval -Pipe $e.Pipe -Expr 'len(nvim_list_uis())' -TimeoutMs $UiTimeoutMs
    if ($null -eq $uis -or [int]$uis -lt 1) { continue }
    $seen[$e.Pid] = $true
    $started = $null
    try { $started = $proc.StartTime } catch { $started = $null }
    [void]$result.Add([pscustomobject]@{ Pid = $e.Pid; Pipe = $e.Pipe; Started = $started })
  }
  return @($result)
}

function Select-NvimInstance {
  <#
    .SYNOPSIS
      Order instances by the configured pick strategy.
    .PARAMETER Pick
      newest (default): most recently started first.
      oldest: longest running first.
      ask: ordered newest first; Show-NvimChooser decides when more than one remains.
  #>
  param([object[]]$Instances, [string]$Pick = 'newest')
  $list = @($Instances)
  if ($list.Count -le 1) { return $list }
  if ($Pick -eq 'oldest') {
    return @($list | Sort-Object @{ Expression = { $_.Started }; Ascending = $true }, Pid)
  }
  return @($list | Sort-Object @{ Expression = { $_.Started }; Descending = $true }, @{ Expression = { $_.Pid }; Descending = $true })
}

# ---------------------------------------------------------------------------------------------
# Minimal msgpack-rpc client (just enough for a request with string/array parameters)
# ---------------------------------------------------------------------------------------------

function ConvertTo-MsgPackString {
  param([string]$Text)
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  $n = $bytes.Length
  $head = $null
  if ($n -lt 32)        { $head = [byte[]]@((0xa0 + $n)) }
  elseif ($n -lt 256)   { $head = [byte[]]@(0xd9, $n) }
  elseif ($n -lt 65536) { $head = [byte[]]@(0xda, [math]::Floor($n / 256), ($n % 256)) }
  else { throw 'string too long for this minimal encoder' }
  return ,([byte[]]($head + $bytes))
}

function ConvertTo-MsgPackValue {
  <#
    .SYNOPSIS
      Encode $null, bool, string, small non-negative int and (nested) arrays of those.
  #>
  param($Value)
  $out = New-Object System.Collections.Generic.List[byte]
  if ($null -eq $Value) { $out.Add([byte]0xc0) }
  elseif ($Value -is [bool]) { if ($Value) { $out.Add([byte]0xc3) } else { $out.Add([byte]0xc2) } }
  elseif ($Value -is [string]) { $out.AddRange([byte[]](ConvertTo-MsgPackString $Value)) }
  elseif ($Value -is [int]) {
    if ($Value -lt 0 -or $Value -gt 127) { throw 'integer out of range for this minimal encoder' }
    $out.Add([byte]$Value)
  }
  elseif ($Value -is [System.Array]) {
    $n = $Value.Length
    if ($n -lt 16) { $out.Add([byte](0x90 + $n)) }
    elseif ($n -lt 65536) { $out.Add([byte]0xdc); $out.Add([byte][math]::Floor($n / 256)); $out.Add([byte]($n % 256)) }
    else { throw 'array too long for this minimal encoder' }
    foreach ($e in $Value) { $out.AddRange([byte[]](ConvertTo-MsgPackValue $e)) }
  }
  else { throw ('unsupported type for msgpack: ' + $Value.GetType().FullName) }
  return ,($out.ToArray())
}

function ConvertFrom-MsgPackValue {
  <#
    .SYNOPSIS
      Decode one msgpack value from $Buf at $Pos (advances $Pos). Throws when the buffer ends early,
      a type is not supported or the nesting is deeper than any reply this client expects; callers
      treat that as "need more data" or "give up".
    .NOTES
      The depth limit matters: a process that squats a pipe name could answer with endlessly nested
      arrays, and unbounded recursion would take this script down with a stack overflow.
  #>
  param([byte[]]$Buf, [ref]$Pos, [int]$Depth = 0)

  if ($Depth -gt 16) { throw 'nesting too deep' }

  function Read-Len([int]$count) {
    if ($Pos.Value + $count -gt $Buf.Length) { throw 'incomplete' }
    $v = 0
    for ($i = 0; $i -lt $count; $i++) { $v = ($v * 256) + $Buf[$Pos.Value + $i] }
    $Pos.Value += $count
    return $v
  }
  function Read-Str([int]$len) {
    if ($Pos.Value + $len -gt $Buf.Length) { throw 'incomplete' }
    $s = [Text.Encoding]::UTF8.GetString($Buf, $Pos.Value, $len)
    $Pos.Value += $len
    return $s
  }
  function Read-Arr([int]$len) {
    $arr = New-Object object[] $len
    for ($i = 0; $i -lt $len; $i++) { $arr[$i] = ConvertFrom-MsgPackValue -Buf $Buf -Pos $Pos -Depth ($Depth + 1) }
    return ,$arr
  }

  if ($Pos.Value -ge $Buf.Length) { throw 'incomplete' }
  $b = [int]$Buf[$Pos.Value]
  $Pos.Value++

  # Arrays are returned wrapped (",") so an empty or one-element array is not unrolled into $null / a scalar.
  if ($b -le 0x7f) { return $b }
  if ($b -ge 0xe0) { return ($b - 256) }
  if ($b -ge 0xa0 -and $b -le 0xbf) { return (Read-Str ($b -band 0x1f)) }
  if ($b -ge 0x90 -and $b -le 0x9f) { return ,(Read-Arr ($b -band 0x0f)) }
  switch ($b) {
    0xc0 { return $null }
    0xc2 { return $false }
    0xc3 { return $true }
    0xcc { return (Read-Len 1) }
    0xcd { return (Read-Len 2) }
    0xce { return (Read-Len 4) }
    0xd0 { $v = Read-Len 1; if ($v -ge 128) { $v -= 256 }; return $v }
    0xd1 { $v = Read-Len 2; if ($v -ge 32768) { $v -= 65536 }; return $v }
    0xd2 { $v = Read-Len 4; if ($v -ge 2147483648) { $v -= 4294967296 }; return $v }
    0xd9 { return (Read-Str (Read-Len 1)) }
    0xda { return (Read-Str (Read-Len 2)) }
    0xdb { return (Read-Str (Read-Len 4)) }
    0xdc { return ,(Read-Arr (Read-Len 2)) }
  }
  throw ('unsupported msgpack type 0x{0:x2}' -f $b)
}

function Invoke-NvimRpc {
  <#
    .SYNOPSIS
      Call one API function in a running instance over its pipe.
    .PARAMETER Pipe
      Full pipe name (\\.\pipe\nvim.<pid>.0).
    .PARAMETER Params
      Positional API parameters, e.g. @('nvim_exec_lua', ...) arguments as an object[].
    .RETURNS
      Object: Connected (the pipe accepted us), Ok (a reply without error arrived), Result, Error (text).
      "Connected but not Ok" means the instance answered with an error or not at all in time.
    .NOTES
      Short timeouts on purpose: a busy or hung instance must not stall the launcher.
  #>
  param([string]$Pipe, [string]$Method, [object[]]$Params = @(), [int]$TimeoutMs = 800)

  $res = [pscustomobject]@{ Connected = $false; Ok = $false; Result = $null; Error = $null }
  $name = $Pipe -replace '^\\\\\.\\pipe\\', ''
  $client = $null
  try {
    $client = New-Object System.IO.Pipes.NamedPipeClientStream('.', $name, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
    $client.Connect($TimeoutMs)
    $res.Connected = $true

    # request: [0, msgid, method, [params...]]
    $req = New-Object System.Collections.Generic.List[byte]
    $req.AddRange([byte[]]@(0x94, 0x00, 0x01))
    $req.AddRange([byte[]](ConvertTo-MsgPackString $Method))
    $req.AddRange([byte[]](ConvertTo-MsgPackValue ([object[]]$Params)))
    $bytes = $req.ToArray()
    $client.Write($bytes, 0, $bytes.Length)
    $client.Flush()

    $acc = New-Object System.Collections.Generic.List[byte]
    $buf = New-Object byte[] 4096
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
      $left = [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds
      if ($left -lt 1) { break }
      $task = $client.ReadAsync($buf, 0, $buf.Length)
      if (-not $task.Wait($left)) { break }
      $n = $task.Result
      if ($n -le 0) { break }
      $acc.AddRange([byte[]]($buf[0..($n - 1)]))

      # Decode complete messages; skip notifications, take the reply to msgid 1.
      $all = $acc.ToArray()
      $pos = 0
      while ($pos -lt $all.Length) {
        $ref = [ref]$pos
        $msg = $null
        try { $msg = ConvertFrom-MsgPackValue -Buf $all -Pos $ref } catch { break }
        $pos = $ref.Value
        if ($msg -is [array] -and $msg.Count -eq 4 -and $msg[0] -eq 1 -and $msg[1] -eq 1) {
          if ($null -ne $msg[2]) {
            $err = $msg[2]
            if ($err -is [array] -and $err.Count -ge 2) { $res.Error = [string]$err[1] } else { $res.Error = [string]$err }
          } else {
            $res.Ok = $true
            $res.Result = $msg[3]
          }
          return $res
        }
      }
    }
    return $res
  } catch {
    return $res
  } finally {
    if ($client) { $client.Dispose() }
  }
}

function Invoke-NvimEval {
  <#
    .SYNOPSIS
      Evaluate a Vimscript expression in a running instance over its pipe; $null on any failure.
    .PARAMETER Pipe
      Full pipe name (\\.\pipe\nvim.<pid>.0) as returned by Get-NvimInstances.
  #>
  param([string]$Pipe, [string]$Expr, [int]$TimeoutMs = 800)
  $r = Invoke-NvimRpc -Pipe $Pipe -Method 'nvim_eval' -Params @($Expr) -TimeoutMs $TimeoutMs
  if ($r.Ok) { return $r.Result }
  return $null
}

# Lua run inside the target instance. The path travels as a parameter, never spliced into command
# text, so no character in a file or folder name (space, #, %, [, ', ...) needs escaping.
# "silent" keeps file messages from raising a hit-enter prompt that would leave the editor waiting.
$script:NvimOpenFileLua = 'local f = ...; vim.cmd("silent drop " .. vim.fn.fnameescape(f)); return "file"'
$script:NvimOpenDirLua = @'
local d, mode = ...
if mode == "filetree" and vim.fn.exists(":Filetree") == 2 then
  vim.cmd.Filetree({ args = { "open", d } })
  return "filetree"
end
vim.api.nvim_set_current_dir(d)
vim.cmd("silent edit .")
return "edit"
'@

function Invoke-NvimOpen {
  <#
    .SYNOPSIS
      Open a file or folder in a running instance over its pipe (no second nvim.exe involved).
    .DESCRIPTION
      A file goes through ":drop" (what "nvim --remote" does). A folder is handed to filetree.nvim
      (":Filetree open <dir>") when FolderMode is 'filetree' and the instance has that command,
      otherwise it becomes the working directory with a directory view.
    .RETURNS
      The Invoke-NvimRpc object; Result is 'file', 'filetree' or 'edit' on success.
  #>
  param([string]$Pipe, [string]$Path, [bool]$IsDir, [string]$FolderMode = 'filetree', [int]$TimeoutMs = 3000)
  if ($IsDir) {
    return (Invoke-NvimRpc -Pipe $Pipe -Method 'nvim_exec_lua' -Params @($script:NvimOpenDirLua, [object[]]@($Path, $FolderMode)) -TimeoutMs $TimeoutMs)
  }
  return (Invoke-NvimRpc -Pipe $Pipe -Method 'nvim_exec_lua' -Params @($script:NvimOpenFileLua, [object[]]@($Path)) -TimeoutMs $TimeoutMs)
}

function ConvertTo-CommandLineArg {
  <#
    .SYNOPSIS
      Quote one argument for a Windows command line (CommandLineToArgvW rules).
    .DESCRIPTION
      Backslashes are literal except in front of a double quote, so a run of them before a quote or at
      the end of the argument is doubled; embedded quotes become \". The old "double every quote"
      form turned a trailing backslash ("C:\dir\") into an escaped closing quote.
  #>
  param([string]$Arg)
  if ($null -eq $Arg -or $Arg -eq '') { return '""' }
  $bs = [char]92
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  $run = 0
  foreach ($ch in $Arg.ToCharArray()) {
    if ($ch -eq $bs) { $run++; continue }
    if ($ch -eq '"') {
      [void]$sb.Append($bs, ($run * 2 + 1))
      [void]$sb.Append('"')
      $run = 0
      continue
    }
    if ($run -gt 0) { [void]$sb.Append($bs, $run); $run = 0 }
    [void]$sb.Append($ch)
  }
  if ($run -gt 0) { [void]$sb.Append($bs, ($run * 2)) }
  [void]$sb.Append('"')
  return $sb.ToString()
}

function Get-NvimInstanceLabel {
  <#
    .SYNOPSIS
      One-line description of an instance for the chooser: "<cwd>  |  <file>  (pid N)".
  #>
  param([object]$Instance)
  $label = Invoke-NvimEval -Pipe $Instance.Pipe -Expr 'getcwd() . "  |  " . fnamemodify(bufname("%"), ":t")'
  $started = ''
  if ($Instance.Started) { $started = ', started ' + ([datetime]$Instance.Started).ToString('HH:mm:ss') }
  if ($label) { return ('{0}  (pid {1}{2})' -f $label, $Instance.Pid, $started) }
  return ('pid {0}{1}' -f $Instance.Pid, $started)
}

function New-NvimChooserForm {
  <#
    .SYNOPSIS
      Build (do not show) a small list dialog. Result is read from $form.Tag after ShowDialog().
    .PARAMETER Items
      Objects with Label and Value (the pipe name to return).
  #>
  param([object[]]$Items)
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'Open in Neovim - choose instance'
  $form.StartPosition = 'CenterScreen'
  $form.TopMost = $true
  $form.Width = 720
  $form.Height = 300
  $form.KeyPreview = $true
  $form.Tag = $null

  $list = New-Object System.Windows.Forms.ListBox
  $list.Dock = 'Fill'
  $list.Font = New-Object System.Drawing.Font('Consolas', 10)
  foreach ($it in $Items) { [void]$list.Items.Add($it.Label) }
  if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
  $form.Controls.Add($list)

  $accept = {
    if ($list.SelectedIndex -ge 0) {
      $form.Tag = $Items[$list.SelectedIndex].Value
      $form.Close()
    }
  }.GetNewClosure()
  $list.Add_DoubleClick($accept)
  $form.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq 'Return') { & $accept; $e.Handled = $true }
    elseif ($e.KeyCode -eq 'Escape') { $form.Close() }
  }.GetNewClosure())
  $form.Add_Shown({ $form.Activate(); $list.Focus() }.GetNewClosure())

  return $form
}

function Show-NvimChooser {
  <#
    .SYNOPSIS
      Let the user pick one of several instances. Returns the chosen pipe or $null (cancelled).
  #>
  param([object[]]$Instances)
  $items = @()
  foreach ($i in $Instances) {
    $items += [pscustomobject]@{ Label = (Get-NvimInstanceLabel $i); Value = $i.Pipe }
  }
  $form = New-NvimChooserForm -Items $items
  [void]$form.ShowDialog()
  $choice = $form.Tag
  $form.Dispose()
  return $choice
}

function Invoke-Spawn {
  <#
    .SYNOPSIS
      Start a program detached. Every argument is quoted for the Windows command line, because
      Start-Process joins an argument array with plain spaces (a folder "My Dir" would arrive as two).
    .PARAMETER Raw
      The list is already a finished command line (the cmd.exe route builds its own quoting).
    .NOTES
      OPEN_IN_NVIM_SPAWN_DRYRUN=1 prints the command instead of starting it (tests, diagnostics).
  #>
  param([string]$FilePath, [string[]]$ArgList, [switch]$Raw)
  if ($Raw) {
    $line = ($ArgList -join ' ')
  } else {
    $q = @()
    foreach ($a in $ArgList) { $q += (ConvertTo-CommandLineArg $a) }
    $line = ($q -join ' ')
  }
  # Console, not the output stream: the caller's return value would swallow the line.
  if ($env:OPEN_IN_NVIM_SPAWN_DRYRUN) { [Console]::Out.WriteLine('spawn: ' + $FilePath + ' ' + $line); return }
  Start-Process -FilePath $FilePath -ArgumentList $line | Out-Null
}

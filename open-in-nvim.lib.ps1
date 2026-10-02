# open-in-nvim.lib.ps1
# Helpers for the "current instance" launcher (dot-sourced by open-in-nvim-current.ps1).
#
# Every Neovim instance listens on a default RPC pipe named \\.\pipe\nvim.<pid>.<n>, even without
# any configuration. This file finds those pipes, drops processes that are not editors a person
# is sitting in front of (--headless helpers such as plugin jobs), and can ask a pipe for a short
# label (cwd | file) so a chooser can show something more useful than a PID.
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

function Test-NvimCommandLineEligible {
  <#
    .SYNOPSIS
      Decide from a command line whether an nvim.exe is an editor instance worth opening files in.
    .DESCRIPTION
      --headless covers plugin jobs and the helper processes some plugins spawn (for example
      "--embed --headless"). Script runs (-l) are headless as well. A GUI such as Neovide starts
      "--embed" WITHOUT --headless, so --embed alone does not disqualify an instance.
      An unknown (empty) command line counts as eligible.
  #>
  param([string]$CommandLine)
  if ([string]::IsNullOrEmpty($CommandLine)) { return $true }
  if ($CommandLine -match '(^|\s)--headless(\s|$)') { return $false }
  if ($CommandLine -match '\s-l(\s|$)') { return $false }
  return $true
}

function Get-NvimInstances {
  <#
    .SYNOPSIS
      Running, eligible Neovim instances that expose a default pipe.
    .PARAMETER OnlyPids
      Restrict to these PIDs (debugging and tests; env OPEN_IN_NVIM_ONLY_PIDS feeds this).
    .RETURNS
      Objects Pid, Pipe, Started (DateTime or $null), CommandLine, sorted by Pid.
  #>
  param([int[]]$OnlyPids = @())

  $entries = @(Get-NvimPipeEntries)
  if ($OnlyPids.Count -gt 0) { $entries = @($entries | Where-Object { $OnlyPids -contains $_.Pid }) }
  if ($entries.Count -eq 0) { return @() }

  # One query for all nvim.exe processes instead of one per pipe.
  $procs = @{}
  $haveCim = $true
  try {
    foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='nvim.exe'" -ErrorAction Stop)) {
      $procs[[int]$p.ProcessId] = $p
    }
  } catch {
    $haveCim = $false
    foreach ($p in @(Get-Process -Name 'nvim' -ErrorAction SilentlyContinue)) {
      $procs[[int]$p.Id] = [pscustomobject]@{ ProcessId = $p.Id; CommandLine = $null; CreationDate = $p.StartTime }
    }
  }

  $result = New-Object System.Collections.ArrayList
  $seen = @{}
  foreach ($e in $entries) {
    if ($seen.ContainsKey($e.Pid)) { continue }     # first (lowest index) pipe per process is enough
    $proc = $procs[$e.Pid]
    if (-not $proc) { continue }                     # pipe of a process that is not nvim.exe or is gone
    if (-not (Test-NvimCommandLineEligible $proc.CommandLine)) { continue }
    $seen[$e.Pid] = $true
    [void]$result.Add([pscustomobject]@{
      Pid         = $e.Pid
      Pipe        = $e.Pipe
      Started     = $proc.CreationDate
      CommandLine = $proc.CommandLine
    })
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
# Minimal msgpack-rpc client (just enough for nvim_eval returning a string)
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

function ConvertFrom-MsgPackValue {
  <#
    .SYNOPSIS
      Decode one msgpack value from $Buf at $Pos (advances $Pos). Throws when the buffer ends early
      or a type is not supported; callers treat that as "need more data" or "give up".
  #>
  param([byte[]]$Buf, [ref]$Pos)

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
    for ($i = 0; $i -lt $len; $i++) { $arr[$i] = ConvertFrom-MsgPackValue -Buf $Buf -Pos $Pos }
    return ,$arr
  }

  if ($Pos.Value -ge $Buf.Length) { throw 'incomplete' }
  $b = [int]$Buf[$Pos.Value]
  $Pos.Value++

  if ($b -le 0x7f) { return $b }
  if ($b -ge 0xe0) { return ($b - 256) }
  if ($b -ge 0xa0 -and $b -le 0xbf) { return (Read-Str ($b -band 0x1f)) }
  if ($b -ge 0x90 -and $b -le 0x9f) { return (Read-Arr ($b -band 0x0f)) }
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
    0xdc { return (Read-Arr (Read-Len 2)) }
  }
  throw ('unsupported msgpack type 0x{0:x2}' -f $b)
}

function Invoke-NvimEval {
  <#
    .SYNOPSIS
      Evaluate a Vimscript expression in a running instance over its pipe; $null on any failure.
    .PARAMETER Pipe
      Full pipe name (\\.\pipe\nvim.<pid>.0) as returned by Get-NvimInstances.
    .NOTES
      Short timeouts on purpose: a busy or hung instance must not stall the chooser.
  #>
  param([string]$Pipe, [string]$Expr, [int]$TimeoutMs = 800)

  $name = $Pipe -replace '^\\\\\.\\pipe\\', ''
  $client = $null
  try {
    $client = New-Object System.IO.Pipes.NamedPipeClientStream('.', $name, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
    $client.Connect($TimeoutMs)

    # request: [0, msgid, "nvim_eval", [expr]]
    $req = New-Object System.Collections.Generic.List[byte]
    $req.AddRange([byte[]]@(0x94, 0x00, 0x01))
    $req.AddRange([byte[]](ConvertTo-MsgPackString 'nvim_eval'))
    $req.Add(0x91)
    $req.AddRange([byte[]](ConvertTo-MsgPackString $Expr))
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

      # Try to decode complete messages; skip notifications, return the reply to msgid 1.
      $all = $acc.ToArray()
      $pos = 0
      while ($pos -lt $all.Length) {
        $p = [ref]$pos
        $msg = $null
        try { $msg = ConvertFrom-MsgPackValue -Buf $all -Pos $p } catch { break }
        $pos = $p.Value
        if ($msg -is [array] -and $msg.Count -eq 4 -and $msg[0] -eq 1 -and $msg[1] -eq 1) {
          if ($null -ne $msg[2]) { return $null }
          return $msg[3]
        }
      }
    }
    return $null
  } catch {
    return $null
  } finally {
    if ($client) { $client.Dispose() }
  }
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

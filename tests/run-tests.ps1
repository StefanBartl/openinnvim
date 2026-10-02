# tests/run-tests.ps1
# Tests for the PID-pipe discovery and the "current instance" launcher.
# Run with Windows PowerShell 5.1 (the launcher's target):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
#
# Safe by construction: it only talks to Neovim instances it started itself (fixture.lua) and
# restricts the launcher to their PIDs via OPEN_IN_NVIM_ONLY_PIDS. USERNAME is faked for the
# launcher so a real per-user pipe (nvim-<you>) of a running session is never picked.
# Only own PIDs are ever stopped. ASCII only.

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'open-in-nvim.lib.ps1')

$nvim = $env:NVIM_EXE
if (-not $nvim -or -not (Test-Path -LiteralPath $nvim)) { $nvim = 'C:\Program Files\Neovim\bin\nvim.exe' }
if (-not (Test-Path -LiteralPath $nvim)) { throw "nvim.exe not found; set NVIM_EXE" }

$script:fail = 0
$script:pass = 0
function Assert-That {
  param([string]$Name, [bool]$Cond, [string]$Detail = '')
  if ($Cond) { $script:pass++; Write-Host "  ok   $Name" }
  else { $script:fail++; Write-Host "  FAIL $Name  $Detail" -ForegroundColor Red }
}

# ---------------------------------------------------------------------------------------------
Write-Host '== unit: command-line eligibility'
Assert-That 'plain TUI'                  (Test-NvimCommandLineEligible '"C:\Program Files\Neovim\bin\nvim.exe" file.txt')
Assert-That 'GUI (--embed only)'         (Test-NvimCommandLineEligible 'nvim.exe --embed')
Assert-That '--listen is not -l'         (Test-NvimCommandLineEligible 'nvim.exe --listen \\.\pipe\nvim-x')
Assert-That '--headless excluded'        (-not (Test-NvimCommandLineEligible 'nvim.exe --headless -c q'))
Assert-That '--embed --headless excluded'(-not (Test-NvimCommandLineEligible 'nvim.exe --embed --headless -n -u NONE'))
Assert-That '-l script excluded'         (-not (Test-NvimCommandLineEligible 'nvim.exe -l probe.lua'))
Assert-That 'unknown command line kept'  (Test-NvimCommandLineEligible '')

Write-Host '== unit: msgpack decoder'
function Dec { param([byte[]]$b) $p = 0; return ConvertFrom-MsgPackValue -Buf $b -Pos ([ref]$p) }
$r = Dec ([byte[]](0x94, 0x01, 0x01, 0xc0, 0xa3, 0x61, 0x62, 0x63))
Assert-That 'array [1,1,nil,"abc"]' (($r.Count -eq 4) -and ($r[0] -eq 1) -and ($null -eq $r[2]) -and ($r[3] -eq 'abc'))
$long = ('x' * 40)
$bytes = [byte[]](@(0xd9, 40) + [Text.Encoding]::UTF8.GetBytes($long))
Assert-That 'str8 (40 chars)' ((Dec $bytes) -eq $long)
Assert-That 'negative fixint'  ((Dec ([byte[]](0xff))) -eq -1)
Assert-That 'uint16'           ((Dec ([byte[]](0xcd, 0x01, 0x00))) -eq 256)
$threw = $false
try { [void](Dec ([byte[]](0xa5, 0x61))) } catch { $threw = ($_.Exception.Message -match 'incomplete') }
Assert-That 'truncated string reports incomplete' $threw
$utf = [Text.Encoding]::UTF8.GetBytes([string]([char]0x00e4 + [char]0x00fc))
Assert-That 'UTF-8 string' ((Dec ([byte[]](@(0xa4) + $utf))) -eq ([string]([char]0x00e4 + [char]0x00fc)))

# ---------------------------------------------------------------------------------------------
Write-Host '== fixture: starting throw-away instances'
$tmp = Join-Path $env:TEMP ('oin_tests_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $tmp | Out-Null
$pidsFile = Join-Path $tmp 'pids.txt'
$stopFile = Join-Path $tmp 'stop.txt'

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $nvim
$psi.Arguments = '--headless -l "' + (Join-Path $PSScriptRoot 'fixture.lua') + '" "' + $pidsFile + '" "' + $stopFile + '"'
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.RedirectStandardInput = $true
$fixture = [System.Diagnostics.Process]::Start($psi)

try {
  $t0 = [DateTime]::UtcNow
  while (-not (Test-Path -LiteralPath $pidsFile) -and ([DateTime]::UtcNow - $t0).TotalSeconds -lt 30) { Start-Sleep -Milliseconds 300 }
  if (-not (Test-Path -LiteralPath $pidsFile)) { throw 'fixture did not report PIDs in 30 s' }
  $P = @{}
  foreach ($l in (Get-Content -LiteralPath $pidsFile)) { $k, $v = $l -split '=', 2; $P[$k] = [int]$v }
  # The fixture's "editor" instances are "nvim --embed" cores with a UI attached (what a GUI runs).
  # On Windows a real TUI session is the same core behind a visible nvim.exe UI client; that client
  # owns no pipe, so discovery only ever sees the core. tui1/tui2 keep their names in the asserts.
  $P.tui1 = $P.gui1
  $P.tui2 = $P.gui2
  Write-Host ('  pids: ' + (($P.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' '))
  Start-Sleep -Milliseconds 1000

  $all = @($P.tui1, $P.tui2, $P.headless, $P.embedhl)

  # -------------------------------------------------------------------------------------------
  Write-Host '== discovery'
  $inst = @(Get-NvimInstances -OnlyPids $all)
  $got = @($inst | ForEach-Object { $_.Pid } | Sort-Object)
  $want = @($P.tui1, $P.tui2 | Sort-Object)
  Assert-That 'finds exactly the two editor instances' (($got -join ',') -eq ($want -join ',')) ("got=" + ($got -join ',') + " want=" + ($want -join ','))
  Assert-That 'pipe name format'                     (($inst | Where-Object { $_.Pipe -match '^\\\\\.\\pipe\\nvim\.\d+\.\d+$' }).Count -eq $inst.Count)
  Assert-That 'start time known'                     (($inst | Where-Object { $_.Started }).Count -eq $inst.Count)
  Assert-That 'headless and embed-headless filtered' ((@($inst | Where-Object { $_.Pid -eq $P.headless -or $_.Pid -eq $P.embedhl })).Count -eq 0)
  $newest = @(Select-NvimInstance -Instances $inst -Pick 'newest')
  $oldest = @(Select-NvimInstance -Instances $inst -Pick 'oldest')
  Assert-That 'newest first' ($newest[0].Pid -eq $P.tui2) ("first=" + $newest[0].Pid)
  Assert-That 'oldest first' ($oldest[0].Pid -eq $P.tui1) ("first=" + $oldest[0].Pid)
  Assert-That 'unknown PID yields nothing' (@(Get-NvimInstances -OnlyPids @(999999)).Count -eq 0)

  # -------------------------------------------------------------------------------------------
  Write-Host '== rpc label'
  $v = Invoke-NvimEval -Pipe $newest[0].Pipe -Expr '1 + 2'
  Assert-That 'nvim_eval returns a number' ($v -eq 3) "got=$v"
  $v = Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'getpid()'
  Assert-That 'getpid matches the process' ($v -eq $P.tui2) "got=$v"
  $lab = Get-NvimInstanceLabel $newest[0]
  Assert-That 'label has cwd and pid' (($lab -match '\|') -and ($lab -match "pid $($P.tui2)")) "label=$lab"
  Assert-That 'dead pipe returns null quickly' ($null -eq (Invoke-NvimEval -Pipe '\\.\pipe\nvim.999999.0' -Expr '1' -TimeoutMs 300))

  # -------------------------------------------------------------------------------------------
  Write-Host '== chooser form (constructed, event invoked programmatically)'
  $items = @(
    [pscustomobject]@{ Label = 'first';  Value = 'PIPE-A' },
    [pscustomobject]@{ Label = 'second'; Value = 'PIPE-B' }
  )
  $form = New-NvimChooserForm -Items $items
  $list = $form.Controls[0]
  Assert-That 'chooser lists both items'  ($list.Items.Count -eq 2)
  Assert-That 'first item preselected'    ($list.SelectedIndex -eq 0)
  $list.SelectedIndex = 1
  $m = $list.GetType().GetMethod('OnDoubleClick', [Reflection.BindingFlags]'NonPublic,Instance')
  [void]$m.Invoke($list, @([EventArgs]::Empty))
  Assert-That 'double click returns the selected value' ($form.Tag -eq 'PIPE-B') "tag=$($form.Tag)"
  $form.Dispose()

  # -------------------------------------------------------------------------------------------
  Write-Host '== launcher script (dry run: candidate order)'
  $launcher = Join-Path $Root 'open-in-nvim-current.ps1'
  $targetFile = Join-Path $tmp 'target file.txt'
  Set-Content -LiteralPath $targetFile -Value 'hello'

  function Invoke-Launcher {
    param([hashtable]$Env, [string]$Target)
    $saved = @{}
    foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    try {
      $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher $Target 2>&1
      return @{ Out = @($out); Code = $LASTEXITCODE }
    } finally {
      foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
  }

  $base = @{ OPEN_IN_NVIM_ONLY_PIDS = (($P.tui1, $P.tui2) -join ','); USERNAME = 'oin_test_nobody'; OPEN_IN_NVIM_DRYRUN = '1' }
  $r = Invoke-Launcher -Env $base -Target $targetFile
  $cands = @($r.Out | Where-Object { "$_" -like 'candidate:*' } | ForEach-Object { "$_" -replace '^candidate:\s*', '' })
  Assert-That 'dry run exits 0'                       ($r.Code -eq 0) "code=$($r.Code) out=$($r.Out -join ' / ')"
  Assert-That 'newest instance is the first candidate' ($cands.Count -ge 2 -and $cands[0] -eq $newest[0].Pipe) ("cands=" + ($cands -join ' , '))
  Assert-That 'older instance is the second candidate' ($cands.Count -ge 2 -and $cands[1] -eq $newest[1].Pipe)
  Assert-That 'no helper process among candidates'     (-not ($cands -match [regex]::Escape("nvim.$($P.headless).0")) -and -not ($cands -match [regex]::Escape("nvim.$($P.embedhl).0")))

  $envNone = $base.Clone(); $envNone['OPEN_IN_NVIM_ONLY_PIDS'] = '999999'
  $r2 = Invoke-Launcher -Env $envNone -Target $targetFile
  $c2 = @($r2.Out | Where-Object { "$_" -like 'candidate:*' })
  Assert-That 'no instance -> only the per-user pipe fallback' ($c2.Count -eq 1 -and "$($c2[0])" -match 'pipe\\nvim-oin_test_nobody') ("c2=" + ($c2 -join ' , '))

  # -------------------------------------------------------------------------------------------
  Write-Host '== launcher script (real open into the newest throw-away instance)'
  $noDry = @{ OPEN_IN_NVIM_ONLY_PIDS = (($P.tui1, $P.tui2) -join ','); USERNAME = 'oin_test_nobody'; OPEN_IN_NVIM_DRYRUN = $null }
  $r3 = Invoke-Launcher -Env $noDry -Target $targetFile
  Assert-That 'launcher exits 0' ($r3.Code -eq 0) "code=$($r3.Code) out=$($r3.Out -join ' / ')"
  Start-Sleep -Milliseconds 800
  $e2 = Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'join(map(getbufinfo({"buflisted": 1}), "v:val.name"), "|")'
  $e1 = Invoke-NvimEval -Pipe $newest[1].Pipe -Expr 'join(map(getbufinfo({"buflisted": 1}), "v:val.name"), "|")'
  Assert-That 'file (with a space) opened in the newest instance' (($e2 -is [string]) -and ($e2 -like "*target file.txt*")) "buffers=[$e2]"
  Assert-That 'no stray "--" buffer'                              (($e2 -is [string]) -and ($e2 -notmatch '(^|\|)[^|]*\\--($|\|)')) "buffers=[$e2]"
  Assert-That 'older instance left untouched'                     (-not ($e1 -like '*target file.txt*')) "buffers=[$e1]"

  $dir = Join-Path $tmp 'sub dir'; New-Item -ItemType Directory -Force $dir | Out-Null
  $r4 = Invoke-Launcher -Env $noDry -Target $dir
  Start-Sleep -Milliseconds 800
  $cwd = Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'getcwd()'
  Assert-That 'directory open changes cwd of the newest instance' ($cwd -eq $dir) "cwd=[$cwd] want=[$dir]"
  Assert-That 'launcher exits 0 for directory' ($r4.Code -eq 0) "code=$($r4.Code)"

  $envOlder = $noDry.Clone(); $envOlder['OPEN_IN_NVIM_ONLY_PIDS'] = "$($P.tui1)"
  $r5 = Invoke-Launcher -Env $envOlder -Target $targetFile
  Start-Sleep -Milliseconds 800
  $e1b = Invoke-NvimEval -Pipe $newest[1].Pipe -Expr 'join(map(getbufinfo({"buflisted": 1}), "v:val.name"), "|")'
  Assert-That 'restricting to the older PID opens it there' (($e1b -is [string]) -and ($e1b -like '*target file.txt*')) "buffers=[$e1b]"
}
finally {
  # Ask the fixture to stop its own children, then make sure only our own processes are gone.
  try { Set-Content -LiteralPath $stopFile -Value 'stop' } catch {}
  if ($fixture -and -not $fixture.WaitForExit(8000)) { try { $fixture.Kill() } catch {} }
  Start-Sleep -Milliseconds 500
  if ($P) {
    foreach ($id in $P.Values) {
      $p = Get-Process -Id $id -ErrorAction SilentlyContinue
      if ($p) { try { $p.Kill() } catch {} }
    }
  }
  try { [IO.Directory]::Delete($tmp, $true) } catch {}
}

Write-Host ''
Write-Host ("passed: {0}  failed: {1}" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0

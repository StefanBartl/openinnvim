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
$one = Dec ([byte[]](0x91, 0xa1, 0x78))
Assert-That 'one-element array stays an array' (($one -is [array]) -and $one.Count -eq 1 -and $one[0] -eq 'x')
$empty = Dec ([byte[]](0x90))
Assert-That 'empty array stays an array, not $null' (($null -ne $empty) -and ($empty -is [array]) -and $empty.Count -eq 0)
$deep = [byte[]](@(0x91) * 40 + @(0xc0))
$threw = $false
try { [void](Dec $deep) } catch { $threw = ($_.Exception.Message -match 'too deep') }
Assert-That 'absurdly nested reply is rejected, not recursed into' $threw

Write-Host '== unit: msgpack encoder'
function RoundTrip { param($Value) $b = [byte[]](ConvertTo-MsgPackValue $Value); $p = 0; return ,(ConvertFrom-MsgPackValue -Buf $b -Pos ([ref]$p)) }
$rt = RoundTrip ([object[]]@('a', [object[]]@('b', 'c'), $true, $false, $null, 5))
Assert-That 'nested array round trip' (($rt[0] -eq 'a') -and ($rt[1].Count -eq 2) -and ($rt[1][1] -eq 'c') -and ($rt[2] -eq $true) -and ($rt[3] -eq $false) -and ($null -eq $rt[4]) -and ($rt[5] -eq 5)) ("got=" + ($rt -join ','))
$longStr = ('p' * 300)
Assert-That 'str16 (300 chars) round trip' ((RoundTrip $longStr) -eq $longStr)
$weirdName = "My Dir (1) #2 [x] 'q' %p & more"
Assert-That 'special characters survive the encoder' ((RoundTrip $weirdName) -eq $weirdName)

Write-Host '== unit: command-line quoting (checked against CommandLineToArgvW)'
Add-Type -Namespace OinTest -Name Argv -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll", SetLastError = true)]
public static extern System.IntPtr CommandLineToArgvW([System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPWStr)] string lpCmdLine, out int pNumArgs);
'@
function Split-Argv {
  param([string]$Line)
  $n = 0
  $ptr = [OinTest.Argv]::CommandLineToArgvW($Line, [ref]$n)
  $out = @()
  for ($i = 0; $i -lt $n; $i++) {
    $sp = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($ptr, $i * [IntPtr]::Size)
    $out += [System.Runtime.InteropServices.Marshal]::PtrToStringUni($sp)
  }
  return ,$out
}
$samples = @('C:\dir\', 'C:\a b\', 'plain', 'with space', 'say "hi"', '\\server\share dir\', 'end\\', 'a\"b', "it's")
foreach ($smp in $samples) {
  $line = 'prog.exe ' + (ConvertTo-CommandLineArg $smp) + ' tail'
  $argv = Split-Argv $line
  Assert-That ("quoting round trip: [$smp]") (($argv.Count -eq 3) -and ($argv[1] -eq $smp) -and ($argv[2] -eq 'tail')) ("argv=" + ($argv -join ' | '))
}

# ---------------------------------------------------------------------------------------------
Write-Host '== fixture: starting throw-away instances'
$runStart = (Get-Date).AddSeconds(-2)
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
  Assert-That 'headless and embed-headless (no UI) filtered' ((@($inst | Where-Object { $_.Pid -eq $P.headless -or $_.Pid -eq $P.embedhl })).Count -eq 0)
  Assert-That 'the headless helper does own a pipe (so the filter is what excludes it)' ((@(Get-NvimPipeEntries | Where-Object { $_.Pid -eq $P.headless })).Count -ge 1)
  $uiHeadless = Invoke-NvimEval -Pipe ('\\.\pipe\nvim.' + $P.headless + '.0') -Expr 'len(nvim_list_uis())'
  $uiGui = Invoke-NvimEval -Pipe ('\\.\pipe\nvim.' + $P.gui1 + '.0') -Expr 'len(nvim_list_uis())'
  Assert-That 'UI count is what separates them' (($uiHeadless -eq 0) -and ($uiGui -ge 1)) "headless=[$uiHeadless] gui=[$uiGui]"
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
    param([hashtable]$Env, [string]$Target, [string]$Script = $launcher)
    $saved = @{}
    foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    try {
      $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script $Target 2>&1
      return @{ Out = @($out); Code = $LASTEXITCODE }
    } finally {
      foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
  }

  # OPEN_IN_NVIM_NO_SPAWN: if discovery ever failed, the launcher must report it instead of opening a
  # real terminal window with a new Neovim.
  $base = @{ OPEN_IN_NVIM_ONLY_PIDS = (($P.tui1, $P.tui2) -join ','); USERNAME = 'oin_test_nobody'; OPEN_IN_NVIM_DRYRUN = '1'; OPEN_IN_NVIM_NO_SPAWN = '1' }
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
  $noDry = @{ OPEN_IN_NVIM_ONLY_PIDS = (($P.tui1, $P.tui2) -join ','); USERNAME = 'oin_test_nobody'; OPEN_IN_NVIM_DRYRUN = $null; OPEN_IN_NVIM_NO_SPAWN = '1' }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $r3 = Invoke-Launcher -Env $noDry -Target $targetFile
  $openMs = $sw.ElapsedMilliseconds
  Assert-That 'launcher exits 0' ($r3.Code -eq 0) "code=$($r3.Code) out=$($r3.Out -join ' / ')"
  Write-Host "       (launcher wall time incl. PowerShell start: $openMs ms)"
  $e2 = Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'join(map(getbufinfo({"buflisted": 1}), "v:val.name"), "|")'
  $e1 = Invoke-NvimEval -Pipe $newest[1].Pipe -Expr 'join(map(getbufinfo({"buflisted": 1}), "v:val.name"), "|")'
  Assert-That 'file (with a space) opened in the newest instance' (($e2 -is [string]) -and ($e2 -like "*target file.txt*")) "buffers=[$e2]"
  Assert-That 'no stray "--" buffer'                              (($e2 -is [string]) -and ($e2 -notmatch '(^|\|)[^|]*\\--($|\|)')) "buffers=[$e2]"
  Assert-That 'older instance left untouched'                     (-not ($e1 -like '*target file.txt*')) "buffers=[$e1]"

  $dir = Join-Path $tmp 'sub dir'; New-Item -ItemType Directory -Force $dir | Out-Null
  # Newest instance (gui2) has a :Filetree stand-in: a folder must go there, not into cd + edit.
  $r4 = Invoke-Launcher -Env $noDry -Target $dir
  $ft = @(Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'get(g:, "ft_args", [])')
  Assert-That 'launcher exits 0 for directory' ($r4.Code -eq 0) "code=$($r4.Code)"
  Assert-That 'folder is handed to :Filetree open as one argument (space intact)' (($ft.Count -eq 2) -and ($ft[0] -eq 'open') -and ($ft[1] -eq $dir)) "g:ft_args=[$($ft -join ' | ')]"
  $cwdFt = Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'getcwd()'
  Assert-That 'with :Filetree the cwd is left to filetree.nvim' ($cwdFt -ne $dir) "cwd=[$cwdFt]"

  # Names that command-line or key parsing would mangle: #, %, [, (, ', &. The old fnameescape route
  # failed for these without any error.
  $weirdDir = Join-Path $tmp "My Dir (1) #2 [x] 'q' %p & more"; New-Item -ItemType Directory -Force $weirdDir | Out-Null
  [void](Invoke-Launcher -Env $noDry -Target $weirdDir)
  $ftw = @(Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'get(g:, "ft_args", [])')
  Assert-That 'folder with #, %, [, (, quote and & arrives unchanged' (($ftw.Count -eq 2) -and ($ftw[1] -eq $weirdDir)) "g:ft_args=[$($ftw -join ' | ')]"
  $weirdFile = Join-Path $tmp "a#b%c [x] 'q' & (1).txt"; Set-Content -LiteralPath $weirdFile -Value 'x'
  $cwdBeforeFile = Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'getcwd()'
  $r6 = Invoke-Launcher -Env $noDry -Target $weirdFile
  $e2w = Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'join(map(getbufinfo({"buflisted": 1}), "v:val.name"), "|")'
  Assert-That 'file with #, %, [, (, quote and & opens' (($r6.Code -eq 0) -and ($e2w -is [string]) -and ($e2w.Contains($weirdFile))) "code=$($r6.Code) buffers=[$e2w]"
  Assert-That 'opening a file does not change the working directory' ((Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'getcwd()') -eq $cwdBeforeFile)

  # Older instance (gui1) has no :Filetree: fall back to cd + directory view.
  $envNoFt = $noDry.Clone(); $envNoFt['OPEN_IN_NVIM_ONLY_PIDS'] = "$($P.tui1)"
  $r4b = Invoke-Launcher -Env $envNoFt -Target $dir
  $cwd = Invoke-NvimEval -Pipe $newest[1].Pipe -Expr 'getcwd()'
  Assert-That 'without :Filetree the directory open changes cwd' ($cwd -eq $dir) "cwd=[$cwd] want=[$dir]"
  Assert-That 'launcher exits 0 for directory (fallback)' ($r4b.Code -eq 0) "code=$($r4b.Code)"
  [void](Invoke-Launcher -Env $envNoFt -Target $weirdDir)
  $cwdW = Invoke-NvimEval -Pipe $newest[1].Pipe -Expr 'getcwd()'
  Assert-That 'cd + directory view works for the special-character folder' ($cwdW -eq $weirdDir) "cwd=[$cwdW]"

  # FOLDER_OPENS_IN lives in the config file, so the 'edit' mode is exercised through the lib directly.
  $viaEdit = Invoke-NvimOpen -Pipe $newest[0].Pipe -Path $dir -IsDir $true -FolderMode 'edit'
  Assert-That 'FolderMode edit skips :Filetree even when the instance has it' (($viaEdit.Ok) -and ($viaEdit.Result -eq 'edit') -and ((Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'getcwd()') -eq $dir))

  # A reached instance that refuses is reported, not mistaken for an unreachable one.
  $bad = Invoke-NvimRpc -Pipe $newest[0].Pipe -Method 'nvim_exec_lua' -Params @('error("boom")', [object[]]@())
  Assert-That 'error reply is Connected but not Ok, with the message' (($bad.Connected) -and (-not $bad.Ok) -and ("$($bad.Error)" -match 'boom')) "err=[$($bad.Error)]"
  $none = Invoke-NvimRpc -Pipe '\\.\pipe\nvim.999999.0' -Method 'nvim_eval' -Params @('1') -TimeoutMs 300
  Assert-That 'missing pipe is not Connected' ((-not $none.Connected) -and (-not $none.Ok))

  $envOlder = $noDry.Clone(); $envOlder['OPEN_IN_NVIM_ONLY_PIDS'] = "$($P.tui1)"
  $r5 = Invoke-Launcher -Env $envOlder -Target $targetFile
  $e1b = Invoke-NvimEval -Pipe $newest[1].Pipe -Expr 'join(map(getbufinfo({"buflisted": 1}), "v:val.name"), "|")'
  Assert-That 'restricting to the older PID opens it there' (($e1b -is [string]) -and ($e1b -like '*target file.txt*')) "buffers=[$e1b]"

  # A folder whose name looks like an environment variable is a real path, not something to expand.
  $pctDir = Join-Path $tmp '%TEMP%x'; New-Item -ItemType Directory -Force $pctDir | Out-Null
  [void](Invoke-Launcher -Env $noDry -Target $pctDir)
  $ftp = @(Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'get(g:, "ft_args", [])')
  Assert-That 'a folder named %TEMP%x is not environment-expanded' (($ftp.Count -eq 2) -and ($ftp[1] -eq $pctDir)) "g:ft_args=[$($ftp -join ' | ')]"

  # -------------------------------------------------------------------------------------------
  Write-Host '== launcher script (no instance reachable)'
  $envNoInst = @{ OPEN_IN_NVIM_ONLY_PIDS = '999999'; USERNAME = 'oin_test_nobody'; OPEN_IN_NVIM_DRYRUN = $null; OPEN_IN_NVIM_NO_SPAWN = '1'; OPEN_IN_NVIM_SPAWN_DRYRUN = $null }
  $rn = Invoke-Launcher -Env $envNoInst -Target $targetFile
  Assert-That 'safety stop: exit code 3 and no window' (($rn.Code -eq 3) -and (($rn.Out -join ' ') -match 'no reachable instance')) "code=$($rn.Code) out=$($rn.Out -join ' / ')"

  # A configured NVIM_SERVER pipe nobody listens on must fail fast: the command line cannot do better
  # than RPC for a pipe, and each attempt there used to cost seconds before the new instance started.
  $cfgCopy = Join-Path $tmp 'cfg copy'; New-Item -ItemType Directory -Force $cfgCopy | Out-Null
  foreach ($f in 'open-in-nvim-current.ps1', 'open-in-nvim.lib.ps1') { Copy-Item -LiteralPath (Join-Path $Root $f) -Destination $cfgCopy }
  Set-Content -LiteralPath (Join-Path $cfgCopy 'open-in-nvim.config.ps1') -Value ("`$Cfg = [ordered]@{ NVIM_BIN = '" + $nvim + "'; NVIM_SERVER = '\\.\pipe\oin-nobody-listens-here' }")
  $swm = [Diagnostics.Stopwatch]::StartNew()
  $rm = Invoke-Launcher -Env $envNoInst -Target $targetFile -Script (Join-Path $cfgCopy 'open-in-nvim-current.ps1')
  $missMs = $swm.ElapsedMilliseconds
  Assert-That 'a configured pipe that does not exist is given up on quickly' (($rm.Code -eq 3) -and ($missMs -lt 2200)) "code=$($rm.Code) ms=$missMs"
  Write-Host "       (unreachable configured pipe -> exit 3 in $missMs ms incl. PowerShell start)"

  # The command that would start a new Neovim (printed instead of started). Windows PowerShell 5.1 did
  # not bind a parameter called $args, so the new instance used to get no --listen and no file.
  $spaceDir = Join-Path $tmp 'My Dir'; New-Item -ItemType Directory -Force $spaceDir | Out-Null
  $spaceFile = Join-Path $spaceDir 'new file.txt'; Set-Content -LiteralPath $spaceFile -Value 'x'
  $envSpawn = $envNoInst.Clone(); $envSpawn['OPEN_IN_NVIM_NO_SPAWN'] = $null; $envSpawn['OPEN_IN_NVIM_SPAWN_DRYRUN'] = '1'
  $rs = Invoke-Launcher -Env $envSpawn -Target $spaceFile
  $spawn = @($rs.Out | Where-Object { "$_" -like 'spawn:*' })
  $line = "$($spawn[0])"
  Assert-That 'new-instance command is produced and exits 0' (($rs.Code -eq 0) -and ($spawn.Count -eq 1)) "code=$($rs.Code) out=$($rs.Out -join ' / ')"
  Assert-That 'new instance gets --listen with the per-user pipe' ($line.Contains('"--listen" "\\.\pipe\nvim-oin_test_nobody"')) "line=$line"
  Assert-That 'new instance gets the file after --' ($line.Contains('"--" "' + $spaceFile + '"')) "line=$line"
  Assert-That 'working directory with a space stays one argument' ($line.Contains('"' + $spaceDir + '"')) "line=$line"
  $rsd = Invoke-Launcher -Env $envSpawn -Target $spaceDir
  $lined = "$(@($rsd.Out | Where-Object { "$_" -like 'spawn:*' })[0])"
  Assert-That 'folder target: --listen but no file argument' ($lined.Contains('"--listen"') -and -not $lined.Contains('new file.txt')) "line=$lined"

  # The "new instance" entry (open-in-nvim.ps1) had the same lost-$args bug: the file never reached nvim.
  $newScript = Join-Path $Root 'open-in-nvim.ps1'
  $envNew = @{ OPEN_IN_NVIM_SPAWN_DRYRUN = '1' }
  $rnew = Invoke-Launcher -Env $envNew -Target $spaceFile -Script $newScript
  $linen = "$(@($rnew.Out | Where-Object { "$_" -like 'spawn:*' })[0])"
  Assert-That 'new-instance entry: file reaches nvim after --' (($rnew.Code -eq 0) -and $linen.Contains('"--" "' + $spaceFile + '"')) "code=$($rnew.Code) line=$linen"
  Assert-That 'new-instance entry: folder with a space is one argument' ($linen.Contains('"' + $spaceDir + '"')) "line=$linen"
  $rroot = Invoke-Launcher -Env $envNew -Target 'C:\' -Script $newScript
  $liner = "$(@($rroot.Out | Where-Object { "$_" -like 'spawn:*' })[0])"
  if ($liner -match '"--cwd"|"-d"') {
    Assert-That 'drive root keeps its closing quote (trailing backslash doubled)' ($liner.Contains('"C:\\"')) "line=$liner"
  }

  # -------------------------------------------------------------------------------------------
  Write-Host '== folder path normalisation'
  Assert-That 'trailing backslash is removed'          ((ConvertTo-PlainDirPath 'C:\a b\c\') -eq 'C:\a b\c')
  Assert-That 'several trailing separators are removed' ((ConvertTo-PlainDirPath 'C:\a\\/') -eq 'C:\a')
  Assert-That 'a drive root keeps its backslash'        ((ConvertTo-PlainDirPath 'C:\') -eq 'C:\')
  Assert-That 'a path without trailing separator stays' ((ConvertTo-PlainDirPath 'C:\a\b') -eq 'C:\a\b')

  Write-Host '== focus helpers'
  # Pure part: walking up a process tree to the first ancestor that owns a window.
  $tree = @{ 10 = 20; 20 = 30; 30 = 40; 40 = 0 }
  Assert-That 'window owner found up the tree' ((Find-WindowOwnerPid -StartPid 10 -ParentOf $tree -HasWindow { param($x) $x -eq 30 }) -eq 30)
  Assert-That 'the start process itself is not considered' ($null -eq (Find-WindowOwnerPid -StartPid 10 -ParentOf $tree -HasWindow { param($x) $x -eq 10 }))
  Assert-That 'no window anywhere returns null' ($null -eq (Find-WindowOwnerPid -StartPid 10 -ParentOf $tree -HasWindow { param($x) $false }))
  $loop = @{ 10 = 20; 20 = 10 }
  Assert-That 'a parent loop ends instead of spinning' ($null -eq (Find-WindowOwnerPid -StartPid 10 -ParentOf $loop -HasWindow { param($x) $false }))
  Assert-That 'unknown start process returns null' ($null -eq (Find-WindowOwnerPid -StartPid 99 -ParentOf $tree -HasWindow { param($x) $true }))
  # The Win32 part cannot be asserted without a window, but it must never throw: a dead pipe gives $false.
  Assert-That 'focus on an unreachable instance fails quietly' ((Set-NvimInstanceFocus -Pipe '\\.\pipe\nvim.999999.0') -eq $false)

  # -------------------------------------------------------------------------------------------
  Write-Host '== install / uninstall (throw-away folder and registry key, never the real entries)'
  $installer = Join-Path $Root 'install.ps1'
  $uninstaller = Join-Path $Root 'uninstall.ps1'
  $hkcu = [Microsoft.Win32.Registry]::CurrentUser
  $testRoot = 'Software\oin_test_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
  $classes = $testRoot + '\Classes'
  function Get-RegDefault {
    param([string]$Sub, [string]$Name = '')
    $k = $hkcu.OpenSubKey("$classes\$Sub")
    if (-not $k) { return $null }
    $v = $k.GetValue($Name); $k.Close(); return $v
  }
  function Invoke-PsFile {
    param([string]$File, [string[]]$FileArgs)
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $File @FileArgs 2>&1
    return @{ Out = @($out); Code = $LASTEXITCODE }
  }
  $instDir = Join-Path $tmp 'inst dir'
  try {
    # a legacy entry of an earlier version must disappear
    $legacy = $hkcu.CreateSubKey("$classes\*\shell\Open_in_Neovim_nvr"); $legacy.Close()

    $ri = Invoke-PsFile $installer @('-InstallDir', $instDir, '-ClassesKey', $classes, '-NvimExe', $nvim)
    Assert-That 'install exits 0' ($ri.Code -eq 0) "code=$($ri.Code) out=$($ri.Out -join ' / ')"
    $expectNew = 'wscript.exe //nologo "' + (Join-Path $instDir 'open-in-nvim.vbs') + '" "%1"'
    $expectCur = 'wscript.exe //nologo "' + (Join-Path $instDir 'open-in-nvim-current.vbs') + '" "%1"'
    $expectBg  = 'wscript.exe //nologo "' + (Join-Path $instDir 'open-in-nvim-current.vbs') + '" "%V"'
    Assert-That 'file entry runs the installed new-instance VBS'     ((Get-RegDefault '*\shell\Open_in_Neovim_new\command') -eq $expectNew)
    Assert-That 'file entry runs the installed current-instance VBS' ((Get-RegDefault '*\shell\Open_in_Neovim_current\command') -eq $expectCur)
    Assert-That 'folder entries exist'                               (((Get-RegDefault 'Directory\shell\Open_in_Neovim_new\command') -ne $null) -and ((Get-RegDefault 'Directory\shell\Open_in_Neovim_current\command') -eq $expectCur))
    Assert-That 'folder background passes %V'                        ((Get-RegDefault 'Directory\Background\shell\Open_in_Neovim_current\command') -eq $expectBg)
    Assert-That 'labels and icon are set'                            (((Get-RegDefault '*\shell\Open_in_Neovim_current') -eq 'Open with Neovim (current instance)') -and ((Get-RegDefault '*\shell\Open_in_Neovim_new') -eq 'Open with Neovim (new instance)') -and ((Get-RegDefault '*\shell\Open_in_Neovim_new' 'Icon') -eq $nvim))
    Assert-That 'legacy entry removed'                               ($null -eq (Get-RegDefault '*\shell\Open_in_Neovim_nvr'))
    $missingFiles = @('open-in-nvim.vbs', 'open-in-nvim-current.vbs', 'open-in-nvim.ps1', 'open-in-nvim-current.ps1', 'open-in-nvim.lib.ps1', 'open-in-nvim.config.ps1', 'install.manifest.txt') | Where-Object { -not (Test-Path -LiteralPath (Join-Path $instDir $_)) }
    Assert-That 'all launcher files, the config and the manifest are installed' (@($missingFiles).Count -eq 0) "missing=$($missingFiles -join ',')"
    $cfgText = [IO.File]::ReadAllText((Join-Path $instDir 'open-in-nvim.config.ps1'))
    Assert-That 'the detected nvim.exe is written into the new config' ($cfgText -match ("NVIM_BIN\s*=\s*'" + [regex]::Escape($nvim) + "'"))
    Assert-That 'no hard-coded C:\tools path is installed'            (-not ((Get-Content -LiteralPath (Join-Path $instDir 'open-in-nvim-current.vbs') -Raw) -match 'C:\\tools'))

    # running again: config is kept, -Force replaces it
    Add-Content -LiteralPath (Join-Path $instDir 'open-in-nvim.config.ps1') -Value '# my own edit'
    [void](Invoke-PsFile $installer @('-InstallDir', $instDir, '-ClassesKey', $classes, '-NvimExe', $nvim))
    Assert-That 're-install keeps an edited config' ([IO.File]::ReadAllText((Join-Path $instDir 'open-in-nvim.config.ps1')) -match 'my own edit')
    [void](Invoke-PsFile $installer @('-InstallDir', $instDir, '-ClassesKey', $classes, '-NvimExe', $nvim, '-Force'))
    Assert-That '-Force replaces the config' (-not ([IO.File]::ReadAllText((Join-Path $instDir 'open-in-nvim.config.ps1')) -match 'my own edit'))

    # the installed chain end to end: VBS -> PowerShell -> RPC -> the throw-away instance
    $vbsFile = Join-Path $tmp 'via vbs.txt'; Set-Content -LiteralPath $vbsFile -Value 'v'
    $vbsDir = Join-Path $tmp 'vbs dir'; New-Item -ItemType Directory -Force $vbsDir | Out-Null
    $savedEnv = @{}
    $vbsEnv = @{ OPEN_IN_NVIM_ONLY_PIDS = (($P.tui1, $P.tui2) -join ','); USERNAME = 'oin_test_nobody'; OPEN_IN_NVIM_NO_SPAWN = '1' }
    foreach ($k in $vbsEnv.Keys) { $savedEnv[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vbsEnv[$k]) }
    try {
      & wscript.exe //nologo (Join-Path $instDir 'open-in-nvim-current.vbs') $vbsFile
      $seen = $false
      for ($i = 0; $i -lt 40 -and -not $seen; $i++) {
        Start-Sleep -Milliseconds 250
        $bufs = Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'join(map(getbufinfo({"buflisted": 1}), "v:val.name"), "|")'
        $seen = ($bufs -is [string]) -and $bufs.Contains($vbsFile)
      }
      Assert-That 'installed VBS opens a file with a space in the running instance' $seen "buffers=[$bufs]"

      # a folder path ending in a backslash, with a space: the VBS must not let it eat its closing quote
      [void](Invoke-NvimRpc -Pipe $newest[0].Pipe -Method 'nvim_exec_lua' -Params @('vim.g.ft_args = nil', [object[]]@()))   # earlier tests left a value
      & wscript.exe //nologo (Join-Path $instDir 'open-in-nvim-current.vbs') ($vbsDir + '\')
      $ftv = @()
      for ($i = 0; $i -lt 40 -and $ftv.Count -ne 2; $i++) {
        Start-Sleep -Milliseconds 250
        $ftv = @(Invoke-NvimEval -Pipe $newest[0].Pipe -Expr 'get(g:, "ft_args", [])')
      }
      Assert-That 'installed VBS handles a folder path with a space and a trailing backslash' (($ftv.Count -eq 2) -and ($ftv[1] -eq $vbsDir)) "g:ft_args=[$($ftv -join ' | ')]"
    } finally {
      foreach ($k in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $savedEnv[$k]) }
    }

    # uninstall: entries and launcher files go, the edited config stays, the folder stays while it is not empty
    $ru = Invoke-PsFile $uninstaller @('-InstallDir', $instDir, '-ClassesKey', $classes, '-RemoveFiles')
    Assert-That 'uninstall exits 0' ($ru.Code -eq 0) "code=$($ru.Code) out=$($ru.Out -join ' / ')"
    $left = @('*\shell\Open_in_Neovim_new', '*\shell\Open_in_Neovim_current', 'Directory\shell\Open_in_Neovim_new', 'Directory\shell\Open_in_Neovim_current', 'Directory\Background\shell\Open_in_Neovim_new', 'Directory\Background\shell\Open_in_Neovim_current') | Where-Object { $null -ne $hkcu.OpenSubKey("$classes\$_") }
    Assert-That 'all six entries are removed' (@($left).Count -eq 0) "left=$($left -join ',')"
    Assert-That 'launcher files are removed'  (-not (Test-Path -LiteralPath (Join-Path $instDir 'open-in-nvim-current.ps1')))
    Assert-That 'the config is kept without -RemoveConfig' (Test-Path -LiteralPath (Join-Path $instDir 'open-in-nvim.config.ps1'))

    # reinstall, then remove everything including the config: the folder goes too
    [void](Invoke-PsFile $installer @('-InstallDir', $instDir, '-ClassesKey', $classes, '-NvimExe', $nvim))
    [void](Invoke-PsFile $uninstaller @('-InstallDir', $instDir, '-ClassesKey', $classes, '-RemoveFiles', '-RemoveConfig'))
    Assert-That '-RemoveConfig removes the config and the then-empty folder' (-not (Test-Path -LiteralPath $instDir))

    # in place: entries point at the repository, nothing is copied, its config is untouched
    $cfgBefore = (Get-FileHash -LiteralPath (Join-Path $Root 'open-in-nvim.config.ps1')).Hash
    [void](Invoke-PsFile $installer @('-InstallDir', $Root, '-ClassesKey', $classes, '-NvimExe', $nvim))
    Assert-That 'in-place install points the entry at the repository' ((Get-RegDefault '*\shell\Open_in_Neovim_current\command') -eq ('wscript.exe //nologo "' + (Join-Path $Root 'open-in-nvim-current.vbs') + '" "%1"'))
    Assert-That 'in-place install leaves the repository config alone' ($cfgBefore -eq (Get-FileHash -LiteralPath (Join-Path $Root 'open-in-nvim.config.ps1')).Hash)
    Assert-That 'in-place install writes no manifest into the repository' (-not (Test-Path -LiteralPath (Join-Path $Root 'install.manifest.txt')))
    [void](Invoke-PsFile $uninstaller @('-InstallDir', $Root, '-ClassesKey', $classes, '-RemoveFiles', '-RemoveConfig'))
    Assert-That 'uninstall never deletes files of the repository itself' ((Test-Path -LiteralPath (Join-Path $Root 'open-in-nvim-current.ps1')) -and (Test-Path -LiteralPath (Join-Path $Root 'open-in-nvim.config.ps1')))

    # dry run writes nothing
    $dry = Join-Path $tmp 'dry dir'
    $rd = Invoke-PsFile $installer @('-InstallDir', $dry, '-ClassesKey', ($testRoot + '\Dry'), '-NvimExe', $nvim, '-DryRun')
    Assert-That 'dry run changes neither folder nor registry' (($rd.Code -eq 0) -and -not (Test-Path -LiteralPath $dry) -and ($null -eq $hkcu.OpenSubKey($testRoot + '\Dry')))
  } finally {
    try { $hkcu.DeleteSubKeyTree($testRoot, $false) } catch {}
  }
}
finally {
  # Ask the fixture to stop its own children, then make sure only our own processes are gone.
  try { Set-Content -LiteralPath $stopFile -Value 'stop' } catch {}
  if ($fixture -and -not $fixture.WaitForExit(8000)) { try { $fixture.Kill() } catch {} }
  Start-Sleep -Milliseconds 500
  if ($P) {
    foreach ($id in $P.Values) {
      # A PID can be reused once its process is gone: only touch an nvim that started during this run.
      $p = Get-Process -Id $id -ErrorAction SilentlyContinue
      if ($p -and $p.ProcessName -eq 'nvim' -and $p.StartTime -ge $runStart) { try { $p.Kill() } catch {} }
    }
  }
  try { [IO.Directory]::Delete($tmp, $true) } catch {}
}

Write-Host ''
Write-Host ("passed: {0}  failed: {1}" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0

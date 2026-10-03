# tests/run-tests.ps1
# Tests for the native launcher (src\*.cs -> OpenInNvim.exe). Run with Windows PowerShell 5.1:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
#
# What it does: builds the exe into a temp folder, calls its public static methods through reflection
# (unit tests), then runs the exe against throw-away Neovim instances (tests\fixture.lua).
#
# Safe by construction: the launcher is only ever started with OPEN_IN_NVIM_ONLY_PIDS (the fixture's
# PIDs), a fake USERNAME (so a real per-user pipe nvim-<you> is never touched) and OPEN_IN_NVIM_NO_SPAWN
# or OPEN_IN_NVIM_SPAWN_DRYRUN (no window ever opens). Every process started here is stopped by its own
# PID in the finally block. No dependency on module functions such as Get-FileHash (an inherited
# PowerShell 7 PSModulePath hides them). ASCII only.
#
# The three parameters are internal: with -FakeServerNames this script runs as the fake pipe server
# of the trust tests (a process that is not Neovim and owns Neovim-looking pipe names).

param(
  [string]$FakeServerNames = '',
  [string]$FakeServerLog = '',
  [int]$FakeServerSeconds = 90
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------------------------
# Fake pipe server mode
# ---------------------------------------------------------------------------------------------
if ($FakeServerNames) {
  Add-Type -Namespace OinFake -Name Pipe -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern IntPtr CreateNamedPipeW(string name, uint openMode, uint pipeMode, uint maxInstances, uint outSize, uint inSize, uint defaultTimeout, IntPtr securityAttributes);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool ConnectNamedPipe(IntPtr pipe, IntPtr overlapped);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool DisconnectNamedPipe(IntPtr pipe);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool ReadFile(IntPtr file, byte[] buffer, uint count, out uint read, IntPtr overlapped);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool WriteFile(IntPtr file, byte[] buffer, uint count, out uint written, IntPtr overlapped);
'@
  function Write-FakeLog { param([string]$Line) [IO.File]::AppendAllText($FakeServerLog, $Line + "`r`n") }
  $served = @()
  foreach ($name in [IO.File]::ReadAllLines($FakeServerNames, [Text.Encoding]::UTF8)) {
    if (-not $name) { continue }
    # PIPE_ACCESS_DUPLEX, byte mode + PIPE_NOWAIT (so one thread can poll all pipes), one instance.
    $handle = [OinFake.Pipe]::CreateNamedPipeW('\\.\pipe\' + $name, 3, 1, 1, 65536, 65536, 0, [IntPtr]::Zero)
    if ($handle.ToInt64() -eq -1) { Write-FakeLog ('create-failed ' + $name + ' error ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); continue }
    $served += [pscustomobject]@{ Name = $name; Handle = $handle }
    Write-FakeLog ('created ' + $name)
  }
  # What a real, idle Neovim with a UI would answer to the launcher's three requests. If the trust check
  # were missing, the launcher would take this server for a usable instance and "open" the file here.
  $answer = [byte[]](0x94, 0x01, 0x01, 0xc0, 0x82, 0xa4, 0x6d, 0x6f, 0x64, 0x65, 0xa1, 0x6e, 0xa8, 0x62, 0x6c, 0x6f, 0x63, 0x6b, 0x69, 0x6e, 0x67, 0xc2,
    0x94, 0x01, 0x02, 0xc0, 0x01,
    0x94, 0x01, 0x03, 0xc0, 0xa4, 0x66, 0x69, 0x6c, 0x65)
  $buffer = New-Object byte[] 65536
  Write-FakeLog ('ready pid=' + $PID)
  $deadline = [DateTime]::UtcNow.AddSeconds($FakeServerSeconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    foreach ($s in $served) {
      $connected = [OinFake.Pipe]::ConnectNamedPipe($s.Handle, [IntPtr]::Zero)
      $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
      # 535: a client is connected. 232: a client was connected and has closed its end already.
      if ($connected -or $err -eq 535 -or $err -eq 232) {
        $read = [uint32]0
        if ([OinFake.Pipe]::ReadFile($s.Handle, $buffer, 65536, [ref]$read, [IntPtr]::Zero) -and $read -gt 0) {
          Write-FakeLog ('received ' + $read + ' bytes on ' + $s.Name)
          $written = [uint32]0
          [void][OinFake.Pipe]::WriteFile($s.Handle, $answer, $answer.Length, [ref]$written, [IntPtr]::Zero)
        }
        if ($err -eq 232) {
          Write-FakeLog ('client came and went on ' + $s.Name)
          [void][OinFake.Pipe]::DisconnectNamedPipe($s.Handle)
        }
      }
    }
    Start-Sleep -Milliseconds 10
  }
  exit 0
}

# ---------------------------------------------------------------------------------------------
# Test run
# ---------------------------------------------------------------------------------------------
$Root = Split-Path -Parent $PSScriptRoot
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$nvim = $env:NVIM_EXE
if (-not $nvim -or -not [IO.File]::Exists($nvim)) { $nvim = 'C:\Program Files\Neovim\bin\nvim.exe' }
if (-not [IO.File]::Exists($nvim)) { throw 'nvim.exe not found; set NVIM_EXE' }

$script:pass = 0
$script:fail = 0
function Assert-That {
  param([string]$Name, [bool]$Cond, [string]$Detail = '')
  if ($Cond) { $script:pass++; Write-Host "  ok   $Name" }
  else { $script:fail++; Write-Host "  FAIL $Name  $Detail" -ForegroundColor Red }
}

function Invoke-Bounded {
  <#
    .SYNOPSIS
      Run a program with an exact command line, extra environment and a time limit; never a window.
    .RETURNS
      Code, Text (stdout), Lines (stdout lines), Err (stderr), Ms, ProcId, TimedOut.
  #>
  param([string]$Exe, [string]$ArgLine, [hashtable]$Env = @{}, [string]$Cwd = '', [int]$LimitMs = 30000)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = $ArgLine
  if ($Cwd) { $psi.WorkingDirectory = $Cwd }
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
  foreach ($k in $Env.Keys) {
    if ($null -eq $Env[$k]) { $psi.EnvironmentVariables.Remove($k) } else { $psi.EnvironmentVariables[$k] = [string]$Env[$k] }
  }
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $proc = [Diagnostics.Process]::Start($psi)
  $outTask = $proc.StandardOutput.ReadToEndAsync()
  $errTask = $proc.StandardError.ReadToEndAsync()
  $timedOut = $false
  if (-not $proc.WaitForExit($LimitMs)) { $timedOut = $true; try { $proc.Kill() } catch {} }
  $proc.WaitForExit()
  $ms = $watch.Elapsed.TotalMilliseconds
  $text = $outTask.Result
  return [pscustomobject]@{
    Code = $proc.ExitCode; Text = $text; Lines = @($text -split "`r?`n" | Where-Object { $_ -ne '' })
    Err = $errTask.Result; Ms = $ms; ProcId = $proc.Id; TimedOut = $timedOut; Log = @()
  }
}

function Remove-OwnTree {
  <#
    .SYNOPSIS
      Delete a folder this run created, bottom-up, one non-recursive call per entry.
    .NOTES
      A reparse point (junction, symlink) is removed as a link and never entered.
  #>
  param([string]$Dir)
  if (-not [IO.Directory]::Exists($Dir)) { return }
  foreach ($f in [IO.Directory]::GetFiles($Dir)) { try { [IO.File]::Delete($f) } catch {} }
  foreach ($d in [IO.Directory]::GetDirectories($Dir)) {
    $isLink = (([IO.File]::GetAttributes($d)) -band [IO.FileAttributes]::ReparsePoint) -ne 0
    if (-not $isLink) { Remove-OwnTree $d } else { try { [IO.Directory]::Delete($d, $false) } catch {} }
  }
  try { [IO.Directory]::Delete($Dir, $false) } catch {}
}

$runStart = (Get-Date).AddSeconds(-2)
$tag = [Guid]::NewGuid().ToString('N').Substring(0, 8)
# A space in the folder name: every path of the run has to survive quoting.
$tmp = Join-Path $env:TEMP ('oin native ' + $tag)
[void][IO.Directory]::CreateDirectory($tmp)
$bin = Join-Path $tmp 'bin dir'
$exe = Join-Path $bin 'OpenInNvim.exe'
$ini = Join-Path $bin 'open-in-nvim.ini'
$runLog = Join-Path $tmp 'launcher.log'

$fixtureProc = $null
$fakeProc = $null
$Pids = $null
$clients = @()

try {
  # -------------------------------------------------------------------------------------------
  Write-Host '== build'
  $build = Invoke-Bounded -Exe $ps51 -ArgLine ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Root 'build.ps1') + '" -OutDir "' + $bin + '"') -LimitMs 120000
  Assert-That 'build.ps1 exits 0 and prints the exe path' (($build.Code -eq 0) -and ($build.Lines.Count -ge 1) -and ($build.Lines[-1] -eq $exe)) ("code=$($build.Code) out=$($build.Text) err=$($build.Err)")
  Assert-That 'no compiler output (zero warnings)' ($build.Lines.Count -eq 1) ("out=$($build.Text)")
  if (-not [IO.File]::Exists($exe)) { throw 'build failed; nothing to test' }

  # Loaded from bytes: the file stays unlocked, the temp folder can be removed at the end.
  [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes($exe))

  function ConvertFrom-Hex { param([string]$Hex) return ,[byte[]]@($Hex -split '\s+' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) }) }
  function Dec { param([string]$Hex) return [OpenInNvim.MsgPack]::Decode((ConvertFrom-Hex $Hex)) }

  # -------------------------------------------------------------------------------------------
  Write-Host '== unit: msgpack round trips (encoder -> decoder)'
  $rt = [OpenInNvim.MsgPack]::Decode([OpenInNvim.MsgPack]::Encode($null))
  Assert-That 'nil' (($rt.Status -eq 'Ok') -and ($null -eq $rt.Value) -and ($rt.Next -eq 1))
  $rtT = [OpenInNvim.MsgPack]::Decode([OpenInNvim.MsgPack]::Encode($true)); $rtF = [OpenInNvim.MsgPack]::Decode([OpenInNvim.MsgPack]::Encode($false))
  Assert-That 'true / false' (($rtT.Value -is [bool]) -and $rtT.Value -and ($rtF.Value -is [bool]) -and (-not $rtF.Value))

  $bad = @()
  foreach ($n in @(0, 1, 127, 128, 255, 256, 65535, 65536, 2147483647, 2147483648, 4294967295, 4294967296, [long]::MaxValue, -1, -32, -33, -128, -129, -32768, -32769, -2147483648, -2147483649, [long]::MinValue)) {
    $bytes = [OpenInNvim.MsgPack]::Encode($n)
    $back = [OpenInNvim.MsgPack]::Decode($bytes)
    if (($back.Status -ne 'Ok') -or (-not ($back.Value -is [long])) -or ($back.Value -ne $n) -or ($back.Next -ne $bytes.Length)) { $bad += "$n" }
  }
  Assert-That 'integers over the full 64-bit range' ($bad.Count -eq 0) ("failed: " + ($bad -join ', '))
  $sizes = @(@(127, 1), @(128, 2), @(256, 3), @(65536, 5), @(4294967296, 9), @(-32, 1), @(-33, 2), @(-129, 3), @(-32769, 5), @(-2147483649, 9))
  $bad = @(); foreach ($pair in $sizes) { $len = [OpenInNvim.MsgPack]::Encode($pair[0]).Length; if ($len -ne $pair[1]) { $bad += "$($pair[0]) -> $len bytes" } }
  Assert-That 'integers use the smallest encoding' ($bad.Count -eq 0) ($bad -join ', ')
  $u = [OpenInNvim.MsgPack]::Decode([OpenInNvim.MsgPack]::Encode([uint64]::MaxValue))
  Assert-That 'uint64 above the signed range stays exact' (($u.Value -is [uint64]) -and ($u.Value -eq [uint64]::MaxValue))

  $bad = @()
  foreach ($pair in @(@(0, 0xa0), @(31, 0xbf), @(32, 0xd9), @(255, 0xd9), @(256, 0xda), @(65535, 0xda), @(65536, 0xdb))) {
    $text = 'x' * $pair[0]
    $bytes = [OpenInNvim.MsgPack]::Encode($text)
    $back = [OpenInNvim.MsgPack]::Decode($bytes)
    if (($bytes[0] -ne $pair[1]) -or ($back.Status -ne 'Ok') -or ($back.Value -cne $text)) { $bad += "$($pair[0])" }
  }
  Assert-That 'strings: fixstr, str8, str16, str32 headers and content' ($bad.Count -eq 0) ("failed lengths: " + ($bad -join ', '))
  $uni = 'k' + [char]0x00e4 + [char]0x00f6 + [char]0x00fc + ' ' + [char]::ConvertFromUtf32(0x1F600) + " 'q' %p & [x]"
  Assert-That 'unicode and special characters survive' (([OpenInNvim.MsgPack]::Decode([OpenInNvim.MsgPack]::Encode($uni))).Value -ceq $uni)

  $nested = [object[]]@('a', [object[]]@('b', $null, $true, $false, 5), 'c')
  $back = ([OpenInNvim.MsgPack]::Decode([OpenInNvim.MsgPack]::Encode($nested))).Value
  Assert-That 'nested arrays' (($back.Count -eq 3) -and ($back[1].Count -eq 5) -and ($back[1][0] -eq 'b') -and ($null -eq $back[1][1]) -and ($back[1][2] -eq $true) -and ($back[1][3] -eq $false) -and ($back[1][4] -eq 5) -and ($back[2] -eq 'c'))
  $empty = ([OpenInNvim.MsgPack]::Decode([OpenInNvim.MsgPack]::Encode([object[]]@()))).Value
  Assert-That 'an empty array stays an array' (($null -ne $empty) -and ($empty -is [array]) -and ($empty.Count -eq 0))
  $a16 = [OpenInNvim.MsgPack]::Encode([object[]]::new(16)); $a32 = [OpenInNvim.MsgPack]::Encode([object[]]::new(65536))
  $b16 = [OpenInNvim.MsgPack]::Decode($a16); $b32 = [OpenInNvim.MsgPack]::Decode($a32)
  Assert-That 'array16 and array32 headers' (($a16[0] -eq 0xdc) -and ($b16.Value.Count -eq 16) -and ($a32[0] -eq 0xdd) -and ($b32.Status -eq 'Ok') -and ($b32.Value.Count -eq 65536))

  Write-Host '== unit: msgpack decoder, every type family'
  $m = Dec '81 a1 61 01'
  Assert-That 'fixmap' (($m.Status -eq 'Ok') -and ($m.Value -is [System.Collections.IDictionary]) -and ($m.Value.Count -eq 1) -and ($m.Value['a'] -eq 1))
  $m16 = Dec 'de 00 02 a1 61 01 a1 62 a1 7a'; $m32 = Dec 'df 00 00 00 01 a1 61 c3'
  Assert-That 'map16 and map32' (($m16.Value['a'] -eq 1) -and ($m16.Value['b'] -eq 'z') -and ($m32.Value['a'] -eq $true))
  $mk = Dec '82 05 a1 78 c0 01'
  Assert-That 'map with non-string keys is decoded, not refused' (($mk.Status -eq 'Ok') -and ($mk.Value['5'] -eq 'x') -and ($mk.Value.Count -eq 2))
  $mm = Dec '81 a1 6d 82 a4 6d 6f 64 65 a1 6e a8 62 6c 6f 63 6b 69 6e 67 c2'
  Assert-That 'nested map (the nvim_get_mode shape)' (($mm.Value['m']['mode'] -eq 'n') -and ($mm.Value['m']['blocking'] -eq $false))
  $b8 = Dec 'c4 03 01 02 03'; $b16x = Dec 'c5 00 02 aa bb'; $b32x = Dec 'c6 00 00 00 01 ff'
  Assert-That 'bin8, bin16, bin32' (($b8.Value -is [byte[]]) -and ($b8.Value.Length -eq 3) -and ($b8.Value[2] -eq 3) -and ($b16x.Value.Length -eq 2) -and ($b16x.Value[1] -eq 0xbb) -and ($b32x.Value[0] -eq 0xff) -and ($b32x.Next -eq 6))
  $e8 = Dec 'c7 02 05 aa bb'; $e16 = Dec 'c8 00 01 fe 11'; $e32 = Dec 'c9 00 00 00 01 07 99'
  Assert-That 'ext8, ext16, ext32' (($e8.Value.Type -eq 5) -and ($e8.Value.Data.Length -eq 2) -and ($e16.Value.Type -eq -2) -and ($e16.Value.Data[0] -eq 0x11) -and ($e32.Value.Type -eq 7) -and ($e32.Next -eq 7))
  $bad = @()
  foreach ($pair in @(@('d4 01 2a', 1), @('d5 02 01 02', 2), @('d6 03 01 02 03 04', 4), @('d7 04 01 02 03 04 05 06 07 08', 8), @('d8 05 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10', 16))) {
    $x = Dec $pair[0]
    if (($x.Status -ne 'Ok') -or ($x.Value.Data.Length -ne $pair[1]) -or ($x.Next -ne ($pair[1] + 2))) { $bad += $pair[0] }
  }
  Assert-That 'fixext 1, 2, 4, 8, 16' ($bad.Count -eq 0) ($bad -join ' / ')
  $f32 = Dec 'ca 3f c0 00 00'; $f64 = Dec 'cb 3f f8 00 00 00 00 00 00'; $fneg = Dec 'cb c0 04 00 00 00 00 00 00'
  Assert-That 'float32 and float64' (($f32.Value -is [double]) -and ($f32.Value -eq 1.5) -and ($f64.Value -eq 1.5) -and ($fneg.Value -eq -2.5) -and ($f64.Next -eq 9))
  $u64 = Dec 'cf ff ff ff ff ff ff ff ff'; $u64s = Dec 'cf 00 00 00 01 00 00 00 00'; $i64 = Dec 'd3 ff ff ff ff 7f ff ff ff'; $i64min = Dec 'd3 80 00 00 00 00 00 00 00'
  Assert-That 'uint64 and int64' (($u64.Value -eq [uint64]::MaxValue) -and ($u64s.Value -eq 4294967296) -and ($i64.Value -eq -2147483649) -and ($i64min.Value -eq [long]::MinValue))
  $u8 = Dec 'cc ff'; $u16 = Dec 'cd 01 00'; $u32 = Dec 'ce ff ff ff ff'; $i8 = Dec 'd0 80'; $i16 = Dec 'd1 80 00'; $i32 = Dec 'd2 80 00 00 00'; $nf = Dec 'ff'
  Assert-That 'uint8/16/32, int8/16/32, negative fixint' (($u8.Value -eq 255) -and ($u16.Value -eq 256) -and ($u32.Value -eq 4294967295) -and ($i8.Value -eq -128) -and ($i16.Value -eq -32768) -and ($i32.Value -eq -2147483648) -and ($nf.Value -eq -1))
  $ar32 = Dec 'dd 00 00 00 02 01 02'; $s32 = Dec 'db 00 00 00 03 61 62 63'; $s16 = Dec 'da 00 03 61 62 63'; $s8 = Dec 'd9 03 61 62 63'
  Assert-That 'array32 and str8/16/32 headers' (($ar32.Value.Count -eq 2) -and ($ar32.Value[1] -eq 2) -and ($s32.Value -eq 'abc') -and ($s16.Value -eq 'abc') -and ($s8.Value -eq 'abc'))

  Write-Host '== unit: "incomplete" versus "malformed"'
  Assert-That 'nothing at all is incomplete' ((Dec '').Status -eq 'Incomplete')
  Assert-That 'truncated string is incomplete' ((Dec 'a5 61').Status -eq 'Incomplete')
  Assert-That 'truncated array is incomplete' ((Dec '93 01').Status -eq 'Incomplete')
  Assert-That 'truncated map is incomplete' ((Dec '82 a1 61 01 a1').Status -eq 'Incomplete')
  Assert-That 'truncated float and length prefix are incomplete' (((Dec 'cb 3f f8').Status -eq 'Incomplete') -and ((Dec 'db 00 00').Status -eq 'Incomplete') -and ((Dec 'c7 02 05 aa').Status -eq 'Incomplete'))
  Assert-That '0xc1 (never used) is malformed, at once' (((Dec 'c1').Status -eq 'Malformed') -and ((Dec '92 01 c1').Status -eq 'Malformed'))
  $sample = ConvertFrom-Hex '94 01 01 c0 82 a4 6d 6f 64 65 a1 6e a8 62 6c 6f 63 6b 69 6e 67 c2'
  $bad = @()
  for ($cut = 0; $cut -lt $sample.Length; $cut++) { if (([OpenInNvim.MsgPack]::Decode($sample, 0, $cut)).Status -ne 'Incomplete') { $bad += $cut } }
  Assert-That 'every proper prefix of a valid message is incomplete, the whole is ok' (($bad.Count -eq 0) -and (([OpenInNvim.MsgPack]::Decode($sample)).Status -eq 'Ok')) ("prefix lengths: " + ($bad -join ','))

  Write-Host '== unit: depth limit'
  $deepOk = [byte[]](@(0x91) * 32 + @(0xc0)); $deepBad = [byte[]](@(0x91) * 33 + @(0xc0)); $deepWorse = [byte[]](@(0x91) * 5000 + @(0xc0))
  Assert-That '32 levels of nesting decode' (([OpenInNvim.MsgPack]::Decode($deepOk)).Status -eq 'Ok')
  Assert-That '33 levels are refused as malformed' (([OpenInNvim.MsgPack]::Decode($deepBad)).Status -eq 'Malformed')
  Assert-That '5000 levels are refused, not recursed into' (([OpenInNvim.MsgPack]::Decode($deepWorse)).Status -eq 'Malformed')
  $deepMap = [byte[]](@(0x81, 0xa1, 0x6b) * 40 + @(0xc0))
  Assert-That 'deeply nested maps are refused too' (([OpenInNvim.MsgPack]::Decode($deepMap)).Status -eq 'Malformed')

  Write-Host '== unit: huge length prefixes'
  Assert-That 'str32 / bin32 / ext32 of 4 GB are malformed' (((Dec 'db ff ff ff ff').Status -eq 'Malformed') -and ((Dec 'c6 ff ff ff ff').Status -eq 'Malformed') -and ((Dec 'c9 ff ff ff ff 01').Status -eq 'Malformed'))
  Assert-That 'array32 / map32 of 4 billion entries are malformed' (((Dec 'dd ff ff ff ff').Status -eq 'Malformed') -and ((Dec 'df ff ff ff ff').Status -eq 'Malformed'))
  # 1,000,000 entries would be legal, but only three bytes follow: "incomplete", and nothing may be
  # allocated for it. 3000 rounds that allocated 8 MB each would take many seconds.
  $claims = @((ConvertFrom-Hex 'dd 00 0f 42 40 01 02 03'), (ConvertFrom-Hex 'db 00 0f 42 40 61 62 63'), (ConvertFrom-Hex 'c6 00 0f 42 40 61 62 63'), (ConvertFrom-Hex 'df 00 07 a1 20 01 02 03'))
  $watch = [Diagnostics.Stopwatch]::StartNew(); $notIncomplete = 0
  for ($i = 0; $i -lt 3000; $i++) { foreach ($c in $claims) { if (([OpenInNvim.MsgPack]::Decode($c)).Status -ne 'Incomplete') { $notIncomplete++ } } }
  $claimMs = $watch.ElapsedMilliseconds
  Assert-That 'a large claimed length with few bytes is incomplete and allocates nothing' (($notIncomplete -eq 0) -and ($claimMs -lt 3000)) "wrong=$notIncomplete ms=$claimMs"
  # 30 nested arrays that each claim a million entries, and a megabyte that makes every claim plausible.
  $nest = New-Object byte[] (30 * 5 + 1000100)
  for ($i = 0; $i -lt 30; $i++) { $nest[$i * 5] = 0xdd; $nest[$i * 5 + 1] = 0x00; $nest[$i * 5 + 2] = 0x0f; $nest[$i * 5 + 3] = 0x42; $nest[$i * 5 + 4] = 0x40 }
  $watch = [Diagnostics.Stopwatch]::StartNew(); $nested = [OpenInNvim.MsgPack]::Decode($nest); $nestMs = $watch.ElapsedMilliseconds
  Assert-That 'nested million-entry claims: incomplete, in time, without allocating per claim' (($nested.Status -eq 'Incomplete') -and ($nestMs -lt 2000)) "status=$($nested.Status) ms=$nestMs"

  Write-Host '== unit: rpc stream parser'
  $parser = New-Object OpenInNvim.RpcParser
  $parser.Feed((ConvertFrom-Hex '93 02 a1 78 91 81 a1 61 01 94 01 01 c0 05'))
  $reply = $parser.Next(1)
  Assert-That 'a notification with a table, then the reply: ok, result 5' (($reply.Status -eq 'Ok') -and ($reply.Result -eq 5)) "status=$($reply.Status) result=$($reply.Result)"
  $parser = New-Object OpenInNvim.RpcParser
  $parser.Feed((ConvertFrom-Hex '93 02 a1 78 91 81 a1 61 01 94 01')); $half = $parser.Next(1)
  $parser.Feed((ConvertFrom-Hex '01 c0 05')); $whole = $parser.Next(1)
  Assert-That 'a reply split across two reads' (($half.Status -eq 'TimedOut') -and ($whole.Status -eq 'Ok') -and ($whole.Result -eq 5)) "half=$($half.Status) whole=$($whole.Status)"
  $parser = New-Object OpenInNvim.RpcParser
  $parser.Feed((ConvertFrom-Hex '94 01 07 c0 01 94 00 09 a1 6d 90 94 01 02 c0 a2 6f 6b'))
  $reply = $parser.Next(2)
  Assert-That 'replies to other ids and requests are stepped over' (($reply.Status -eq 'Ok') -and ($reply.Result -eq 'ok'))
  $parser = New-Object OpenInNvim.RpcParser
  $parser.Feed((ConvertFrom-Hex '94 01 01 92 00 a4 62 6f 6f 6d c0'))
  $reply = $parser.Next(1)
  Assert-That 'an error reply is returned as text' (($reply.Status -eq 'Error') -and ($reply.ErrorText -eq 'boom'))
  $parser = New-Object OpenInNvim.RpcParser; $parser.Feed((ConvertFrom-Hex '93 02 a1 78 90 c1'))
  Assert-That 'malformed bytes fail at once' ($parser.Next(1).Status -eq 'Malformed')
  $parser = New-Object OpenInNvim.RpcParser; $parser.Feed((ConvertFrom-Hex '05'))
  Assert-That 'a message that is not an rpc array is malformed' ($parser.Next(1).Status -eq 'Malformed')
  # Receive cap: 210000 complete five-byte notifications (1.05 MB) and no reply.
  $block = New-Object byte[] 5000
  for ($i = 0; $i -lt 1000; $i++) { $block[$i * 5] = 0x93; $block[$i * 5 + 1] = 0x02; $block[$i * 5 + 2] = 0xa1; $block[$i * 5 + 3] = 0x78; $block[$i * 5 + 4] = 0x90 }
  $flood = New-Object byte[] (5000 * 210)
  for ($i = 0; $i -lt 210; $i++) { [Buffer]::BlockCopy($block, 0, $flood, $i * 5000, 5000) }
  $parser = New-Object OpenInNvim.RpcParser
  $watch = [Diagnostics.Stopwatch]::StartNew(); $parser.Feed($flood); $reply = $parser.Next(1); $floodMs = $watch.ElapsedMilliseconds
  Assert-That 'more than 1 MiB without the reply: TooBig' (($reply.Status -eq 'TooBig') -and ($parser.TotalReceived -eq $flood.Length)) "status=$($reply.Status)"
  Assert-That '210000 messages are parsed once, in linear time' ($floodMs -lt 2000) "ms=$floodMs"
  $parser = New-Object OpenInNvim.RpcParser; $parser.Feed($flood); $parser.Feed((ConvertFrom-Hex '94 01 01 c0 05'))
  Assert-That 'a reply that did arrive is still found behind a flood' ($parser.Next(1).Status -eq 'Ok')
  $parser = New-Object OpenInNvim.RpcParser; $parser.Feed($flood)
  Assert-That 'the deadline is checked while parsing' ($parser.Next(1, -1).Status -eq 'TimedOut')

  # -------------------------------------------------------------------------------------------
  Write-Host '== unit: raw command line'
  function Parse { param([string]$Raw) return [OpenInNvim.CommandLine]::Parse($Raw) }
  $c = Parse '"C:\Program Files\Oin\OpenInNvim.exe" current "C:\"'
  Assert-That 'quoted drive root "C:\" stays C:\' (($c.Mode -eq 'current') -and ($c.Path -ceq 'C:\')) "mode=[$($c.Mode)] path=[$($c.Path)]"
  $c = Parse '"C:\Program Files\Oin\OpenInNvim.exe" current "C:\a b\c d\"'
  Assert-That 'trailing backslash before the closing quote' ($c.Path -ceq 'C:\a b\c d\') "path=[$($c.Path)]"
  $c = Parse 'C:\Oin\OpenInNvim.exe new C:\a b\c d.txt'
  Assert-That 'unquoted path with spaces: the rest is the path' (($c.Mode -eq 'new') -and ($c.Path -ceq 'C:\a b\c d.txt')) "path=[$($c.Path)]"
  $c = Parse "`"C:\Oin\OpenInNvim.exe`"`tcurrent   `"C:\x y.txt`"   "
  Assert-That 'tabs and extra blanks between and after the tokens' (($c.Mode -eq 'current') -and ($c.Path -ceq 'C:\x y.txt')) "path=[$($c.Path)]"
  $c1 = Parse '"C:\Oin\OpenInNvim.exe" current'; $c2 = Parse '"C:\Oin\OpenInNvim.exe" current   '; $c3 = Parse '"C:\Oin\OpenInNvim.exe" current ""'
  Assert-That 'no path' (($c1.Mode -eq 'current') -and ($null -eq $c1.Path) -and ($null -eq $c2.Path) -and ($null -eq $c3.Path))
  $c1 = Parse '"C:\Oin\OpenInNvim.exe"'; $c2 = Parse ''
  Assert-That 'no mode' (($c1.Mode -eq '') -and ($null -eq $c1.Path) -and ($c2.Mode -eq ''))
  $c = Parse ('OpenInNvim.exe CURRENT "' + 'C:\' + $uni + '.txt"')
  Assert-That 'unicode path, mode in upper case' (($c.Mode -eq 'current') -and ($c.Path -ceq ('C:\' + $uni + '.txt')))
  $c = Parse '"C:\Oin\OpenInNvim.exe" current "C:\%TEMP%x\a$USERNAME b.txt"'
  Assert-That '%VAR% and $VAR are left alone' ($c.Path -ceq 'C:\%TEMP%x\a$USERNAME b.txt') "path=[$($c.Path)]"
  $c = Parse '"C:\Oin\OpenInNvim.exe" current "\\server\share\my dir\"'
  Assert-That 'UNC path with a trailing backslash' ($c.Path -ceq '\\server\share\my dir\') "path=[$($c.Path)]"
  $c = Parse '"C:\Oin\OpenInNvim.exe" current "C:\a b'
  Assert-That 'a stray quote never ends up in the path' ($c.Path -ceq 'C:\a b') "path=[$($c.Path)]"
  $c = Parse '"C:\my dir\Open In Nvim.exe"extra current "C:\x"'
  Assert-That 'program token with spaces and glued text' (($c.Mode -eq 'current') -and ($c.Path -ceq 'C:\x')) "mode=[$($c.Mode)] path=[$($c.Path)]"

  Write-Host '== unit: command-line quoting (checked against CommandLineToArgvW)'
  Add-Type -Namespace OinNativeTest -Name Argv -MemberDefinition @'
[DllImport("shell32.dll", SetLastError = true)]
public static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string lpCmdLine, out int pNumArgs);
'@
  function Split-Argv {
    param([string]$Line)
    $n = 0
    $ptr = [OinNativeTest.Argv]::CommandLineToArgvW($Line, [ref]$n)
    $out = @()
    for ($i = 0; $i -lt $n; $i++) { $out += [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::ReadIntPtr($ptr, $i * [IntPtr]::Size)) }
    return ,$out
  }
  $samples = @('C:\dir\', 'C:\a b\', 'plain', 'with space', 'say "hi"', '\\server\share dir\', 'end\\', 'a\"b', "it's", 'C:\', '--', '%TEMP%x', 'semi;colon', ('u ' + $uni))
  foreach ($smp in $samples) {
    $argv = Split-Argv ('prog.exe ' + [OpenInNvim.CommandLine]::QuoteArg($smp) + ' tail')
    Assert-That ("quoting round trip: [$smp]") (($argv.Count -eq 3) -and ($argv[1] -ceq $smp) -and ($argv[2] -eq 'tail')) ("argv=" + ($argv -join ' | '))
  }
  $argv = Split-Argv ('prog.exe ' + [OpenInNvim.CommandLine]::JoinArgs([string[]]@('--listen', '\\.\pipe\x y', '--', 'C:\a b\', '')))
  Assert-That 'JoinArgs: five arguments, one of them empty' (($argv.Count -eq 6) -and ($argv[2] -ceq '\\.\pipe\x y') -and ($argv[4] -ceq 'C:\a b\') -and ($argv[5] -eq '')) ("argv=" + ($argv -join ' | '))

  Write-Host '== unit: PATH lookup'
  $pathA = Join-Path $tmp 'path a'; $pathB = Join-Path $tmp 'path b'
  [void][IO.Directory]::CreateDirectory($pathA); [void][IO.Directory]::CreateDirectory($pathB)
  [IO.File]::WriteAllText((Join-Path $pathA 'oinfoo.exe'), ''); [IO.File]::WriteAllText((Join-Path $pathB 'oinbar.cmd'), ''); [IO.File]::WriteAllText((Join-Path $pathB 'oinfoo.exe'), '')
  $searchPath = ';"' + $pathA + '";;' + $pathB + ';'
  Assert-That 'name without extension finds the .exe in the first directory (quoted, empty entries)' ([OpenInNvim.CommandLine]::FindOnPath('oinfoo', $searchPath) -eq (Join-Path $pathA 'oinfoo.exe'))
  Assert-That 'name with extension' (([OpenInNvim.CommandLine]::FindOnPath('oinbar.cmd', $searchPath) -eq (Join-Path $pathB 'oinbar.cmd')) -and ($null -eq [OpenInNvim.CommandLine]::FindOnPath('oinbar', $searchPath)))
  Assert-That 'not on PATH' (($null -eq [OpenInNvim.CommandLine]::FindOnPath('oin-no-such-program', $searchPath)) -and ($null -eq [OpenInNvim.CommandLine]::FindOnPath('oinfoo', '')))
  Assert-That 'a name with a directory is checked as given' (([OpenInNvim.CommandLine]::FindOnPath((Join-Path $pathA 'oinfoo.exe'), '') -eq (Join-Path $pathA 'oinfoo.exe')) -and ($null -eq [OpenInNvim.CommandLine]::FindOnPath((Join-Path $pathA 'missing.exe'), $searchPath)))
  $savedCwd = [Environment]::CurrentDirectory
  try {
    [Environment]::CurrentDirectory = $pathA
    Assert-That 'the current directory is never searched' ($null -eq [OpenInNvim.CommandLine]::FindOnPath('oinfoo', '.;;'))
  } finally { [Environment]::CurrentDirectory = $savedCwd }

  Write-Host '== unit: ini'
  [Environment]::SetEnvironmentVariable('OIN_NATIVE_TEST_VAR', 'X:\wez dir')
  $iniText = @'
# a comment
; another comment
NVIM_BIN = "C:\Program Files\Neovim\bin\nvim.exe"
wezterm_bin = '%OIN_NATIVE_TEST_VAR%\wezterm-gui.exe'
NVIM_SERVER = \\.\pipe\my pipe # not a comment
PREFER_STABLE_PIPE = false
FOCUS_TERMINAL = Yes
INSTANCE_PICK = Oldest
FOLDER_OPENS_IN=edit
TERMINAL = bogus
SOMETHING_ELSE = 1
a line without the sign
'@
  $cfg = [OpenInNvim.Config]::Parse($iniText)
  Assert-That 'quoted value' ($cfg.NvimBin -ceq 'C:\Program Files\Neovim\bin\nvim.exe') "[$($cfg.NvimBin)]"
  Assert-That '%VAR% is expanded, single quotes stripped, key case ignored' ($cfg.WeztermBin -ceq 'X:\wez dir\wezterm-gui.exe') "[$($cfg.WeztermBin)]"
  Assert-That 'the value runs to the end of the line (# is legal in a path)' ($cfg.NvimServer -ceq '\\.\pipe\my pipe # not a comment') "[$($cfg.NvimServer)]"
  Assert-That 'booleans' ((-not $cfg.PreferStablePipe) -and $cfg.FocusTerminal)
  Assert-That 'choices are case-insensitive' (($cfg.InstancePick -ceq 'oldest') -and ($cfg.FolderOpensIn -ceq 'edit'))
  Assert-That 'an invalid choice falls back to the default and is noted' (($cfg.Terminal -eq 'auto') -and (@($cfg.Notes | Where-Object { $_ -like 'TERMINAL*bogus*' }).Count -eq 1))
  Assert-That 'unknown key and broken line are noted, not fatal' ((@($cfg.Notes | Where-Object { $_ -like 'unknown key SOMETHING_ELSE*' }).Count -eq 1) -and (@($cfg.Notes | Where-Object { $_ -like 'line 12 ignored*' }).Count -eq 1)) ("notes=" + ($cfg.Notes -join ' / '))
  $def = [OpenInNvim.Config]::Parse('')
  Assert-That 'defaults' (($def.NvimBin -eq 'nvim') -and ($def.Terminal -eq 'auto') -and ($def.WeztermBin -eq '') -and ($def.NvimServer -eq '') -and $def.PreferStablePipe -and ($def.InstancePick -eq 'newest') -and ($def.FolderOpensIn -eq 'filetree') -and (-not $def.FocusTerminal) -and ($def.Notes.Count -eq 0))
  $flags = [OpenInNvim.Config]::Parse("PREFER_STABLE_PIPE = `$false`r`nFOCUS_TERMINAL = 1`r`n")
  $flags2 = [OpenInNvim.Config]::Parse("PREFER_STABLE_PIPE = off`nFOCUS_TERMINAL = maybe`n")
  Assert-That 'boolean spellings; an invalid one keeps the default and is noted' ((-not $flags.PreferStablePipe) -and $flags.FocusTerminal -and (-not $flags2.PreferStablePipe) -and (-not $flags2.FocusTerminal) -and ($flags2.Notes.Count -eq 1))
  $loadErr = $null
  $missing = [OpenInNvim.Config]::Load((Join-Path $tmp 'no such.ini'), [ref]$loadErr)
  Assert-That 'a missing file means defaults' (($null -ne $missing) -and ($null -eq $loadErr) -and ($missing.InstancePick -eq 'newest'))
  $umlautPath = 'C:\T' + [char]0x00e4 + 'st ' + [char]0x00fc + '\nvim.exe'
  $encodings = @{ 'UTF-8' = (New-Object System.Text.UTF8Encoding($false)); 'UTF-8 with BOM' = (New-Object System.Text.UTF8Encoding($true)); 'UTF-16' = [Text.Encoding]::Unicode; 'ANSI code page' = [Text.Encoding]::Default }
  $bad = @()
  foreach ($encName in $encodings.Keys) {
    $encFile = Join-Path $tmp 'encoding test.ini'
    [IO.File]::WriteAllText($encFile, ("# x`r`nNVIM_BIN = " + $umlautPath + "`r`n"), $encodings[$encName])
    $loaded = [OpenInNvim.Config]::Load($encFile, [ref]$loadErr)
    if (($null -eq $loaded) -or ($loaded.NvimBin -cne $umlautPath)) { $bad += $encName }
  }
  Assert-That 'the ini is read as UTF-8, UTF-16 (byte order mark) or the ANSI code page' ($bad.Count -eq 0) ("wrong for: " + ($bad -join ', '))

  Write-Host '== unit: pipe names, addresses, PID list'
  function Parse-Pipe { param($Name) $procId = 0; $index = 0; $ok = [OpenInNvim.Pipes]::TryParseDefault($Name, [ref]$procId, [ref]$index); return @{ Ok = $ok; ProcId = $procId; Index = $index } }
  $pp = Parse-Pipe 'nvim.12345.0'; $pp2 = Parse-Pipe 'nvim.7.12'
  Assert-That 'nvim.<pid>.<n>' ($pp.Ok -and ($pp.ProcId -eq 12345) -and ($pp.Index -eq 0) -and $pp2.Ok -and ($pp2.ProcId -eq 7) -and ($pp2.Index -eq 12))
  $threw = $false; $huge = $null
  try { $huge = Parse-Pipe 'nvim.99999999999.0' } catch { $threw = $true }
  Assert-That 'nvim.99999999999.0 is rejected without an exception' ((-not $threw) -and (-not $huge.Ok))
  $bad = @()
  foreach ($name in @('nvim.123.', 'nvim..0', 'nvim.12a.0', 'nvim.123.0x', 'nvim-bartl', 'xnvim.1.0', 'nvim.+1.0', 'nvim. 1.0', 'nvim.1.99999999999', 'nvim.0.0', 'nvim.1', 'NVIM.1.0', 'nvim.1.-1', '', $null)) {
    if ((Parse-Pipe $name).Ok) { $bad += "[$name]" }
  }
  Assert-That 'everything else is not a default pipe name' ($bad.Count -eq 0) ("accepted: " + ($bad -join ' '))
  Assert-That 'pipe addresses' ([OpenInNvim.Pipes]::IsPipeAddress('\\.\pipe\x') -and (-not [OpenInNvim.Pipes]::IsPipeAddress('\\.\pipe\')) -and (-not [OpenInNvim.Pipes]::IsPipeAddress('127.0.0.1:80')) -and (-not [OpenInNvim.Pipes]::IsPipeAddress($null)))
  function Parse-Tcp { param($Address) $h = $null; $port = 0; $ok = [OpenInNvim.TcpChannel]::TryParseAddress($Address, [ref]$h, [ref]$port); return @{ Ok = $ok; Host = $h; Port = $port } }
  $t1 = Parse-Tcp '127.0.0.1:6666'; $t2 = Parse-Tcp 'localhost:80'; $t3 = Parse-Tcp '[::1]:6666'
  Assert-That 'host:port' ($t1.Ok -and ($t1.Host -eq '127.0.0.1') -and ($t1.Port -eq 6666) -and $t2.Ok -and ($t2.Host -eq 'localhost') -and $t3.Ok -and ($t3.Host -eq '::1') -and ($t3.Port -eq 6666))
  $bad = @(); foreach ($a in @('C:\x', '\\.\pipe\x', 'host:99999', 'host:', ':80', 'host', 'host:0', 'host:-1', 'a/b:80', '')) { if ((Parse-Tcp $a).Ok) { $bad += "[$a]" } }
  Assert-That 'what is not host:port' ($bad.Count -eq 0) ("accepted: " + ($bad -join ' '))
  $list = [OpenInNvim.Hooks]::ParsePids('1, 22;333 4444'); $none = [OpenInNvim.Hooks]::ParsePids('abc'); $unset = [OpenInNvim.Hooks]::ParsePids('')
  Assert-That 'OPEN_IN_NVIM_ONLY_PIDS: a list, an invalid value (restricts to nothing), not set' ((($list -join ',') -eq '1,22,333,4444') -and ($null -ne $none) -and ($none.Count -eq 0) -and ($null -eq $unset))
  Assert-That 'the pipe namespace can be listed' (([OpenInNvim.Pipes]::List()).Count -gt 0)

  Write-Host '== unit: target kinds'
  $kFile = Join-Path $tmp 'kind file.txt'; [IO.File]::WriteAllText($kFile, 'k')
  $kDir = Join-Path $tmp 'kind dir'; [void][IO.Directory]::CreateDirectory($kDir)
  $kPct = Join-Path $tmp '%TEMP%x'; [void][IO.Directory]::CreateDirectory($kPct)
  $t = [OpenInNvim.Target]::Resolve($kFile, 'C:\')
  Assert-That 'existing file: its folder is the working directory' (($t.Kind -eq 'File') -and ($t.Path -ceq $kFile) -and ($t.WorkDir -ceq $tmp)) "kind=$($t.Kind) path=[$($t.Path)] wd=[$($t.WorkDir)]"
  $t = [OpenInNvim.Target]::Resolve(($kDir + '\'), 'C:\'); $t2 = [OpenInNvim.Target]::Resolve(($kDir + '\\/'), 'C:\')
  Assert-That 'existing folder: trailing separators removed' (($t.Kind -eq 'Folder') -and ($t.Path -ceq $kDir) -and ($t.WorkDir -ceq $kDir) -and ($t2.Path -ceq $kDir)) "path=[$($t.Path)] [$($t2.Path)]"
  $t = [OpenInNvim.Target]::Resolve('C:\', $tmp); $t2 = [OpenInNvim.Target]::Resolve('C:', $tmp)
  Assert-That 'a drive root keeps its backslash; bare C: means the root' (($t.Kind -eq 'Folder') -and ($t.Path -ceq 'C:\') -and ($t.WorkDir -ceq 'C:\') -and ($t2.Path -ceq 'C:\')) "[$($t.Path)] [$($t2.Path)]"
  $t = [OpenInNvim.Target]::Resolve((Join-Path $tmp 'not there.txt'), 'C:\')
  Assert-That 'a path that does not exist is a new file in its (existing) folder' (($t.Kind -eq 'NewFile') -and ($t.Path -ceq (Join-Path $tmp 'not there.txt')) -and ($t.WorkDir -ceq $tmp))
  $t = [OpenInNvim.Target]::Resolve((Join-Path $tmp 'no dir\new.txt'), 'C:\Windows')
  Assert-That 'new file in a folder that does not exist: process directory as working directory' (($t.Kind -eq 'NewFile') -and ($t.WorkDir -ceq 'C:\Windows'))
  $t = [OpenInNvim.Target]::Resolve($null, $kDir); $t2 = [OpenInNvim.Target]::Resolve('', $kDir)
  Assert-That 'no path: the process working directory' (($t.Kind -eq 'Folder') -and ($t.Path -ceq $kDir) -and ($t2.Path -ceq $kDir))
  $t = [OpenInNvim.Target]::Resolve($kPct, 'C:\')
  Assert-That 'a folder named %TEMP%x is used literally' (($t.Kind -eq 'Folder') -and ($t.Path -ceq $kPct)) "path=[$($t.Path)]"
  $t = [OpenInNvim.Target]::Resolve(($kFile -replace '\\', '/'), 'C:\')
  Assert-That 'forward slashes' (($t.Kind -eq 'File') -and ($t.Path -ceq $kFile)) "path=[$($t.Path)]"
  try {
    [Environment]::CurrentDirectory = $tmp
    $t = [OpenInNvim.Target]::Resolve('kind file.txt', 'C:\')
    Assert-That 'relative input becomes absolute' (($t.Kind -eq 'File') -and ($t.Path -ceq $kFile)) "path=[$($t.Path)]"
  } finally { [Environment]::CurrentDirectory = $savedCwd }
  Assert-That 'UNC forms: share root and folder' (([OpenInNvim.Target]::TrimSeparators('\\server\share\my dir\') -ceq '\\server\share\my dir') -and ([OpenInNvim.Target]::TrimSeparators('\\server\share\') -ceq '\\server\share') -and ([OpenInNvim.Target]::TrimSeparators('\\server\share\a.txt') -ceq '\\server\share\a.txt'))

  # -------------------------------------------------------------------------------------------
  Write-Host '== fixture: starting throw-away instances'
  $fakeUser = 'oin_p1_' + $tag
  $userListen = 'oin_p1_listen_' + $tag
  $listenPipe = '\\.\pipe\nvim-' + $userListen
  $probe = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
  $probe.Start(); $tcpPort = $probe.LocalEndpoint.Port; $probe.Stop()
  $pidsFile = Join-Path $tmp 'pids.txt'
  $stopFile = Join-Path $tmp 'stop.txt'

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $nvim
  $psi.Arguments = '--headless -l "' + (Join-Path $PSScriptRoot 'fixture.lua') + '" "' + $pidsFile + '" "' + $stopFile + '" "listen1=' + $listenPipe + ';tcp1=127.0.0.1:' + $tcpPort + '"'
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.RedirectStandardInput = $true
  $fixtureProc = [Diagnostics.Process]::Start($psi)

  $t0 = [DateTime]::UtcNow
  while (-not [IO.File]::Exists($pidsFile) -and ([DateTime]::UtcNow - $t0).TotalSeconds -lt 45) { Start-Sleep -Milliseconds 250 }
  if (-not [IO.File]::Exists($pidsFile)) { throw 'fixture did not report PIDs in 45 s' }
  Start-Sleep -Milliseconds 300
  $Pids = @{}
  foreach ($line in [IO.File]::ReadAllLines($pidsFile)) { $k, $v = $line -split '=', 2; $Pids[$k] = [int]$v }
  Write-Host ('  pids: ' + (($Pids.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' '))
  foreach ($need in 'gui1', 'gui2', 'headless', 'embedhl', 'listen1', 'tcp1') { if (-not $Pids.ContainsKey($need)) { throw "fixture did not start $need" } }

  $pipe1 = '\\.\pipe\nvim.' + $Pids.gui1 + '.0'
  $pipe2 = '\\.\pipe\nvim.' + $Pids.gui2 + '.0'
  $pipeHl = '\\.\pipe\nvim.' + $Pids.headless + '.0'
  $editors = "$($Pids.gui1),$($Pids.gui2)"

  # RPC from the test side goes through the launcher's own client (and through its trust check).
  function Open-Rpc {
    param([string]$Pipe)
    $client = [OpenInNvim.RpcClient]::OpenPipe($Pipe, 2000)
    if ($null -eq $client) { throw "cannot connect to $Pipe" }
    $script:clients += $client
    return $client
  }
  function Invoke-Lua {
    param($Rpc, [string]$Code, [object[]]$LuaArgs = @(), [int]$Ms = 8000)
    # Values that came through the pipeline are wrapped in PSObject; the encoder needs the bare objects.
    $inner = [object[]]::new($LuaArgs.Count)
    for ($i = 0; $i -lt $LuaArgs.Count; $i++) { if ($null -ne $LuaArgs[$i]) { $inner[$i] = $LuaArgs[$i].PSObject.BaseObject } }
    $outer = [object[]]::new(2); $outer[0] = $Code; $outer[1] = $inner
    $reply = $Rpc.Call('nvim_exec_lua', $outer, $Ms)
    if ($reply.Status -ne 'Ok') { return ('<' + $reply.Status + ' ' + $reply.ErrorText + '>') }
    return $reply.Result
  }
  function Send-Keys { param($Rpc, [string]$Keys) [void]$Rpc.Call('nvim_input', [object[]]@($Keys), 2000) }
  function Get-Mode {
    param($Rpc)
    $reply = $Rpc.Call('nvim_get_mode', [object[]]@(), 2000)
    if ($reply.Status -ne 'Ok') { return ('<' + $reply.Status + '>') }
    if ($reply.Result['blocking']) { return ($reply.Result['mode'] + ' blocking') }
    return $reply.Result['mode']
  }
  function Wait-Mode {
    param($Rpc, [string]$Want, [int]$Ms = 3000)
    $until = [DateTime]::UtcNow.AddMilliseconds($Ms); $got = ''
    do { $got = Get-Mode $Rpc; if ($got -ceq $Want) { return $got }; Start-Sleep -Milliseconds 25 } while ([DateTime]::UtcNow -lt $until)
    return $got
  }
  function Get-CurrentName { param($Rpc) return (Invoke-Lua $Rpc 'return vim.api.nvim_buf_get_name(0)') }
  function Get-FirstLine { param($Rpc) return (Invoke-Lua $Rpc 'return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""') }
  function Test-HasBuffer { param($Rpc, [string]$Path) return [bool](Invoke-Lua $Rpc 'local p = ...; for _, b in ipairs(vim.api.nvim_list_bufs()) do if vim.api.nvim_buf_get_name(b) == p then return true end end; return false' @($Path)) }
  $resetLua = @'
local dir = ...
vim.cmd('silent! tabonly!')
vim.cmd('silent! only!')
vim.o.hidden = true
vim.o.confirm = false
vim.cmd('enew!')
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if b ~= vim.api.nvim_get_current_buf() then pcall(vim.api.nvim_buf_delete, b, { force = true }) end
end
pcall(function() vim.wo.winfixbuf = false end)
vim.api.nvim_set_current_dir(dir)
vim.g.ft_args = nil
return true
'@
  function Reset-Instance { param($Rpc) Send-Keys $Rpc '<C-\><C-N>'; $done = Invoke-Lua $Rpc $resetLua @($tmp); if ($done -ne $true) { throw "reset failed: $done" } }

  function Set-Ini {
    param([hashtable]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { if ([IO.File]::Exists($ini)) { [IO.File]::Delete($ini) }; return }
    $lines = @('# written by run-tests.ps1')
    foreach ($k in $Values.Keys) { $lines += ($k + ' = ' + $Values[$k]) }
    [IO.File]::WriteAllLines($ini, [string[]]$lines)
  }

  function Invoke-Oin {
    <#
      .SYNOPSIS
        Run the launcher. The command line is exactly what Explorer would write: <mode> "<path>".
      .NOTES
        Refuses to run without the PID restriction and one of the two no-window switches.
    #>
    param([string]$ArgLine, [hashtable]$Env = @{}, [string]$Cwd = $tmp)
    $all = @{
      OPEN_IN_NVIM_ONLY_PIDS = $editors; OPEN_IN_NVIM_NO_SPAWN = '1'; OPEN_IN_NVIM_NO_UI = '1'; USERNAME = $fakeUser; OPEN_IN_NVIM_NO_PATH_REFRESH = '1'
      OPEN_IN_NVIM_DRYRUN = $null; OPEN_IN_NVIM_SPAWN_DRYRUN = $null; OPEN_IN_NVIM_ALLOW_TCP = $null; OPEN_IN_NVIM_LOG = $runLog
    }
    foreach ($k in $Env.Keys) { $all[$k] = $Env[$k] }
    if (-not $all['OPEN_IN_NVIM_ONLY_PIDS']) { throw 'refusing to run the launcher without OPEN_IN_NVIM_ONLY_PIDS' }
    if (-not $all['OPEN_IN_NVIM_NO_SPAWN'] -and -not $all['OPEN_IN_NVIM_SPAWN_DRYRUN']) { throw 'refusing to run the launcher without NO_SPAWN or SPAWN_DRYRUN' }
    if ($all['USERNAME'] -eq $env:USERNAME) { throw 'refusing to run the launcher with the real USERNAME' }
    if ([IO.File]::Exists($runLog)) { [IO.File]::Delete($runLog) }
    $res = Invoke-Bounded -Exe $exe -ArgLine $ArgLine -Env $all -Cwd $Cwd -LimitMs 30000
    if ($res.TimedOut) { throw "launcher did not exit within 30 s: $ArgLine" }
    if ([IO.File]::Exists($runLog)) { $res.Log = @([IO.File]::ReadAllLines($runLog)) }
    return $res
  }
  function Get-Candidates { param($Res) return @($Res.Lines | Where-Object { $_ -like 'candidate: *' } | ForEach-Object { $_.Substring(11) }) }
  function New-TestFile {
    param([string]$Name, [string]$Dir = $tmp)
    $path = [string](Join-Path $Dir $Name)
    [IO.File]::WriteAllText($path, ('content of ' + $Name + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    return $path
  }
  function Open-File { param([string]$Path, [hashtable]$Env = @{}) return (Invoke-Oin ('current "' + $Path + '"') $Env) }

  $g1 = Open-Rpc $pipe1
  $g2 = Open-Rpc $pipe2
  $hl = Open-Rpc $pipeHl
  $ln = Open-Rpc $listenPipe
  $tcpChannel = [OpenInNvim.TcpChannel]::Connect('127.0.0.1', $tcpPort, 2000)
  if ($null -eq $tcpChannel) { throw 'cannot connect to the TCP fixture instance' }
  $tc = New-Object OpenInNvim.RpcClient($tcpChannel)
  $clients += $tc
  Set-Ini $null
  foreach ($rpc in $g1, $g2, $ln, $tc) { Reset-Instance $rpc }

  $allPipes = [OpenInNvim.Pipes]::List()
  Assert-That 'fixture: the --listen instances own no default pipe' ((@($allPipes | Where-Object { $_ -like ('nvim.' + $Pids.listen1 + '.*') -or $_ -like ('nvim.' + $Pids.tcp1 + '.*') })).Count -eq 0)
  Assert-That 'fixture: editors have a UI, helpers have none' (((Invoke-Lua $g1 'return #vim.api.nvim_list_uis()') -ge 1) -and ((Invoke-Lua $ln 'return #vim.api.nvim_list_uis()') -ge 1) -and ((Invoke-Lua $tc 'return #vim.api.nvim_list_uis()') -ge 1) -and ((Invoke-Lua $hl 'return #vim.api.nvim_list_uis()') -eq 0))

  # -------------------------------------------------------------------------------------------
  Write-Host '== dry run: candidates and their order'
  $target = New-TestFile 'target file.txt'
  $four = "$($Pids.gui1),$($Pids.gui2),$($Pids.headless),$($Pids.embedhl)"
  $res = Invoke-Oin ('current "' + $target + '"') @{ OPEN_IN_NVIM_DRYRUN = '1'; OPEN_IN_NVIM_ONLY_PIDS = $four }
  $cands = Get-Candidates $res
  Assert-That 'dry run exits 0' ($res.Code -eq 0) "code=$($res.Code) err=$($res.Err)"
  Assert-That 'dry run prints mode, target and working directory' (($res.Lines -contains 'mode: current') -and ($res.Lines -contains ('target: file ' + $target)) -and ($res.Lines -contains ('cwd: ' + $tmp))) ("out=" + ($res.Lines -join ' / '))
  Assert-That 'candidates: newest first, then the older one, as "<address> pid=<n>"' (($cands.Count -eq 2) -and ($cands[0] -eq ($pipe2 + ' pid=' + $Pids.gui2)) -and ($cands[1] -eq ($pipe1 + ' pid=' + $Pids.gui1))) ("cands=" + ($cands -join ' , '))
  Assert-That 'headless and embed-headless helpers are not candidates' (@($res.Log | Where-Object { $_ -like '*no UI attached*' }).Count -eq 2) ("log=" + ($res.Log -join ' / '))
  Assert-That 'the dry run opened nothing' ((-not (Test-HasBuffer $g2 $target)) -and (-not (Test-HasBuffer $g1 $target)))
  Set-Ini @{ INSTANCE_PICK = 'oldest' }
  $res = Invoke-Oin ('current "' + $target + '"') @{ OPEN_IN_NVIM_DRYRUN = '1' }
  $cands = Get-Candidates $res
  Assert-That 'INSTANCE_PICK = oldest reverses the order' (($cands.Count -eq 2) -and ($cands[0] -like ($pipe1 + ' *')) -and ($cands[1] -like ($pipe2 + ' *'))) ("cands=" + ($cands -join ' , '))
  Set-Ini $null
  $res = Invoke-Oin 'current "C:\"' @{ OPEN_IN_NVIM_DRYRUN = '1' }
  Assert-That 'drive root: "C:\" is the folder C:\ with working directory C:\' (($res.Lines -contains 'target: folder C:\') -and ($res.Lines -contains 'cwd: C:\')) ("out=" + ($res.Lines -join ' / '))
  $res = Invoke-Oin 'current' @{ OPEN_IN_NVIM_DRYRUN = '1' } $kDir
  Assert-That 'no path: the working directory of the process' ($res.Lines -contains ('target: folder ' + $kDir)) ("out=" + ($res.Lines -join ' / '))
  $res = Invoke-Oin ('new "' + $target + '"') @{ OPEN_IN_NVIM_DRYRUN = '1' }
  Assert-That 'dry run in "new" mode prints the target and no candidates' (($res.Code -eq 0) -and ($res.Lines -contains 'mode: new') -and ((Get-Candidates $res).Count -eq 0))
  $longPath = $tmp + '\' + ('long name ' * 30) + 'x.txt'
  $res = Invoke-Oin ('current "' + $longPath + '"') @{ OPEN_IN_NVIM_DRYRUN = '1' }
  Assert-That 'a path longer than 260 characters is taken as it is' (($res.Code -eq 0) -and ($longPath.Length -gt 300) -and ($res.Lines -contains ('target: newfile ' + $longPath))) ("code=$($res.Code) err=$($res.Err)")

  # -------------------------------------------------------------------------------------------
  Write-Host '== open a file'
  $res = Open-File $target
  Assert-That 'launcher exits 0' ($res.Code -eq 0) "code=$($res.Code) err=$($res.Err) log=$($res.Log -join ' / ')"
  Write-Host ("       (wall time of the first run: {0:F0} ms)" -f $res.Ms)
  Assert-That 'the file is the current buffer of the newest instance, with its content' (((Get-CurrentName $g2) -ceq $target) -and ((Get-FirstLine $g2) -eq 'content of target file.txt')) ("name=[" + (Get-CurrentName $g2) + "]")
  Assert-That 'the buffer is listed' ((Invoke-Lua $g2 'return vim.bo.buflisted') -eq $true)
  Assert-That 'the older instance was left alone' (-not (Test-HasBuffer $g1 $target))
  $touched = @($res.Log | Where-Object { ($_ -match '^\s*\d+ (usable|skip|request|opened|delivered|not opened)') -and $_.Contains($pipe1) })
  Assert-That 'lazy: probing stopped at the first usable instance (the older one was never contacted)' (($touched.Count -eq 0) -and (@($res.Log | Where-Object { $_ -like ('*usable: ' + $pipe2 + '*') }).Count -eq 1)) ("log=" + ($res.Log -join ' / '))
  Assert-That 'log lines are "<elapsed ms> <text>" and end with the exit code' ((@($res.Log | Where-Object { $_ -notmatch '^\s*\d+ \S' }).Count -eq 0) -and ($res.Log.Count -ge 5) -and ($res.Log[-1] -match '^\s*\d+ exit 0$') -and ($res.Log[0] -match '^\s*\d+ start: ')) ("log=" + ($res.Log -join ' / '))
  $cwdBefore = Invoke-Lua $g2 'return vim.fn.getcwd()'
  $res = Open-File $target
  Assert-That 'opening it again: no second buffer, working directory unchanged' (((Invoke-Lua $g2 'local n = 0; for _, b in ipairs(vim.api.nvim_list_bufs()) do if vim.api.nvim_buf_get_name(b) == ... then n = n + 1 end end; return n' @($target)) -eq 1) -and ((Invoke-Lua $g2 'return vim.fn.getcwd()') -ceq $cwdBefore))
  Set-Ini @{ INSTANCE_PICK = 'oldest' }
  $res = Open-File $target
  Assert-That 'INSTANCE_PICK = oldest opens it in the oldest instance' (($res.Code -eq 0) -and ((Get-CurrentName $g1) -ceq $target))
  Set-Ini @{ INSTANCE_PICK = 'ask' }
  $askFile = New-TestFile 'ask.txt'
  $res = Open-File $askFile
  Assert-That 'INSTANCE_PICK = ask without a window (NO_UI): the first entry, i.e. the newest' (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $askFile) -and (@($res.Log | Where-Object { $_ -like '*chooser: picked*' }).Count -eq 1))
  Set-Ini $null
  $res = Open-File $target @{ OPEN_IN_NVIM_ONLY_PIDS = "$($Pids.gui1)" }
  Assert-That 'restricted to one PID' (($res.Code -eq 0) -and ((Get-CurrentName $g1) -ceq $target))

  # -------------------------------------------------------------------------------------------
  Write-Host '== hostile names open as the SAME file'
  Reset-Instance $g2; Reset-Instance $g1
  $names = @(
    'a$USERNAME b.txt', '$TEMP.txt', '%USERNAME%.txt', 'g[1].txt', 'g1.txt', 'h{1,2}.txt', 'h1.txt', 'h2.txt',
    'q`echo`.txt', "it's #1 %p & (x).txt", '-dash first.txt', 'semi;colon, comma.txt', 'caret^ bang!.txt',
    ('uml ' + [char]0x00e4 + [char]0x00f6 + [char]0x00fc + [char]0x00df + ' ' + [char]::ConvertFromUtf32(0x1F600) + '.txt')
  )
  $paths = @{}
  foreach ($name in $names) { $paths[$name] = New-TestFile $name }
  foreach ($name in $names) {
    $res = Open-File $paths[$name]
    $gotName = Get-CurrentName $g2; $gotLine = Get-FirstLine $g2
    Assert-That ("file [$name]") (($res.Code -eq 0) -and ($gotName -ceq $paths[$name]) -and ($gotLine -ceq ('content of ' + $name))) "code=$($res.Code) buffer=[$gotName] line=[$gotLine]"
  }
  $inPct = New-TestFile 'inside.txt' $kPct
  $res = Open-File $inPct
  Assert-That 'file inside a folder named %TEMP%x' (((Get-CurrentName $g2) -ceq $inPct) -and ((Get-FirstLine $g2) -eq 'content of inside.txt')) ("buffer=[" + (Get-CurrentName $g2) + "]")
  $notYet = [string](Join-Path $tmp 'not yet (new) $HOME [1].txt')
  $res = Open-File $notYet
  Assert-That 'a file that does not exist yet becomes an empty buffer of that name; nothing is created on disk' (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $notYet) -and (-not [IO.File]::Exists($notYet))) ("buffer=[" + (Get-CurrentName $g2) + "]")
  $unc = '\\localhost\' + $tmp.Substring(0, 1) + '$' + $tmp.Substring(2)
  $uncOk = $false
  try { $uncOk = [IO.Directory]::Exists($unc) } catch { $uncOk = $false }
  if ($uncOk) {
    $uncFile = $unc + '\target file.txt'
    $res = Open-File $uncFile
    Assert-That 'UNC form of a local file' (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ieq $uncFile) -and ((Get-FirstLine $g2) -eq 'content of target file.txt')) ("buffer=[" + (Get-CurrentName $g2) + "]")
    $res = Invoke-Oin ('current "' + $unc + '\kind dir\"') @{ OPEN_IN_NVIM_ONLY_PIDS = "$($Pids.gui1)" }
    $uncCwd = Invoke-Lua $g1 'return vim.fn.getcwd()'
    Assert-That 'UNC form of a local folder (trailing backslash): cd + directory view' (($res.Code -eq 0) -and ($uncCwd -ieq ($unc + '\kind dir'))) "cwd=[$uncCwd]"
  } else {
    Write-Host "       (UNC end-to-end skipped: $unc is not accessible; the UNC forms are covered by the unit tests)"
  }

  # -------------------------------------------------------------------------------------------
  Write-Host '== folders'
  Reset-Instance $g2; Reset-Instance $g1
  $spaceDir = [string](Join-Path $tmp 'sub dir'); [void][IO.Directory]::CreateDirectory($spaceDir)
  $weirdDir = [string](Join-Path $tmp "My Dir (1) #2 [x] 'q' %p & `$USERNAME"); [void][IO.Directory]::CreateDirectory($weirdDir)
  $res = Invoke-Oin ('current "' + $spaceDir + '"')
  $ft = @(Invoke-Lua $g2 'return vim.g.ft_args or {}')
  Assert-That 'folder -> :Filetree open <dir>: one argument, the space intact' (($res.Code -eq 0) -and ($ft.Count -eq 2) -and ($ft[0] -eq 'open') -and ($ft[1] -ceq $spaceDir)) ("ft_args=[" + ($ft -join ' | ') + "] log=" + ($res.Log -join ' / '))
  Assert-That 'with :Filetree the working directory is left to filetree.nvim' ((Invoke-Lua $g2 'return vim.fn.getcwd()') -ceq $tmp)
  Assert-That 'the log names the route' (@($res.Log | Where-Object { $_ -like '*opened in*(filetree)*' }).Count -eq 1)
  [void](Invoke-Lua $g2 'vim.g.ft_args = nil')
  $res = Invoke-Oin ('current "' + $spaceDir + '\"')
  $ft = @(Invoke-Lua $g2 'return vim.g.ft_args or {}')
  Assert-That 'folder with a trailing backslash (as Explorer writes it for some folders)' (($ft.Count -eq 2) -and ($ft[1] -ceq $spaceDir)) ("ft_args=[" + ($ft -join ' | ') + "]")
  foreach ($d in @($kPct, $weirdDir)) {
    [void](Invoke-Lua $g2 'vim.g.ft_args = nil')
    $res = Invoke-Oin ('current "' + $d + '"')
    $ft = @(Invoke-Lua $g2 'return vim.g.ft_args or {}')
    Assert-That ("folder [" + [IO.Path]::GetFileName($d) + "] reaches :Filetree unchanged") (($ft.Count -eq 2) -and ($ft[1] -ceq $d)) ("ft_args=[" + ($ft -join ' | ') + "]")
  }
  $only1 = @{ OPEN_IN_NVIM_ONLY_PIDS = "$($Pids.gui1)" }
  foreach ($d in @($spaceDir, $kPct, $weirdDir)) {
    $res = Invoke-Oin ('current "' + $d + '\"') $only1
    $cwd = Invoke-Lua $g1 'return vim.fn.getcwd()'
    Assert-That ("no :Filetree in the instance: cd + directory view for [" + [IO.Path]::GetFileName($d) + "]") (($res.Code -eq 0) -and ($cwd -ceq $d) -and (@($res.Log | Where-Object { $_ -like '*opened in*(edit)*' }).Count -eq 1)) "cwd=[$cwd]"
  }
  # Neovim expands $NAME when it changes directory: with this sibling in place every flavour of ":cd"
  # lands in "a<user> b" instead of the clicked "a$USERNAME b".
  $dollarDir = [string](Join-Path $tmp 'a$USERNAME b'); [void][IO.Directory]::CreateDirectory($dollarDir)
  $dollarSibling = [string](Join-Path $tmp ('a' + $env:USERNAME + ' b')); [void][IO.Directory]::CreateDirectory($dollarSibling)
  $res = Invoke-Oin ('current "' + $dollarDir + '"') $only1
  $cwd = Invoke-Lua $g1 'return vim.fn.getcwd()'
  Assert-That 'folder [a$USERNAME b] next to [a<user> b]: the clicked one, and the variable is back afterwards' (($res.Code -eq 0) -and ($cwd -ceq $dollarDir) -and ((Invoke-Lua $g1 'return vim.env.USERNAME') -ceq $env:USERNAME)) "cwd=[$cwd]"
  Set-Ini @{ FOLDER_OPENS_IN = 'edit' }
  [void](Invoke-Lua $g2 'vim.g.ft_args = nil')
  $res = Invoke-Oin ('current "' + $spaceDir + '"')
  Assert-That 'FOLDER_OPENS_IN = edit skips :Filetree even when the instance has it' (($res.Code -eq 0) -and ((Invoke-Lua $g2 'return vim.fn.getcwd()') -ceq $spaceDir) -and ((Invoke-Lua $g2 'return vim.g.ft_args == nil') -eq $true))
  # The directory view fails AFTER the working directory was changed: this instance has taken the folder,
  # it must not be opened in the next one as well.
  Reset-Instance $g2; Reset-Instance $g1
  Set-Ini @{ INSTANCE_PICK = 'oldest' }
  [void](Invoke-Lua $g1 'local real = vim.cmd; vim.g.oin_view_calls = 0; vim.cmd = setmetatable({}, { __index = real, __call = function(_, c) if c == "silent edit ." then vim.g.oin_view_calls = vim.g.oin_view_calls + 1; error("view boom") end; return real(c) end }); _G.oin_real_cmd = real')
  $res = Invoke-Oin ('current "' + $spaceDir + '"')
  $viewCalls = Invoke-Lua $g1 'vim.cmd = _G.oin_real_cmd; return vim.g.oin_view_calls'
  Assert-That 'a directory view that fails after the cd is not a refusal: no second instance changes directory' (($res.Code -eq 0) -and ($viewCalls -eq 1) -and ((Invoke-Lua $g1 'return vim.fn.getcwd()') -ceq $spaceDir) -and ((Invoke-Lua $g2 'return vim.fn.getcwd()') -ceq $tmp) -and ((Invoke-Lua $g2 'return vim.g.ft_args == nil') -eq $true)) ("code=$($res.Code) calls=$viewCalls log=" + ($res.Log -join ' / '))
  Set-Ini $null

  # -------------------------------------------------------------------------------------------
  Write-Host '== instances that must not get the file'
  Reset-Instance $g2; Reset-Instance $g1
  $res = Open-File $target @{ OPEN_IN_NVIM_ONLY_PIDS = "$($Pids.headless),$($Pids.embedhl)" }
  Assert-That 'only headless helpers: exit 3 (NO_SPAWN), "no reachable instance"' (($res.Code -eq 3) -and ($res.Lines -contains 'no reachable instance') -and (@($res.Log | Where-Object { $_ -like '*no UI attached*' }).Count -eq 2)) "code=$($res.Code) out=$($res.Text)"
  Assert-That 'the headless helper did not get the file' (-not (Test-HasBuffer $hl $target))

  # A hit-enter prompt: the instance is alive but waits for a key.
  $blockedFile = New-TestFile 'while blocked.txt'
  Send-Keys $g2 ':echo "a\nb\nc"<CR>'
  $modeNow = Wait-Mode $g2 'r blocking'
  $res = Open-File $blockedFile
  $skipIndex = -1
  for ($i = 0; $i -lt $res.Log.Count; $i++) { if ($res.Log[$i] -like ('*skip ' + $pipe2 + ': blocked*')) { $skipIndex = $i } }
  $skipMs = -1
  if ($skipIndex -gt 0) { $skipMs = [int](($res.Log[$skipIndex] -replace '^\s*(\d+) .*$', '$1')) - [int](($res.Log[$skipIndex - 1] -replace '^\s*(\d+) .*$', '$1')) }
  Assert-That 'blocked instance (hit-enter prompt) is recognised' (($modeNow -eq 'r blocking') -and ($skipIndex -gt 0)) ("mode=[$modeNow] log=" + ($res.Log -join ' / '))
  Assert-That 'it is skipped in well under 100 ms' (($skipMs -ge 0) -and ($skipMs -lt 100)) "skip took $skipMs ms"
  Assert-That 'the next instance gets the file, exit 0' (($res.Code -eq 0) -and ((Get-CurrentName $g1) -ceq $blockedFile))
  Write-Host ("       (blocked instance skipped after {0} ms; whole run {1:F0} ms)" -f $skipMs, $res.Ms)
  Send-Keys $g2 '<CR>'
  $modeNow = Wait-Mode $g2 'n'
  Assert-That 'after the prompt is dismissed the blocked instance has NOT opened the file' (($modeNow -eq 'n') -and (-not (Test-HasBuffer $g2 $blockedFile)))

  # An instance whose main thread is busy does not answer at all: skipped after the probe limit.
  $busyFile = New-TestFile 'while busy.txt'
  [void]$g2.Send('nvim_exec_lua', [object[]]@('local t = vim.uv.hrtime(); while vim.uv.hrtime() - t < 1.5e9 do end', [object[]]@()))
  Start-Sleep -Milliseconds 100
  $res = Open-File $busyFile
  Assert-That 'busy instance: no answer within the limit, next instance gets the file' (($res.Code -eq 0) -and ((Get-CurrentName $g1) -ceq $busyFile) -and (@($res.Log | Where-Object { $_ -like ('*skip ' + $pipe2 + ': no answer to nvim_get_mode*') }).Count -eq 1) -and ($res.Ms -lt 1500)) ("ms=$($res.Ms) log=" + ($res.Log -join ' / '))
  Start-Sleep -Milliseconds 1800
  Assert-That 'the busy instance is fine afterwards and has not opened the file' (((Wait-Mode $g2 'n') -eq 'n') -and (-not (Test-HasBuffer $g2 $busyFile)))

  # An error reply: this instance refuses, the next one gets it.
  Reset-Instance $g2; Reset-Instance $g1
  $refusedFile = New-TestFile 'refused.txt'
  [void](Invoke-Lua $g2 'vim.fn.bufadd = function() error("boom from the test") end')
  $res = Open-File $refusedFile
  [void](Invoke-Lua $g2 'vim.fn.bufadd = nil')
  Assert-That 'error reply: the next instance gets the file, exit 0' (($res.Code -eq 0) -and ((Get-CurrentName $g1) -ceq $refusedFile) -and (-not (Test-HasBuffer $g2 $refusedFile))) "code=$($res.Code)"
  Assert-That 'the error text is in the log' (@($res.Log | Where-Object { $_ -like ('*not opened in ' + $pipe2 + ' (Refused)*boom from the test*') }).Count -eq 1) ("log=" + ($res.Log -join ' / '))
  # An autocommand failing after the buffer is on screen is NOT a refusal.
  Reset-Instance $g2; Reset-Instance $g1
  $auFile = New-TestFile 'autocmd fails.txt'
  [void](Invoke-Lua $g2 'vim.g.oin_au = vim.api.nvim_create_autocmd("BufEnter", { pattern = "*autocmd fails.txt", callback = function() error("autocmd boom") end })')
  $res = Open-File $auFile
  [void](Invoke-Lua $g2 'vim.api.nvim_del_autocmd(vim.g.oin_au)')
  Assert-That 'a failing autocommand after the buffer is shown does not send the file to a second instance' (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $auFile) -and (-not (Test-HasBuffer $g1 $auFile)))

  # -------------------------------------------------------------------------------------------
  Write-Host '== slow open'
  Reset-Instance $g2; Reset-Instance $g1
  $slowFile = New-TestFile 'slow open.txt'
  [void](Invoke-Lua $g2 'vim.g.oin_slow = vim.api.nvim_create_autocmd("BufReadPost", { pattern = "*slow open.txt", callback = function() vim.wait(3500, function() return false end) end })')
  $res = Open-File $slowFile
  Assert-That 'a 3.5 s open: the launcher waits and exits 0' (($res.Code -eq 0) -and ($res.Ms -ge 3000) -and ($res.Ms -lt 12000)) "code=$($res.Code) ms=$($res.Ms)"
  Assert-That 'the file is open in the slow instance and NOT in a second one' ((Test-HasBuffer $g2 $slowFile) -and (-not (Test-HasBuffer $g1 $slowFile)))
  Write-Host ("       (slow open: launcher returned after {0:F0} ms)" -f $res.Ms)
  # No answer within the limit (unit level, short limit instead of 15 s): "Delivered", never "next instance".
  Reset-Instance $g2
  [void](Invoke-Lua $g2 'vim.api.nvim_del_autocmd(vim.g.oin_slow); vim.g.oin_slow = vim.api.nvim_create_autocmd("BufReadPost", { pattern = "*slow open.txt", callback = function() vim.wait(1500, function() return false end) end })')
  $cand = New-Object OpenInNvim.Candidate
  $cand.Pid = $Pids.gui2; $cand.Address = $pipe2
  $cand.Indexes = New-Object 'System.Collections.Generic.List[int]'; $cand.Indexes.Add(0)
  $hooks = New-Object OpenInNvim.Hooks
  $hooks.OnlyPids = [int[]]@($Pids.gui2)
  $why = $null
  $session = [OpenInNvim.Discovery]::Connect($cand, $hooks, [ref]$why)
  $detail = $null
  $outcome = [OpenInNvim.Opener]::Open($session, [OpenInNvim.Target]::Resolve($slowFile, $tmp), [OpenInNvim.Config]::Parse(''), 400, [ref]$detail)
  Start-Sleep -Milliseconds 1700
  Assert-That 'no answer within the limit is "Delivered" (the instance has the request), and the file does open there' (($outcome -eq 'Delivered') -and (Test-HasBuffer $g2 $slowFile)) "outcome=$outcome detail=$detail why=$why"
  $session.Dispose()
  [void](Invoke-Lua $g2 'vim.api.nvim_del_autocmd(vim.g.oin_slow)')

  # -------------------------------------------------------------------------------------------
  Write-Host '== editor modes and window situations (target: one instance)'
  $only2 = @{ OPEN_IN_NVIM_ONLY_PIDS = "$($Pids.gui2)" }
  $modeCases = @(
    @{ Name = 'insert'; Keys = 'ihello'; Mode = 'i' },
    @{ Name = 'visual'; Keys = 'ione<CR>two<Esc>ggVG'; Mode = 'V' },
    @{ Name = 'command-line'; Keys = ':echo 12'; Mode = 'c' },
    @{ Name = 'operator-pending'; Keys = 'ione<Esc>d'; Mode = 'no' }
  )
  foreach ($case in $modeCases) {
    Reset-Instance $g2
    [void](Invoke-Lua $g2 'vim.g.oin_prev = vim.api.nvim_get_current_buf()')
    Send-Keys $g2 $case.Keys
    $before = Wait-Mode $g2 $case.Mode
    $textBefore = Invoke-Lua $g2 'return table.concat(vim.api.nvim_buf_get_lines(vim.g.oin_prev, 0, -1, false), "|")'
    $modeFile = New-TestFile ('mode ' + $case.Name + '.txt')
    $res = Open-File $modeFile $only2
    $after = Wait-Mode $g2 'n'
    $textAfter = Invoke-Lua $g2 'return table.concat(vim.api.nvim_buf_get_lines(vim.g.oin_prev, 0, -1, false), "|")'
    $cmdType = Invoke-Lua $g2 'return vim.fn.getcmdtype()'
    Assert-That ("from " + $case.Name + " mode: file visible, Normal mode, earlier buffer untouched") (($before -ceq $case.Mode) -and ($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $modeFile) -and ($after -eq 'n') -and ($cmdType -eq '') -and ($textAfter -ceq $textBefore) -and ((Get-FirstLine $g2) -eq ('content of mode ' + $case.Name + '.txt'))) "before=[$before] after=[$after] cmdtype=[$cmdType] text=[$textBefore]->[$textAfter] code=$($res.Code)"
  }
  Reset-Instance $g2
  [void](Invoke-Lua $g2 'vim.cmd("terminal cmd.exe"); vim.g.oin_term = vim.api.nvim_get_current_buf()')
  Send-Keys $g2 'i'
  $before = Wait-Mode $g2 't'
  # Not a nicety: Neovim 0.12.2 itself crashes (0xC0000005) when the window of a terminal buffer that is
  # only some 50 ms old is split, also over a plain RPC connection without this launcher. A terminal
  # that has been running for a second is fine, which is the only case a click can ever meet.
  Start-Sleep -Milliseconds 1500
  $termFile = New-TestFile 'mode terminal.txt'
  $res = Open-File $termFile $only2
  $after = Wait-Mode $g2 'n'
  $termState = Invoke-Lua $g2 'return string.format("valid=%s shown=%d wins=%d", tostring(vim.api.nvim_buf_is_valid(vim.g.oin_term)), #vim.fn.win_findbuf(vim.g.oin_term), #vim.api.nvim_tabpage_list_wins(0))'
  Assert-That 'from terminal mode: file in a new window, Normal mode, the terminal keeps its window' (($before -eq 't') -and ($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $termFile) -and ($after -eq 'n') -and ($termState -eq 'valid=true shown=1 wins=2')) ("before=[$before] after=[$after] $termState code=$($res.Code) log=" + ($res.Log -join ' / '))
  [void](Invoke-Lua $g2 'pcall(vim.api.nvim_buf_delete, vim.g.oin_term, { force = true })')

  Reset-Instance $g2
  [void](Invoke-Lua $g2 'local b = vim.api.nvim_create_buf(false, true); vim.g.oin_fb = b; vim.g.oin_fw = vim.api.nvim_open_win(b, true, { relative = "editor", row = 2, col = 2, width = 30, height = 5 })')
  $floatFile = New-TestFile 'from float.txt'
  $res = Open-File $floatFile $only2
  $floatState = Invoke-Lua $g2 'return string.format("curfloat=%s floatkeeps=%s", tostring(vim.api.nvim_win_get_config(0).relative ~= ""), tostring(vim.api.nvim_win_is_valid(vim.g.oin_fw) and vim.api.nvim_win_get_buf(vim.g.oin_fw) == vim.g.oin_fb))'
  Assert-That 'floating window current: the file goes to a normal window, the float keeps its buffer' (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $floatFile) -and ($floatState -eq 'curfloat=false floatkeeps=true')) $floatState

  Reset-Instance $g2
  [void](Invoke-Lua $g2 'vim.cmd("file pinned"); vim.wo.winfixbuf = true; vim.g.oin_pw = vim.api.nvim_get_current_win(); vim.g.oin_pb = vim.api.nvim_get_current_buf()')
  $pinFile = New-TestFile 'next to pinned.txt'
  $res = Open-File $pinFile $only2
  $pinState = Invoke-Lua $g2 'return string.format("pinnedkeeps=%s wins=%d curpinned=%s", tostring(vim.api.nvim_win_get_buf(vim.g.oin_pw) == vim.g.oin_pb), #vim.api.nvim_tabpage_list_wins(0), tostring(vim.api.nvim_get_current_win() == vim.g.oin_pw))'
  Assert-That "'winfixbuf' on the only window: a new split, the pinned window keeps its buffer" (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $pinFile) -and ($pinState -eq 'pinnedkeeps=true wins=2 curpinned=false')) $pinState
  Reset-Instance $g2
  [void](Invoke-Lua $g2 'vim.cmd("vsplit"); vim.cmd("enew"); vim.g.oin_ow = vim.api.nvim_get_current_win(); vim.cmd("wincmd p"); vim.cmd("file pinned2"); vim.wo.winfixbuf = true; vim.g.oin_pw = vim.api.nvim_get_current_win(); vim.g.oin_pb = vim.api.nvim_get_current_buf()')
  $pinFile2 = New-TestFile 'other window.txt'
  $res = Open-File $pinFile2 $only2
  $pinState = Invoke-Lua $g2 'return string.format("pinnedkeeps=%s wins=%d inother=%s", tostring(vim.api.nvim_win_get_buf(vim.g.oin_pw) == vim.g.oin_pb), #vim.api.nvim_tabpage_list_wins(0), tostring(vim.api.nvim_get_current_win() == vim.g.oin_ow))'
  Assert-That "'winfixbuf' and another normal window: the file goes there, no split" (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $pinFile2) -and ($pinState -eq 'pinnedkeeps=true wins=2 inother=true')) $pinState

  Reset-Instance $g2
  [void](Invoke-Lua $g2 'vim.o.hidden = false; vim.cmd("file unsaved"); vim.api.nvim_buf_set_lines(0, 0, -1, false, { "not saved" }); vim.g.oin_db = vim.api.nvim_get_current_buf()')
  $dirtyFile = New-TestFile 'next to unsaved.txt'
  $res = Open-File $dirtyFile $only2
  $dirtyState = Invoke-Lua $g2 'return string.format("loaded=%s modified=%s shown=%d wins=%d", tostring(vim.api.nvim_buf_is_loaded(vim.g.oin_db)), tostring(vim.bo[vim.g.oin_db].modified), #vim.fn.win_findbuf(vim.g.oin_db), #vim.api.nvim_tabpage_list_wins(0))'
  Assert-That 'nohidden + modified buffer: a split, the unsaved buffer stays on screen' (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $dirtyFile) -and ($dirtyState -eq 'loaded=true modified=true shown=1 wins=2') -and ((Get-Mode $g2) -eq 'n')) $dirtyState
  Reset-Instance $g2
  [void](Invoke-Lua $g2 'vim.o.hidden = false; vim.o.confirm = true; vim.cmd("file unsaved2"); vim.api.nvim_buf_set_lines(0, 0, -1, false, { "not saved" })')
  $dirtyFile2 = New-TestFile 'next to unsaved 2.txt'
  $res = Open-File $dirtyFile2 $only2
  Assert-That "nohidden + 'confirm' + modified buffer: no dialog, a split" (($res.Code -eq 0) -and ($res.Ms -lt 5000) -and ((Get-CurrentName $g2) -ceq $dirtyFile2) -and ((Get-Mode $g2) -eq 'n'))

  Reset-Instance $g2
  $tabFile = New-TestFile 'in tab two.txt'
  [void](Invoke-Lua $g2 'vim.cmd("tabnew"); vim.cmd("silent edit " .. vim.fn.fnameescape(...)); vim.cmd("tabfirst")' @($tabFile))
  $res = Open-File $tabFile $only2
  $tabState = Invoke-Lua $g2 'local n = 0; for _, b in ipairs(vim.api.nvim_list_bufs()) do if vim.api.nvim_buf_get_name(b) == ... then n = n + 1 end end; return string.format("tab=%d tabs=%d buffers=%d wins=%d", vim.api.nvim_tabpage_get_number(0), #vim.api.nvim_list_tabpages(), n, #vim.fn.win_findbuf(vim.fn.bufnr(...)))' @($tabFile)
  Assert-That 'already shown in another tabpage: go there, no duplicate buffer, no second window' (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $tabFile) -and ($tabState -eq 'tab=2 tabs=2 buffers=1 wins=1')) $tabState

  Reset-Instance $g2; Reset-Instance $g1
  Send-Keys $g2 'q:'
  Start-Sleep -Milliseconds 300
  $cmdwinFile = New-TestFile 'cmdwin.txt'
  $res = Open-File $cmdwinFile
  Assert-That 'command-line window open (the editor refuses with E11): the next instance gets the file' (($res.Code -eq 0) -and ((Get-CurrentName $g1) -ceq $cmdwinFile) -and (@($res.Log | Where-Object { $_ -like '*(Refused)*E11*' }).Count -eq 1)) ("log=" + ($res.Log -join ' / '))
  Send-Keys $g2 '<C-c><C-c>'
  Start-Sleep -Milliseconds 200
  Reset-Instance $g2

  # -------------------------------------------------------------------------------------------
  Write-Host '== stable pipe nvim-<USERNAME>'
  Reset-Instance $g2; Reset-Instance $g1; Reset-Instance $ln
  $userA = 'oin_p1_a_' + $tag
  $stableA = '\\.\pipe\nvim-' + $userA
  $started = Invoke-Lua $g1 'return vim.fn.serverstart(...)' @($stableA)
  $res = Invoke-Oin ('current "' + $target + '"') @{ OPEN_IN_NVIM_DRYRUN = '1'; USERNAME = $userA }
  $cands = Get-Candidates $res
  Assert-That 'the verified owner of the stable pipe goes first (here: the OLDER instance), under its own pipe' (($started -eq $stableA) -and ($cands.Count -eq 2) -and ($cands[0] -eq ($pipe1 + ' pid=' + $Pids.gui1)) -and ($cands[1] -like ($pipe2 + ' *'))) ("cands=" + ($cands -join ' , ') + " log=" + ($res.Log -join ' / '))
  $stableFile = New-TestFile 'via stable pipe.txt'
  $res = Open-File $stableFile @{ USERNAME = $userA }
  Assert-That 'the file opens in the owner of the stable pipe' (($res.Code -eq 0) -and ((Get-CurrentName $g1) -ceq $stableFile) -and (-not (Test-HasBuffer $g2 $stableFile)))
  Set-Ini @{ PREFER_STABLE_PIPE = 'false' }
  $res = Invoke-Oin ('current "' + $target + '"') @{ OPEN_IN_NVIM_DRYRUN = '1'; USERNAME = $userA }
  $cands = Get-Candidates $res
  Assert-That 'PREFER_STABLE_PIPE = false: plain newest-first order' (($cands.Count -eq 2) -and ($cands[0] -like ($pipe2 + ' *'))) ("cands=" + ($cands -join ' , '))
  Set-Ini $null
  [void](Invoke-Lua $g1 'return vim.fn.serverstop(...)' @($stableA))

  $userH = 'oin_p1_h_' + $tag
  $stableH = '\\.\pipe\nvim-' + $userH
  [void](Invoke-Lua $hl 'return vim.fn.serverstart(...)' @($stableH))
  $three = "$($Pids.gui1),$($Pids.gui2),$($Pids.headless)"
  $res = Invoke-Oin ('current "' + $target + '"') @{ OPEN_IN_NVIM_DRYRUN = '1'; USERNAME = $userH; OPEN_IN_NVIM_ONLY_PIDS = $three }
  $cands = Get-Candidates $res
  Assert-That 'stable pipe owned by a headless instance: ignored' (($cands.Count -eq 2) -and ($cands[0] -like ($pipe2 + ' *')) -and ($cands[1] -like ($pipe1 + ' *'))) ("cands=" + ($cands -join ' , ') + " log=" + ($res.Log -join ' / '))
  $headlessFile = New-TestFile 'not for headless.txt'
  $res = Open-File $headlessFile @{ USERNAME = $userH; OPEN_IN_NVIM_ONLY_PIDS = $three }
  Assert-That 'the file goes to the newest editor, not into the headless owner' (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $headlessFile) -and (-not (Test-HasBuffer $hl $headlessFile)))
  [void](Invoke-Lua $hl 'return vim.fn.serverstop(...)' @($stableH))

  $withListen = "$($Pids.gui1),$($Pids.gui2),$($Pids.listen1)"
  $res = Invoke-Oin ('current "' + $target + '"') @{ OPEN_IN_NVIM_DRYRUN = '1'; USERNAME = $userListen; OPEN_IN_NVIM_ONLY_PIDS = $withListen }
  $cands = Get-Candidates $res
  Assert-That 'owner without a default pipe (--listen): the stable pipe is its address, first' (($cands.Count -eq 3) -and ($cands[0] -eq ($listenPipe + ' pid=' + $Pids.listen1))) ("cands=" + ($cands -join ' , ') + " log=" + ($res.Log -join ' / '))
  $listenFile = New-TestFile 'via listen pipe.txt'
  $res = Open-File $listenFile @{ USERNAME = $userListen; OPEN_IN_NVIM_ONLY_PIDS = $withListen }
  Assert-That 'the file opens in the --listen instance' (($res.Code -eq 0) -and ((Get-CurrentName $ln) -ceq $listenFile) -and (-not (Test-HasBuffer $g2 $listenFile)))
  $res = Invoke-Oin ('current "' + $target + '"') @{ OPEN_IN_NVIM_DRYRUN = '1'; USERNAME = $userListen }
  $cands = Get-Candidates $res
  Assert-That 'ONLY_PIDS also gates the stable pipe: an owner outside the list is not a candidate' (($cands.Count -eq 2) -and (@($cands | Where-Object { $_ -like '*nvim-*' }).Count -eq 0) -and (@($res.Log | Where-Object { $_ -like '*not in OPEN_IN_NVIM_ONLY_PIDS*' }).Count -eq 1)) ("cands=" + ($cands -join ' , '))

  # -------------------------------------------------------------------------------------------
  Write-Host '== NVIM_SERVER'
  Reset-Instance $g2; Reset-Instance $g1; Reset-Instance $tc
  $srvPipe = '\\.\pipe\oin-p1-server-' + $tag
  [void](Invoke-Lua $g1 'return vim.fn.serverstart(...)' @($srvPipe))
  Set-Ini @{ NVIM_SERVER = $srvPipe }
  $res = Invoke-Oin ('current "' + $target + '"') @{ OPEN_IN_NVIM_DRYRUN = '1' }
  $cands = Get-Candidates $res
  Assert-That 'NVIM_SERVER pipe: its verified owner goes first' (($cands.Count -eq 2) -and ($cands[0] -eq ($pipe1 + ' pid=' + $Pids.gui1))) ("cands=" + ($cands -join ' , ') + " log=" + ($res.Log -join ' / '))
  $srvFile = New-TestFile 'via server pipe.txt'
  $res = Open-File $srvFile
  Assert-That 'the file opens in the NVIM_SERVER instance' (($res.Code -eq 0) -and ((Get-CurrentName $g1) -ceq $srvFile))
  [void](Invoke-Lua $g1 'return vim.fn.serverstop(...)' @($srvPipe))

  $deadPipe = '\\.\pipe\oin-p1-nobody-' + $tag
  Set-Ini @{ NVIM_SERVER = $deadPipe; NVIM_BIN = $nvim }
  $deadFile = New-TestFile 'server pipe missing.txt'
  $res = Open-File $deadFile
  Assert-That 'NVIM_SERVER pipe nobody serves: straight on to the running instances' (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $deadFile) -and ($res.Ms -lt 1000)) "code=$($res.Code) ms=$($res.Ms)"
  $res = Invoke-Oin ('current "' + $deadFile + '"') @{ OPEN_IN_NVIM_ONLY_PIDS = '999999'; OPEN_IN_NVIM_NO_SPAWN = $null; OPEN_IN_NVIM_SPAWN_DRYRUN = '1' }
  $spawn = @($res.Lines | Where-Object { $_ -like 'spawn: *' })
  Assert-That 'no instance at all: the new instance would listen on that free name' (($res.Code -eq 0) -and ($spawn.Count -eq 1) -and $spawn[0].Contains('"--listen" "' + $deadPipe + '"') -and $spawn[0].Contains('"--" "' + $deadFile + '"')) ("out=" + ($res.Lines -join ' / '))

  $tcpAddr = '127.0.0.1:' + $tcpPort
  Set-Ini @{ NVIM_SERVER = $tcpAddr }
  $tcpFile = New-TestFile 'via tcp.txt'
  $res = Open-File $tcpFile
  Assert-That 'TCP NVIM_SERVER is refused in ONLY_PIDS mode without OPEN_IN_NVIM_ALLOW_TCP' (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $tcpFile) -and (-not (Test-HasBuffer $tc $tcpFile)) -and (@($res.Log | Where-Object { $_ -like '*not used: OPEN_IN_NVIM_ONLY_PIDS*' }).Count -eq 1)) ("log=" + ($res.Log -join ' / '))
  $tcpFile2 = New-TestFile 'via tcp 2 $USERNAME [1].txt'
  $res = Invoke-Oin ('current "' + $tcpFile2 + '"') @{ OPEN_IN_NVIM_DRYRUN = '1'; OPEN_IN_NVIM_ALLOW_TCP = '1' }
  $cands = Get-Candidates $res
  Assert-That 'TCP candidate goes first' (($cands.Count -eq 3) -and ($cands[0] -eq ($tcpAddr + ' pid=0'))) ("cands=" + ($cands -join ' , '))
  $res = Open-File $tcpFile2 @{ OPEN_IN_NVIM_ALLOW_TCP = '1' }
  Assert-That 'reachable host:port: the file opens there, over the same RPC client' (($res.Code -eq 0) -and ((Get-CurrentName $tc) -ceq $tcpFile2) -and ((Get-FirstLine $tc) -eq 'content of via tcp 2 $USERNAME [1].txt') -and (-not (Test-HasBuffer $g2 $tcpFile2))) ("log=" + ($res.Log -join ' / '))
  $res = Invoke-Oin ('current "' + $spaceDir + '"') @{ OPEN_IN_NVIM_ALLOW_TCP = '1' }
  Assert-That 'a folder over TCP: cd + directory view (same snippet as over a pipe)' (($res.Code -eq 0) -and ((Invoke-Lua $tc 'return vim.fn.getcwd()') -ceq $spaceDir))

  Set-Ini @{ NVIM_SERVER = '127.0.0.1:1' }
  $unreachFile = New-TestFile 'tcp unreachable.txt'
  $res = Open-File $unreachFile @{ OPEN_IN_NVIM_ALLOW_TCP = '1'; OPEN_IN_NVIM_ONLY_PIDS = "$($Pids.gui2)" }
  Assert-That 'unreachable 127.0.0.1:1: falls through in under 600 ms and opens in the running instance' (($res.Code -eq 0) -and ($res.Ms -lt 600) -and ((Get-CurrentName $g2) -ceq $unreachFile)) "code=$($res.Code) ms=$($res.Ms)"
  Write-Host ("       (unreachable TCP address + open elsewhere: {0:F0} ms)" -f $res.Ms)
  $res = Open-File $unreachFile @{ OPEN_IN_NVIM_ALLOW_TCP = '1'; OPEN_IN_NVIM_ONLY_PIDS = '999999' }
  Assert-That 'unreachable address and no instance: exit 3 in under 600 ms' (($res.Code -eq 3) -and ($res.Ms -lt 600)) "code=$($res.Code) ms=$($res.Ms)"
  Add-Type -AssemblyName System.Management
  $children = @((New-Object System.Management.ManagementObjectSearcher("SELECT ProcessId, Name FROM Win32_Process WHERE ParentProcessId = $($res.ProcId)")).Get())
  Assert-That 'no nvim.exe (or anything else) was started for the unreachable address' ($children.Count -eq 0) ("children=" + (($children | ForEach-Object { $_['Name'] }) -join ','))
  Set-Ini $null

  # -------------------------------------------------------------------------------------------
  Write-Host '== trust: pipes served by a process that is not Neovim'
  Reset-Instance $g2; Reset-Instance $g1
  $userS = 'oin_p1_s_' + $tag
  $namesFile = Join-Path $tmp 'fake names.txt'
  $fakeLog = Join-Path $tmp 'fake server.log'
  $hostileName = 'oin_p1_' + $tag + '_bad|name'
  $fakeNames = @(
    ('nvim-' + $userS),                       # the stable per-user name
    ('nvim.' + $Pids.gui1 + '.1'),            # a second pipe "of" a real editor
    ('nvim.' + $Pids.listen1 + '.0'),         # the default name of a real editor that has none
    'nvim.99999999999.0',                     # a PID that fits no int
    $hostileName                              # characters that are illegal in paths
  )
  [IO.File]::WriteAllLines($namesFile, [string[]]$fakeNames, (New-Object System.Text.UTF8Encoding($false)))
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $ps51
  $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -FakeServerNames "' + $namesFile + '" -FakeServerLog "' + $fakeLog + '" -FakeServerSeconds 90'
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $fakeProc = [Diagnostics.Process]::Start($psi)
  $t0 = [DateTime]::UtcNow; $ready = $false
  while (-not $ready -and ([DateTime]::UtcNow - $t0).TotalSeconds -lt 30) {
    Start-Sleep -Milliseconds 200
    if ([IO.File]::Exists($fakeLog)) { $ready = (@([IO.File]::ReadAllLines($fakeLog) | Where-Object { $_ -like 'ready pid=*' }).Count -eq 1) }
  }
  if (-not $ready) { throw 'the fake pipe server did not come up in 30 s' }
  $created = @([IO.File]::ReadAllLines($fakeLog) | Where-Object { $_ -like 'created *' })
  Assert-That 'the fake server (powershell.exe) owns all five names' ($created.Count -eq 5) ("log=" + ([IO.File]::ReadAllText($fakeLog)))
  $listed = [OpenInNvim.Pipes]::List()
  Assert-That 'the launcher still lists the namespace, hostile name included' (($listed -contains $hostileName) -and ($listed -contains 'nvim.99999999999.0'))
  $getFilesThrows = $false
  try { [void][IO.Directory]::GetFiles('\\.\pipe\') } catch { $getFilesThrows = $true }
  Write-Host ("       (Directory.GetFiles on the pipe namespace throws now: $getFilesThrows)")

  # The fake server's own PID is put on the ONLY_PIDS list on purpose: the gate must not be what saves us.
  $trustPids = "$($Pids.gui1),$($Pids.gui2),$($Pids.listen1),$($fakeProc.Id)"
  $res = Invoke-Oin ('current "' + $target + '"') @{ OPEN_IN_NVIM_DRYRUN = '1'; USERNAME = $userS; OPEN_IN_NVIM_ONLY_PIDS = $trustPids }
  $cands = Get-Candidates $res
  Assert-That 'squatted names are no candidates; discovery is undisturbed' (($res.Code -eq 0) -and ($cands.Count -eq 2) -and ($cands[0] -eq ($pipe2 + ' pid=' + $Pids.gui2)) -and ($cands[1] -eq ($pipe1 + ' pid=' + $Pids.gui1))) ("cands=" + ($cands -join ' , ') + " log=" + ($res.Log -join ' / '))
  Assert-That 'stable name: refused because the server is not nvim.exe' (@($res.Log | Where-Object { $_ -like ('*skip \\.\pipe\nvim-' + $userS + ': served by powershell.exe, not by nvim.exe*') }).Count -eq 1) ("log=" + ($res.Log -join ' / '))
  Assert-That 'nvim.<pid>.0 of a real editor: refused because the server is not the PID in the name' (@($res.Log | Where-Object { $_ -like ('*nvim.' + $Pids.listen1 + '.0: served by pid ' + $fakeProc.Id + ', not by the pid in its name*') }).Count -eq 1) ("log=" + ($res.Log -join ' / '))
  $trustFile = New-TestFile 'trust.txt'
  $res = Open-File $trustFile @{ USERNAME = $userS; OPEN_IN_NVIM_ONLY_PIDS = $trustPids }
  Assert-That 'the real open lands in the real editor' (($res.Code -eq 0) -and ((Get-CurrentName $g2) -ceq $trustFile))
  # Only the editor behind nvim.<listen1>.0 is on the list now: the squatted pipe is its ONLY default name.
  $res = Open-File $trustFile @{ USERNAME = $userS; OPEN_IN_NVIM_ONLY_PIDS = "$($Pids.listen1),$($fakeProc.Id)" }
  Assert-That 'with nothing but squatted names: exit 3, nothing sent' ($res.Code -eq 3) "code=$($res.Code) log=$($res.Log -join ' / ')"
  # The squatter holds nvim.<pid>.0, the editor itself then gets nvim.<pid>.1: the lowest name is refused,
  # the next one is served by the right process and is used.
  $realPipe = Invoke-Lua $ln 'for _ = 1, 3 do local ok, addr = pcall(vim.fn.serverstart); if ok and addr ~= "" then return addr end end; return ""'
  $fallbackFile = New-TestFile 'second default pipe.txt'
  $res = Open-File $fallbackFile @{ USERNAME = $userS; OPEN_IN_NVIM_ONLY_PIDS = "$($Pids.listen1),$($fakeProc.Id)" }
  Assert-That 'a squatted lowest pipe name does not hide the editor behind the next one' (($realPipe -eq ('\\.\pipe\nvim.' + $Pids.listen1 + '.1')) -and ($res.Code -eq 0) -and ((Get-CurrentName $ln) -ceq $fallbackFile) -and (@($res.Log | Where-Object { $_ -like ('*usable: \\.\pipe\nvim.' + $Pids.listen1 + '.1 *') }).Count -eq 1)) ("pipe=[$realPipe] code=$($res.Code) log=" + ($res.Log -join ' / '))
  [void](Invoke-Lua $ln 'return vim.fn.serverstop(...)' @($realPipe))
  Start-Sleep -Milliseconds 300
  $fakeLines = @([IO.File]::ReadAllLines($fakeLog))
  Assert-That 'the fake server never received a single byte' (@($fakeLines | Where-Object { $_ -like 'received *' }).Count -eq 0) ("fake log=" + ($fakeLines -join ' / '))
  Assert-That 'but it was connected to (the identity check needs a connection)' (@($fakeLines | Where-Object { $_ -like 'client came and went on *' }).Count -ge 2) ("fake log=" + ($fakeLines -join ' / '))
  # Control: the fake server does log what it is sent, and it answers like an idle editor. Without this,
  # "never received a byte" could simply mean that its logging is broken.
  $control = New-Object System.IO.Pipes.NamedPipeClientStream('.', ('nvim-' + $userS), [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
  $controlRead = 0
  try {
    $control.Connect(3000)
    $control.Write([byte[]](0x01, 0x02, 0x03), 0, 3)
    $control.Flush()
    $controlBuffer = New-Object byte[] 64
    $controlTask = $control.ReadAsync($controlBuffer, 0, 64)
    if ($controlTask.Wait(3000)) { $controlRead = $controlTask.Result }
  } finally { $control.Dispose() }
  Start-Sleep -Milliseconds 200
  Assert-That 'control: bytes written to the fake server are logged and answered' ((@([IO.File]::ReadAllLines($fakeLog) | Where-Object { $_ -eq ('received 3 bytes on nvim-' + $userS) }).Count -eq 1) -and ($controlRead -eq 36)) ("read=$controlRead fake log=" + ([IO.File]::ReadAllLines($fakeLog) -join ' / '))
  try { if (-not $fakeProc.HasExited) { $fakeProc.Kill() } } catch {}
  $fakeProc.WaitForExit(5000) | Out-Null

  # -------------------------------------------------------------------------------------------
  Write-Host '== exit codes, hooks, new-instance seam'
  $res = Open-File $target @{ OPEN_IN_NVIM_ONLY_PIDS = '999999' }
  Assert-That 'no instance + NO_SPAWN: exit 3 and "no reachable instance"' (($res.Code -eq 3) -and ($res.Lines -contains 'no reachable instance') -and ($res.Log[-1] -match 'exit 3$'))
  $res = Invoke-Oin ('bogus "' + $target + '"')
  Assert-That 'unknown mode: exit 1 and a usage line on stderr' (($res.Code -eq 1) -and ($res.Err -like '*usage: OpenInNvim.exe current|new*'))
  $res = Invoke-Oin ''
  Assert-That 'no arguments: exit 1' ($res.Code -eq 1)
  $res = Invoke-Oin ('new "' + $target + '"')
  Assert-That '"new" with NO_SPAWN: exit 3, nothing started' (($res.Code -eq 3) -and (@($res.Log | Where-Object { $_ -like '*spawn suppressed*' }).Count -eq 1))
  Set-Ini @{ NVIM_BIN = $nvim }
  $spawnEnv = @{ OPEN_IN_NVIM_NO_SPAWN = $null; OPEN_IN_NVIM_SPAWN_DRYRUN = '1' }
  $res = Invoke-Oin ('new "' + $target + '"') $spawnEnv
  $spawn = @($res.Lines | Where-Object { $_ -like 'spawn: *' })
  Assert-That '"new" with SPAWN_DRYRUN: prints "spawn: <exe> <command line>" and the working directory' (($res.Code -eq 0) -and ($spawn.Count -eq 1) -and ($spawn[0] -eq ('spawn: ' + $nvim + ' "--" "' + $target + '"')) -and ($res.Lines -contains ('spawn-cwd: ' + $tmp))) ("out=" + ($res.Lines -join ' / '))
  $res = Invoke-Oin ('new "' + $spaceDir + '\"') $spawnEnv
  $spawn = @($res.Lines | Where-Object { $_ -like 'spawn: *' })
  Assert-That 'a folder: no file argument, the folder is the working directory' (($res.Code -eq 0) -and ($spawn.Count -eq 1) -and (-not $spawn[0].Contains('"--"')) -and ($res.Lines -contains ('spawn-cwd: ' + $spaceDir))) ("out=" + ($res.Lines -join ' / '))
  $res = Invoke-Oin ('current "' + $target + '"') @{ OPEN_IN_NVIM_ONLY_PIDS = '999999'; OPEN_IN_NVIM_NO_SPAWN = $null; OPEN_IN_NVIM_SPAWN_DRYRUN = '1' }
  $spawn = @($res.Lines | Where-Object { $_ -like 'spawn: *' })
  Assert-That '"current" without a usable instance goes through the same spawner; no --listen by default' (($res.Code -eq 0) -and ($spawn.Count -eq 1) -and (-not $spawn[0].Contains('--listen')) -and $spawn[0].Contains('"--" "' + $target + '"')) ("out=" + ($res.Lines -join ' / '))
  # -------------------------------------------------------------------------------------------
  Write-Host '== terminals for a new instance'
  # Fake terminals: empty files named like the programs, in a private PATH folder.
  $termDir = [string](Join-Path $tmp 'terms'); [void][IO.Directory]::CreateDirectory($termDir)
  foreach ($n in 'wezterm-gui.exe', 'wt.exe') { [IO.File]::WriteAllBytes((Join-Path $termDir $n), [byte[]]@()) }
  $semiDir = [string](Join-Path $tmp 'a;b'); [void][IO.Directory]::CreateDirectory($semiDir)
  $semiFile = New-TestFile 'x;y.txt' $semiDir
  function Get-Via { param($Res) return @($Res.Lines | Where-Object { $_ -like 'spawn-via: *' } | ForEach-Object { $_.Substring(11) }) }
  Set-Ini @{ NVIM_BIN = $nvim }
  $res = Invoke-Oin ('new "' + $target + '"') ($spawnEnv + @{ PATH = $termDir })
  $via = @(Get-Via $res)
  Assert-That 'TERMINAL = auto: WezTerm, then Windows Terminal, then the console' (($via.Count -eq 3) -and ($via[0] -like 'wezterm *') -and ($via[1] -like 'wt *') -and ($via[2] -like 'console *')) ("via=" + ($via -join ' / '))
  Assert-That 'WezTerm: start --cwd <dir> -- <nvim> -- <file>' ($via[0] -eq ('wezterm ' + (Join-Path $termDir 'wezterm-gui.exe') + ' "start" "--cwd" "' + $tmp + '" "--" "' + $nvim + '" "--" "' + $target + '"')) ("via=" + $via[0])
  Assert-That 'Windows Terminal: -w 0 nt -d <dir> -- <nvim> -- <file>' ($via[1] -eq ('wt ' + (Join-Path $termDir 'wt.exe') + ' "-w" "0" "nt" "-d" "' + $tmp + '" "--" "' + $nvim + '" "--" "' + $target + '"')) ("via=" + $via[1])
  Assert-That 'console: Neovim itself, no cmd.exe anywhere' (($via[2] -eq ('console ' + $nvim + ' "--" "' + $target + '"')) -and (@($via | Where-Object { $_ -match 'cmd\.exe' }).Count -eq 0))
  $res = Invoke-Oin ('new "' + $semiFile + '"') ($spawnEnv + @{ PATH = $termDir })
  $via = @(Get-Via $res)
  Assert-That 'Windows Terminal: a ";" in a name is written "\;" (its command separator)' (($via[1].Contains('a\;b')) -and ($via[1].Contains('x\;y.txt')) -and ($via[0].Contains('a;b')) -and (-not $via[0].Contains('\;'))) ("via=" + ($via -join ' / '))
  Set-Ini @{ NVIM_BIN = $nvim; TERMINAL = 'wt' }
  $via = @(Get-Via (Invoke-Oin ('new "' + $target + '"') ($spawnEnv + @{ PATH = $termDir })))
  Assert-That 'TERMINAL = wt: Windows Terminal, console as the fallback' (($via.Count -eq 2) -and ($via[0] -like 'wt *') -and ($via[1] -like 'console *')) ("via=" + ($via -join ' / '))
  Set-Ini @{ NVIM_BIN = $nvim; TERMINAL = 'console' }
  $via = @(Get-Via (Invoke-Oin ('new "' + $target + '"') ($spawnEnv + @{ PATH = $termDir })))
  Assert-That 'TERMINAL = console: only the console' (($via.Count -eq 1) -and ($via[0] -like 'console *')) ("via=" + ($via -join ' / '))
  Set-Ini @{ NVIM_BIN = $nvim; TERMINAL = 'wezterm' }
  $via = @(Get-Via (Invoke-Oin ('new "' + $target + '"') ($spawnEnv + @{ PATH = $pathA })))
  Assert-That 'a named terminal that is not installed falls back to the console' (($via.Count -eq 1) -and ($via[0] -like 'console *')) ("via=" + ($via -join ' / '))
  $wezCfg = [string](Join-Path $tmp 'my wez.exe'); [IO.File]::WriteAllBytes($wezCfg, [byte[]]@())
  Set-Ini @{ NVIM_BIN = $nvim; WEZTERM_BIN = $wezCfg }
  $via = @(Get-Via (Invoke-Oin ('new "' + $target + '"') ($spawnEnv + @{ PATH = $pathA })))
  Assert-That 'WEZTERM_BIN from the config wins over PATH' (($via.Count -ge 1) -and ($via[0] -like ('wezterm ' + $wezCfg + ' *'))) ("via=" + ($via -join ' / '))

  Assert-That 'PATH merge: inherited entries first, missing registry entries appended once' ([OpenInNvim.Spawner]::MergePath('C:\a;C:\b\', 'c:\B;C:\c;;C:\a') -eq 'C:\a;C:\b\;C:\c')
  Set-Ini @{ NVIM_BIN = $nvim }
  $res = Invoke-Oin ('new "' + $target + '"') ($spawnEnv + @{ PATH = $pathA; OPEN_IN_NVIM_NO_PATH_REFRESH = $null })
  Assert-That 'a cut-short inherited PATH is completed from the registry (dry run still exits 0)' ($res.Code -eq 0) ("out=" + $res.Text)

  # -------------------------------------------------------------------------------------------
  Write-Host '== chooser (INSTANCE_PICK = ask) and focus'
  foreach ($rpc in $g1, $g2) { Reset-Instance $rpc }
  $two = "$($Pids.gui1),$($Pids.gui2)"
  $askFile = New-TestFile 'ask me.txt'
  Set-Ini @{ INSTANCE_PICK = 'ask' }
  $res = Open-File $askFile @{ OPEN_IN_NVIM_ONLY_PIDS = $two; OPEN_IN_NVIM_PICK = '1' }
  Assert-That 'ask: the picked instance (second in the list = the older one) gets the file' (($res.Code -eq 0) -and (Test-HasBuffer $g1 $askFile) -and (-not (Test-HasBuffer $g2 $askFile))) ("log=" + ($res.Log -join ' / '))
  $askFile2 = New-TestFile 'ask me 2.txt'
  $res = Open-File $askFile2 @{ OPEN_IN_NVIM_ONLY_PIDS = $two; OPEN_IN_NVIM_PICK = '0' }
  Assert-That 'ask: picking the first entry opens in the newest' (($res.Code -eq 0) -and (Test-HasBuffer $g2 $askFile2) -and (-not (Test-HasBuffer $g1 $askFile2)))
  $askFile3 = New-TestFile 'ask me 3.txt'
  $res = Open-File $askFile3 @{ OPEN_IN_NVIM_ONLY_PIDS = $two; OPEN_IN_NVIM_PICK = '9' }
  Assert-That 'ask: cancelled -> exit 0, nothing opened anywhere, nothing started' (($res.Code -eq 0) -and (-not (Test-HasBuffer $g1 $askFile3)) -and (-not (Test-HasBuffer $g2 $askFile3)) -and (@($res.Log | Where-Object { $_ -like '*chooser cancelled*' }).Count -eq 1))
  $res = Open-File $askFile3 @{ OPEN_IN_NVIM_ONLY_PIDS = "$($Pids.gui1)"; OPEN_IN_NVIM_PICK = '9' }
  Assert-That 'ask with a single usable instance: no chooser, it just opens' (($res.Code -eq 0) -and (Test-HasBuffer $g1 $askFile3))
  Set-Ini @{ FOCUS_TERMINAL = 'true' }
  $focusFile = New-TestFile 'focus me.txt'
  $res = Open-File $focusFile @{ OPEN_IN_NVIM_ONLY_PIDS = $two }
  Assert-That 'FOCUS_TERMINAL: best effort, the open still succeeds and the attempt is logged' (($res.Code -eq 0) -and (Test-HasBuffer $g2 $focusFile) -and (@($res.Log | Where-Object { $_ -like '*focus*' }).Count -ge 1)) ("log=" + ($res.Log -join ' / '))
  Assert-That 'Focus.FindHostWindow of a process without any window in its ancestry is zero or a real window, never an exception' ($true -eq ([OpenInNvim.Focus]::FindHostWindow(4) -is [IntPtr]))

  Set-Ini @{ NVIM_BIN = (Join-Path $tmp 'no such nvim.exe') }
  $res = Invoke-Oin ('new "' + $target + '"') ($spawnEnv + @{ PATH = $pathA })
  Assert-That 'Neovim neither configured nor on PATH: exit 1 (nothing startable)' (($res.Code -eq 1) -and (@($res.Log | Where-Object { $_ -like '*nothing startable*' }).Count -eq 1)) "code=$($res.Code) out=$($res.Text)"
  Set-Ini @{ INSTANCE_PICK = 'sideways'; NO_SUCH_KEY = 'x' }
  $res = Open-File $target
  Assert-That 'config: a bad value and an unknown key are logged, the click still works' (($res.Code -eq 0) -and (@($res.Log | Where-Object { $_ -like '*config: *' }).Count -eq 2)) ("log=" + ($res.Log -join ' / '))
  Set-Ini $null
  $res = Invoke-Bounded -Exe $exe -ArgLine ('current "' + $target + '"') -Env @{ OPEN_IN_NVIM_ONLY_PIDS = '999999'; OPEN_IN_NVIM_NO_SPAWN = '1'; OPEN_IN_NVIM_NO_UI = '1'; USERNAME = $fakeUser; OPEN_IN_NVIM_LOG = $null; OPEN_IN_NVIM_DRYRUN = $null } -Cwd $tmp
  Assert-That 'without OPEN_IN_NVIM_LOG no log file is written' (($res.Code -eq 3) -and (@([IO.Directory]::GetFiles($bin)).Count -eq 1)) ("files=" + ([IO.Directory]::GetFiles($bin) -join ','))

  # -------------------------------------------------------------------------------------------
  Write-Host '== install.ps1 / uninstall.ps1 (throw-away registry key and folder)'
  $regKey = 'Software\oin_native_test_' + $tag
  $instDir = [string](Join-Path $tmp 'inst dir')
  function Invoke-Script {
    param([string]$Script, [string]$ArgLine, [string]$Cwd = $tmp)
    return (Invoke-Bounded -Exe $ps51 -ArgLine ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Root $Script) + '" ' + $ArgLine) -Cwd $Cwd -LimitMs 120000)
  }
  function Get-Command-Value {
    param([string]$Sub)
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($regKey + '\' + $Sub + '\command')
    if (-not $k) { return $null }
    try { return [string]$k.GetValue('') } finally { $k.Close() }
  }
  try {
    $res = Invoke-Script 'install.ps1' ('-InstallDir "' + $instDir + '" -ClassesKey "' + $regKey + '" -NvimExe "' + $nvim + '"')
    $instExe = Join-Path $instDir 'OpenInNvim.exe'
    Assert-That 'install: exit 0, exe built, ini and manifest written' (($res.Code -eq 0) -and [IO.File]::Exists($instExe) -and [IO.File]::Exists((Join-Path $instDir 'open-in-nvim.ini')) -and [IO.File]::Exists((Join-Path $instDir 'install.manifest.txt'))) ("out=" + $res.Text)
    Assert-That 'install: the ini names the given nvim.exe' (@([IO.File]::ReadAllLines((Join-Path $instDir 'open-in-nvim.ini')) | Where-Object { $_ -eq ('NVIM_BIN = ' + $nvim) }).Count -eq 1)
    $cmdFile = Get-Command-Value '*\shell\Open_in_Neovim_current'
    $cmdNew = Get-Command-Value 'Directory\shell\Open_in_Neovim_new'
    $cmdBg = Get-Command-Value 'Directory\Background\shell\Open_in_Neovim_current'
    Assert-That 'install: commands name the exe by its full quoted path, with the mode and "%1" / "%V"' (($cmdFile -eq ('"' + $instExe + '" current "%1"')) -and ($cmdNew -eq ('"' + $instExe + '" new "%1"')) -and ($cmdBg -eq ('"' + $instExe + '" current "%V"'))) ("file=$cmdFile new=$cmdNew bg=$cmdBg")
    [IO.File]::AppendAllText((Join-Path $instDir 'open-in-nvim.ini'), "`r`n# mine`r`n")
    $res = Invoke-Script 'install.ps1' ('-InstallDir "' + $instDir + '" -ClassesKey "' + $regKey + '" -NvimExe "' + $nvim + '"')
    Assert-That 'install again: the existing ini is kept' (($res.Code -eq 0) -and ([IO.File]::ReadAllText((Join-Path $instDir 'open-in-nvim.ini')).Contains('# mine')))
    $res = Invoke-Script 'install.ps1' ('-InstallDir "rel inst" -ClassesKey "' + $regKey + '" -NvimExe "' + $nvim + '"')
    $cmdRel = Get-Command-Value '*\shell\Open_in_Neovim_current'
    Assert-That 'install with a relative -InstallDir: the registry holds the absolute path' (($res.Code -eq 0) -and ($cmdRel -eq ('"' + (Join-Path (Join-Path $tmp 'rel inst') 'OpenInNvim.exe') + '" current "%1"'))) ("cmd=$cmdRel")
    # An old-version folder: its files go, its config is converted.
    $oldDir = [string](Join-Path $tmp 'old inst'); [void][IO.Directory]::CreateDirectory($oldDir)
    foreach ($n in 'open-in-nvim.vbs', 'open-in-nvim-current.ps1', 'open-in-nvim.lib.ps1') { [IO.File]::WriteAllText((Join-Path $oldDir $n), 'old') }
    [IO.File]::WriteAllText((Join-Path $oldDir 'open-in-nvim.config.ps1'), "`$Cfg = [ordered]@{ NVIM_BIN = 'x'; INSTANCE_PICK = 'oldest'; FOCUS_TERMINAL = `$true; NVIM_SERVER = '' }")
    $res = Invoke-Script 'install.ps1' ('-InstallDir "' + $oldDir + '" -ClassesKey "' + $regKey + '" -NvimExe "' + $nvim + '"')
    $iniLines = @([IO.File]::ReadAllLines((Join-Path $oldDir 'open-in-nvim.ini')))
    Assert-That 'install over the old version: old files removed, config converted' (($res.Code -eq 0) -and (-not [IO.File]::Exists((Join-Path $oldDir 'open-in-nvim.vbs'))) -and (-not [IO.File]::Exists((Join-Path $oldDir 'open-in-nvim.config.ps1'))) -and ($iniLines -contains 'INSTANCE_PICK = oldest') -and ($iniLines -contains 'FOCUS_TERMINAL = true') -and ($iniLines -contains ('NVIM_BIN = ' + $nvim))) ("ini=" + ($iniLines -join ' / '))
    $res = Invoke-Script 'install.ps1' ('-InstallDir "' + (Join-Path $tmp 'dry') + '" -ClassesKey "' + $regKey + '_dry" -NvimExe "' + $nvim + '" -DryRun')
    Assert-That 'install -DryRun: nothing written' (($res.Code -eq 0) -and (-not [IO.Directory]::Exists((Join-Path $tmp 'dry'))) -and ($null -eq [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($regKey + '_dry')))
    $res = Invoke-Script 'uninstall.ps1' ('-InstallDir "' + $instDir + '" -ClassesKey "' + $regKey + '" -RemoveFiles')
    Assert-That 'uninstall -RemoveFiles: entries gone, exe gone, config kept' (($res.Code -eq 0) -and ($null -eq (Get-Command-Value '*\shell\Open_in_Neovim_current')) -and (-not [IO.File]::Exists($instExe)) -and [IO.File]::Exists((Join-Path $instDir 'open-in-nvim.ini'))) ("out=" + $res.Text)
    # The installed exe really works (built by install.ps1, not by the suite).
    $res = Invoke-Script 'install.ps1' ('-InstallDir "' + $instDir + '" -ClassesKey "' + $regKey + '" -NvimExe "' + $nvim + '"')
    $run = Invoke-Bounded -Exe $instExe -ArgLine ('current "' + $target + '"') -Env @{ OPEN_IN_NVIM_ONLY_PIDS = $editors; OPEN_IN_NVIM_NO_SPAWN = '1'; OPEN_IN_NVIM_NO_UI = '1'; USERNAME = $fakeUser; OPEN_IN_NVIM_DRYRUN = '1' } -Cwd $tmp
    Assert-That 'the installed exe runs (dry run lists candidates)' (($run.Code -eq 0) -and (@($run.Lines | Where-Object { $_ -like 'candidate: *' }).Count -ge 1)) ("out=" + $run.Text)
  }
  finally {
    try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($regKey, $false) } catch {}
  }

  # -------------------------------------------------------------------------------------------
  Write-Host '== timing (information only)'
  Reset-Instance $g2
  $times = @()
  for ($i = 0; $i -lt 6; $i++) { $r = Open-File $target @{ OPEN_IN_NVIM_LOG = $null }; if ($i -gt 0) { $times += $r.Ms } }
  $sorted = @($times | Sort-Object)
  Write-Host ("       launcher wall time, file -> newest of 2 instances, n=5: median {0:F0} ms, min {1:F0}, max {2:F0}" -f $sorted[2], $sorted[0], $sorted[4])
}
finally {
  foreach ($client in $clients) { try { $client.Dispose() } catch {} }
  if ($fakeProc) { try { if (-not $fakeProc.HasExited) { $fakeProc.Kill() } } catch {} }
  # Ask the fixture to stop its own children, then make sure only our own processes are gone.
  try { if ($stopFile) { [IO.File]::WriteAllText($stopFile, 'stop') } } catch {}
  if ($fixtureProc -and -not $fixtureProc.WaitForExit(10000)) { try { $fixtureProc.Kill() } catch {} }
  Start-Sleep -Milliseconds 500
  if ($Pids) {
    foreach ($id in $Pids.Values) {
      # A PID can be reused once its process is gone: only touch an nvim that started during this run.
      $left = Get-Process -Id $id -ErrorAction SilentlyContinue
      if ($left -and $left.ProcessName -eq 'nvim' -and $left.StartTime -ge $runStart) { try { $left.Kill() } catch {} }
    }
  }
  [Environment]::SetEnvironmentVariable('OIN_NATIVE_TEST_VAR', $null)
  Remove-OwnTree $tmp
}

Write-Host ''
Write-Host ("passed: {0}  failed: {1}" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0

# build-setup.ps1
# Builds the download: OpenInNvim-Setup.exe (installs without the repository, carries uninstall.exe) plus
# SHA256SUMS.txt, with the C# compiler that ships with Windows (no SDK, no Inno Setup, no NuGet).
# Windows PowerShell 5.1 compatible.
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File build-setup.ps1 [-OutDir <dir>]
#
# Default output folder: <repo>\dist (git-ignored). The last line printed is the path of the setup exe.
# Order: uninstall.exe, OpenInNvim.exe (build.ps1), then the setup exe with both inside it as resources.

param(
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $here 'version.ps1')
if (-not $OutDir) { $OutDir = Join-Path $here 'dist' }
$OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)

$csc = Get-OinCsc
if (-not $csc) { Write-Host 'build-setup.ps1: csc.exe not found under %SystemRoot%\Microsoft.NET'; exit 1 }

$stage = Join-Path ([IO.Path]::GetTempPath()) ('oin_setup_stage_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)
[void][IO.Directory]::CreateDirectory($OutDir)
$info = $null
try {
  $info = New-OinAssemblyInfo $here 'OpenInNvim setup'
  $common = Join-Path $here 'setup\Common.cs'
  $manifest = Join-Path $here 'setup\app.manifest'
  $refs = @('/reference:System.dll', '/reference:System.Core.dll', '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll')
  $base = @('/nologo', '/noconfig', '/target:winexe', '/optimize+', '/warnaserror+', '/platform:anycpu', ('/win32manifest:' + $manifest)) + $refs

  function Invoke-Csc {
    param([string[]]$CscArgs, [string]$Out)
    $output = & $csc $CscArgs 2>&1
    $code = $LASTEXITCODE
    foreach ($line in @($output)) { Write-Host "$line" }
    if ($code -ne 0 -or -not [IO.File]::Exists($Out)) { Write-Host "build-setup.ps1: csc failed for $Out (exit code $code)"; exit 1 }
  }

  # 1) uninstall.exe
  $uninstall = Join-Path $stage 'uninstall.exe'
  Invoke-Csc -Out $uninstall -CscArgs ($base + @(('/out:' + $uninstall), $common, (Join-Path $here 'setup\UninstallProgram.cs'), $info))

  # 2) OpenInNvim.exe (the same build as install.ps1 makes)
  & (Join-Path $here 'build.ps1') -OutDir $stage | Out-Null
  $launcher = Join-Path $stage 'OpenInNvim.exe'
  if ($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($launcher)) { Write-Host 'build-setup.ps1: build.ps1 failed'; exit 1 }

  # 3) the setup exe, with everything it installs inside
  $setup = Join-Path $OutDir 'OpenInNvim-Setup.exe'
  $resources = @(
    ('/resource:' + $launcher + ',OpenInNvim.exe'),
    ('/resource:' + $uninstall + ',uninstall.exe'),
    ('/resource:' + (Join-Path $here 'open-in-nvim.ini') + ',open-in-nvim.ini'),
    ('/resource:' + (Join-Path $here 'Logos\new-session.ico') + ',new-session.ico'),
    ('/resource:' + (Join-Path $here 'Logos\current-session.ico') + ',current-session.ico'),
    ('/resource:' + (Join-Path $here 'file-extensions.ps1') + ',file-extensions.ps1')
  )
  Invoke-Csc -Out $setup -CscArgs ($base + $resources + @(('/out:' + $setup), $common, (Join-Path $here 'setup\SetupProgram.cs'), $info))

  # 4) checksums (.NET directly: no module function that an inherited PSModulePath could hide)
  $sha = [Security.Cryptography.SHA256]::Create()
  $lines = @()
  foreach ($f in @($setup)) {
    $bytes = $sha.ComputeHash([IO.File]::ReadAllBytes($f))
    $hex = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    $lines += ($hex + ' *' + (Split-Path -Leaf $f))
  }
  [IO.File]::WriteAllLines((Join-Path $OutDir 'SHA256SUMS.txt'), [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ('version ' + (Get-OinVersion $here))
  Write-Host $setup
}
finally {
  if ($info -and [IO.File]::Exists($info)) { [IO.File]::Delete($info) }
  try { [IO.Directory]::Delete($stage, $true) } catch {}
}
exit 0

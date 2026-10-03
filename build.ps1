# build.ps1
# Builds OpenInNvim.exe from src\*.cs with the C# compiler that ships with Windows (.NET Framework 4.x,
# no SDK, no NuGet). Windows PowerShell 5.1 compatible.
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 [-OutDir <dir>]
#
# Default output folder: <repo>\bin (git-ignored). Prints the path of the built exe; exit code 1 on failure.
# That compiler is C# 5: no string interpolation, no ?., no nameof, no expression-bodied members.

param(
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $OutDir) { $OutDir = Join-Path $here 'bin' }
# Absolute: csc resolves /out: against ITS working directory, which need not be the caller's.
$OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)

$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not [IO.File]::Exists($csc)) { $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not [IO.File]::Exists($csc)) {
  Write-Host 'build.ps1: csc.exe not found under %SystemRoot%\Microsoft.NET\Framework64\v4.0.30319 (or Framework\)'
  exit 1
}

$src = Join-Path $here 'src'
if (@([IO.Directory]::GetFiles($src, '*.cs')).Count -eq 0) {
  Write-Host "build.ps1: no sources in $src"
  exit 1
}
[void][IO.Directory]::CreateDirectory($OutDir)
$exe = Join-Path $OutDir 'OpenInNvim.exe'

# /noconfig: only the references named here, not the default csc.rsp list.
# System.Windows.Forms / System.Drawing are for the chooser and the error dialog only; an assembly that
# no executed code path touches is never loaded, so they cost a click nothing.
$cscArgs = @(
  '/nologo', '/noconfig', '/target:winexe', '/optimize+', '/warnaserror+', '/platform:anycpu',
  ('/out:' + $exe),
  '/reference:System.dll', '/reference:System.Core.dll', '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll',
  (Join-Path $src '*.cs')
)

$output = & $csc $cscArgs 2>&1
$code = $LASTEXITCODE
foreach ($line in @($output)) { Write-Host "$line" }
if ($code -ne 0 -or -not [IO.File]::Exists($exe)) {
  Write-Host "build.ps1: csc failed (exit code $code)"
  exit 1
}
Write-Host $exe
exit 0

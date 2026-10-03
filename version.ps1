# version.ps1
# Dot-sourced by build.ps1 and build-setup.ps1: the version number lives in the VERSION file only.
# Windows PowerShell 5.1 compatible.

function Get-OinVersion {
  <#
    .SYNOPSIS
      The version from the VERSION file ("1.2.3"), checked to be three numbers.
  #>
  param([string]$Root)
  $text = ([IO.File]::ReadAllText((Join-Path $Root 'VERSION'))).Trim()
  if ($text -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION must look like 1.2.3, got '$text'" }
  return $text
}

function New-OinAssemblyInfo {
  <#
    .SYNOPSIS
      Write a throw-away AssemblyInfo source file (temp folder) carrying the version, and return its path.
      The caller deletes it after compiling.
  #>
  param([string]$Root, [string]$Title)
  $v = Get-OinVersion $Root
  $path = Join-Path ([IO.Path]::GetTempPath()) ('oin_assemblyinfo_' + [Guid]::NewGuid().ToString('N') + '.cs')
  $code = @(
    'using System.Reflection;',
    ('[assembly: AssemblyTitle("' + $Title + '")]'),
    '[assembly: AssemblyCompany("Stefan Bartl")]',
    '[assembly: AssemblyProduct("OpenInNvim")]',
    ('[assembly: AssemblyVersion("' + $v + '.0")]'),
    ('[assembly: AssemblyFileVersion("' + $v + '.0")]'),
    ('[assembly: AssemblyInformationalVersion("' + $v + '")]')
  )
  [IO.File]::WriteAllLines($path, [string[]]$code, (New-Object System.Text.UTF8Encoding($false)))
  return $path
}

function Get-OinCsc {
  $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  if (-not [IO.File]::Exists($csc)) { $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
  if (-not [IO.File]::Exists($csc)) { return $null }
  return $csc
}

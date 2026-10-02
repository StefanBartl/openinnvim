# verify.ps1
# Verifies both context-menu workflows end to end (VBS -> PS1 -> nvim).
# One file and one folder are tested for each.

param(
  [string]$FileTarget = "$env:USERPROFILE\Desktop\openin-test.txt",
  [string]$DirTarget  = "$env:USERPROFILE\Desktop"
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here -or $Here -eq '') {
  $scriptPath = $MyInvocation.MyCommand.Path
  if ($scriptPath -and $scriptPath -ne '') { $Here = Split-Path -Path $scriptPath -Parent } else { $Here = $PWD.Path }
}

$VbsNew     = Join-Path $Here 'open-in-nvim.vbs'
$VbsCurrent = Join-Path $Here 'open-in-nvim-current.vbs'

if (-not (Test-Path -LiteralPath $VbsNew))     { throw "VBS (new) fehlt: $VbsNew" }
if (-not (Test-Path -LiteralPath $VbsCurrent)) { throw "VBS (current) fehlt: $VbsCurrent" }

Write-Host "Test 1/4: NEW instance, file..."
wscript.exe //nologo "$VbsNew" "$FileTarget"

Write-Host "Test 2/4: NEW instance, directory..."
wscript.exe //nologo "$VbsNew" "$DirTarget"

Write-Host "Test 3/4: CURRENT instance, file..."
wscript.exe //nologo "$VbsCurrent" "$FileTarget"

Write-Host "Test 4/4: CURRENT instance, directory..."
wscript.exe //nologo "$VbsCurrent" "$DirTarget"

Write-Host "Verify finished. If no windows appeared: check NVIM_BIN/WEZTERM_BIN or set OPEN_IN_NVIM_DEBUG=1."

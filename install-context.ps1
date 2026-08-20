# install-context.ps1
# Installiert zwei Explorer-Kontextmenüeinträge unter HKCU:
#  - Open with Neovim (new instance)
#  - Open with Neovim (current instance)
# Entfernt zuvor gängige Altlasten (HKCU/HKLM).
# Default-Installationspfad: C:\tools\OpenInNvim

param(
  [string]$InstallPath = 'C:\tools\OpenInNvim'
)

$ErrorActionPreference = 'Stop'

function Ensure-Path {
  param([string]$p)
  if (-not (Test-Path -LiteralPath $p)) {
    New-Item -ItemType Directory -Path $p -Force | Out-Null
  }
}

function Remove-Key {
  param([string]$key)
  try {
    if (Test-Path -LiteralPath $key) {
      Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop
      Write-Host "Removed: $key"
    }
  } catch {
    Write-Warning "Could not remove $key: $($_.Exception.Message)"
  }
}

function Set-Menu {
  param([string]$baseKey, [string]$display, [string]$command, [string]$icon)
  New-Item -Path $baseKey -Force | Out-Null
  New-ItemProperty -Path $baseKey -Name '(default)' -Value $display -PropertyType String -Force | Out-Null
  if ($icon) { New-ItemProperty -Path $baseKey -Name 'Icon' -Value $icon -PropertyType String -Force | Out-Null }
  New-Item -Path ($baseKey + '\command') -Force | Out-Null
  New-ItemProperty -Path ($baseKey + '\command') -Name '(default)' -Value $command -PropertyType String -Force | Out-Null
}

# 1) Dateien prüfen
Ensure-Path $InstallPath
$psNew      = Join-Path $InstallPath 'open-in-nvim.ps1'
$vbsNew     = Join-Path $InstallPath 'open-in-nvim.vbs'
$psCurrent  = Join-Path $InstallPath 'open-in-nvim-current.ps1'
$vbsCurrent = Join-Path $InstallPath 'open-in-nvim-current.vbs'
$config     = Join-Path $InstallPath 'open-in-nvim.config.ps1'

foreach ($f in @($psNew, $vbsNew, $psCurrent, $vbsCurrent)) {
  if (-not (Test-Path -LiteralPath $f)) { throw "Required file missing: $f" }
}

# 2) Altlasten entfernen
$targets = @(
  'HKCU:\Software\Classes\*\shell\Open_in_Neovim',
  'HKCU:\Software\Classes\*\shell\Open_in_Neovim_nvr',
  'HKCU:\Software\Classes\*\shell\Open_in_Neovim_new_hidden',
  'HKCU:\Software\Classes\*\shell\Open_in_Neovim_Debug',
  'HKCU:\Software\Classes\*\shell\Open_in_Neovim_new',
  'HKCU:\Software\Classes\*\shell\Open_in_Neovim_current',
  'HKCU:\Software\Classes\Directory\shell\Open_in_Neovim',
  'HKCU:\Software\Classes\Directory\shell\Open_in_Neovim_nvr',
  'HKCU:\Software\Classes\Directory\shell\Open_in_Neovim_new_hidden',
  'HKCU:\Software\Classes\Directory\shell\Open_in_Neovim_Debug',
  'HKCU:\Software\Classes\Directory\shell\Open_in_Neovim_new',
  'HKCU:\Software\Classes\Directory\shell\Open_in_Neovim_current',
  'HKCU:\Software\Classes\Directory\Background\shell\Open_in_Neovim',
  'HKCU:\Software\Classes\Directory\Background\shell\Open_in_Neovim_nvr',
  'HKCU:\Software\Classes\Directory\Background\shell\Open_in_Neovim_new_hidden',
  'HKCU:\Software\Classes\Directory\Background\shell\Open_in_Neovim_Debug',
  'HKCU:\Software\Classes\Directory\Background\shell\Open_in_Neovim_new',
  'HKCU:\Software\Classes\Directory\Background\shell\Open_in_Neovim_current',

  'HKLM:\Software\Classes\*\shell\Open_in_Neovim',
  'HKLM:\Software\Classes\*\shell\Open_in_Neovim_nvr',
  'HKLM:\Software\Classes\*\shell\Open_in_Neovim_new_hidden',
  'HKLM:\Software\Classes\*\shell\Open_in_Neovim_Debug',
  'HKLM:\Software\Classes\*\shell\Open_in_Neovim_new',
  'HKLM:\Software\Classes\*\shell\Open_in_Neovim_current',
  'HKLM:\Software\Classes\Directory\shell\Open_in_Neovim',
  'HKLM:\Software\Classes\Directory\shell\Open_in_Neovim_nvr',
  'HKLM:\Software\Classes\Directory\shell\Open_in_Neovim_new_hidden',
  'HKLM:\Software\Classes\Directory\shell\Open_in_Neovim_Debug',
  'HKLM:\Software\Classes\Directory\shell\Open_in_Neovim_new',
  'HKLM:\Software\Classes\Directory\shell\Open_in_Neovim_current',
  'HKLM:\Software\Classes\Directory\Background\shell\Open_in_Neovim',
  'HKLM:\Software\Classes\Directory\Background\shell\Open_in_Neovim_nvr',
  'HKLM:\Software\Classes\Directory\Background\shell\Open_in_Neovim_new_hidden',
  'HKLM:\Software\Classes\Directory\Background\shell\Open_in_Neovim_Debug',
  'HKLM:\Software\Classes\Directory\Background\shell\Open_in_Neovim_new',
  'HKLM:\Software\Classes\Directory\Background\shell\Open_in_Neovim_current'
)
foreach ($k in $targets) { Remove-Key $k }

# 3) Einträge anlegen
$displayNew     = 'Open with Neovim (new instance)'
$displayCurrent = 'Open with Neovim (current instance)'
$icon           = 'C:\Program Files\Neovim\bin\nvim.exe'

$wscript = (Get-Command -Name 'wscript.exe' -ErrorAction SilentlyContinue)
if ($wscript) { $wscript = $wscript.Source } else { $wscript = 'wscript.exe' }

$cmdNew     = $wscript + ' //nologo "' + $vbsNew.Replace('"','""')     + '"'
$cmdCurrent = $wscript + ' //nologo "' + $vbsCurrent.Replace('"','""') + '"'

# Dateien
Set-Menu -baseKey 'HKCU:\Software\Classes\*\shell\Open_in_Neovim_new'     -display $displayNew     -command ($cmdNew + ' "%1"') -icon $icon
Set-Menu -baseKey 'HKCU:\Software\Classes\*\shell\Open_in_Neovim_current' -display $displayCurrent -command ($cmdCurrent + ' "%1"') -icon $icon

# Ordner
Set-Menu -baseKey 'HKCU:\Software\Classes\Directory\shell\Open_in_Neovim_new'     -display $displayNew     -command ($cmdNew + ' "%1"') -icon $icon
Set-Menu -baseKey 'HKCU:\Software\Classes\Directory\shell\Open_in_Neovim_current' -display $displayCurrent -command ($cmdCurrent + ' "%1"') -icon $icon

# Ordner-Hintergrund
Set-Menu -baseKey 'HKCU:\Software\Classes\Directory\Background\shell\Open_in_Neovim_new'     -display $displayNew     -command ($cmdNew + ' "%V"') -icon $icon
Set-Menu -baseKey 'HKCU:\Software\Classes\Directory\Background\shell\Open_in_Neovim_current' -display $displayCurrent -command ($cmdCurrent + ' "%V"') -icon $icon

Write-Host 'Kontextmenü installiert:'
Write-Host "  * $displayNew"
Write-Host "  * $displayCurrent"
Write-Host 'Hinweis: Explorer neu starten (taskkill /F /IM explorer.exe ; explorer.exe)'
